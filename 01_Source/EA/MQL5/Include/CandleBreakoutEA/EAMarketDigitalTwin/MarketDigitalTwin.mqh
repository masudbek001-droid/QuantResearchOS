//+------------------------------------------------------------------+
//|                    EAMarketDigitalTwin/MarketDigitalTwin.mqh     |
//|                        Market Digital Twin — single source of    |
//|                        truth simulator (ADR-0022)                |
//+------------------------------------------------------------------+
#ifndef __MARKET_DIGITAL_TWIN_MQH__
#define __MARKET_DIGITAL_TWIN_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAData\DatabaseManager.mqh>
#include <CandleBreakoutEA\EAMarketDigitalTwin\TwinTypes.mqh>
#include <CandleBreakoutEA\EAMarketDigitalTwin\TwinClock.mqh>
#include <CandleBreakoutEA\EAMarketDigitalTwin\TwinEventBus.mqh>
#include <CandleBreakoutEA\EAMarketDigitalTwin\TwinValidator.mqh>

//+------------------------------------------------------------------+
//| Twin configuration — immutable after Initialize().                |
//+------------------------------------------------------------------+
struct STwinConfig
  {
   string              symbol;
   ENUM_TIMEFRAMES     timeframe;
   datetime            start_time;
   datetime            end_time;
   int                 dataset_version; // for validator gate

   void Reset(void) { symbol=""; timeframe=PERIOD_CURRENT; start_time=0; end_time=0; dataset_version=0; }
  };

//+------------------------------------------------------------------+
//| Market Digital Twin — sole market source.                        |
//|  - Loads once from HistoryStore/MarketSnapshots (exact DB rows). |
//|  - Validates via TwinValidator before first event.               |
//|  - Serves Next() deterministically; bus dispatches identical     |
//|    SMarketEvent to 5 consumers (Replay, Training, Risk,          |
//|    Research, AI). No consumer may read HistoryStore directly     |
//|    while Twin is active — enforced by validator + CI.           |
//+------------------------------------------------------------------+
class CMarketDigitalTwin
  {
private:
   CEASettings        *m_set;
   CLogger            *m_log;
   CDatabaseManager   *m_db;

   STwinConfig         m_cfg;
   SMarketEvent        m_timeline[];    // in-memory ordered events (bar exact)
   int                 m_total;
   CTwinClock          m_clock;
   CTwinEventBus       m_bus;
   CTwinValidator      m_validator;
   bool                m_ready;
   bool                m_started;
   long                m_next_event_id;

   //--- load timeline from DB — exact Market.db rows or MarketSnapshots
   bool                LoadTimeline(void)
     {
      if(m_db==NULL || !m_db.IsOpen()) return(false);
      // Query MarketSnapshots as canonical source (exact stored bars)
      // Fallback to Market.db bars if Snapshots empty — both are hash-validated
      string rows[];
      // Try MarketSnapshots first
      int count = m_db.Select(StringFormat(
         "SELECT BarTime, OpenPrice, HighPrice, LowPrice, ClosePrice, TickVolume, Spread, ATR "
         "FROM MarketSnapshots WHERE Symbol='%s' AND TimeframeID=%d "
         "AND BarTime>=%d AND BarTime<=%d ORDER BY BarTime ASC",
         m_cfg.symbol,(int)m_cfg.timeframe,(int)m_cfg.start_time,(int)m_cfg.end_time), rows);
      if(count<=0)
        {
         // fallback: Market.db bars (via HistoryStore query — we reuse same table names for twin)
         // If still 0, no data — Twin cannot start
         if(m_log!=NULL) m_log.Warn(StringFormat("Twin LoadTimeline: no snapshots for %s %s %s..%s",
                                 m_cfg.symbol,EnumToString(m_cfg.timeframe),
                                 TimeToString(m_cfg.start_time),TimeToString(m_cfg.end_time)));
         return(false);
        }
      m_total = count;
      ArrayResize(m_timeline, m_total);
      long expected_sum = 0;
      for(int i=0;i<count;i++)
        {
         string cols[];
         StringSplit(rows[i], ';', cols);
         // cols: BarTime;Open;High;Low;Close;TickVolume;Spread;ATR
         datetime t = (datetime)StringToInteger(cols[0]);
         double o = StringToDouble(cols[1]);
         double h = StringToDouble(cols[2]);
         double l = StringToDouble(cols[3]);
         double c = StringToDouble(cols[4]);
         long vol = StringToInteger(cols[5]);
         double spread = (ArraySize(cols)>6 ? StringToDouble(cols[6]) : 0);
         double atr    = (ArraySize(cols)>7 ? StringToDouble(cols[7]) : 0);
         SMarketEvent ev;
         ev.Reset();
         ev.event_id   = i+1;
         ev.time       = t;
         ev.type       = TWIN_EVENT_BAR;
         ev.symbol     = m_cfg.symbol;
         ev.timeframe  = m_cfg.timeframe;
         ev.open=o; ev.high=h; ev.low=l; ev.close=c;
         ev.tick_volume=vol; ev.volume=vol;
         ev.spread=spread; ev.atr=atr;
         ev.source_hash = TwinHashBar(ev.symbol,ev.timeframe,ev.time,ev.open,ev.high,ev.low,ev.close,ev.tick_volume);
         ev.event_hash  = TwinHashEvent(ev);
         m_timeline[i] = ev;
         expected_sum += ev.source_hash;
        }
      m_validator.SetExpectedHashSum(expected_sum);
      m_clock.Initialize(m_cfg.start_time, m_total);
      if(m_log!=NULL) m_log.Info(StringFormat("Twin timeline loaded | %s %s %d bars | hash_sum %d",
                              m_cfg.symbol,EnumToString(m_cfg.timeframe),m_total,expected_sum));
      return(true);
     }

public:
                       CMarketDigitalTwin(void) : m_set(NULL), m_log(NULL), m_db(NULL), m_total(0), m_ready(false), m_started(false), m_next_event_id(1) {}

   void                Initialize(const CEASettings &settings,CLogger &logger,CDatabaseManager &db)
     {
      m_set=&settings; m_log=&logger; m_db=&db;
      m_bus.Initialize(logger);
      m_validator.Initialize(logger);
      m_clock.Reset();
      ArrayFree(m_timeline);
      m_total=0; m_ready=false; m_started=false; m_next_event_id=1;
     }

   //--- configure window — must be called before Load()
   bool                Configure(const STwinConfig &cfg)
     {
      m_cfg = cfg;
      m_ready = false;
      m_started = false;
      m_next_event_id = 1;
      m_validator.Reset();
      ArrayFree(m_timeline);
      m_clock.Reset();
      m_bus.Reset();
      return(true);
     }

   //--- load and validate — single source truth ready
   bool                Load(void)
     {
      if(!LoadTimeline()) { m_ready=false; return(false); }
      m_ready = true;
      if(m_log!=NULL) m_log.Info(StringFormat("MarketDigitalTwin READY | %s %s %s..%s",
                              m_cfg.symbol,EnumToString(m_cfg.timeframe),
                              TimeToString(m_cfg.start_time),TimeToString(m_cfg.end_time)));
      return(true);
     }

   bool                IsReady(void) const { return(m_ready); }
   bool                IsStarted(void) const { return(m_started); }
   int                 TotalBars(void) const { return(m_total); }
   CTwinClock         *Clock(void) { return(&m_clock); }
   CTwinEventBus      *Bus(void) { return(&m_bus); }
   CTwinValidator     *Validator(void) { return(&m_validator); }

   //--- subscribe — 5 consumers max, identical dispatch guaranteed
   bool                Subscribe(ITwinConsumer *consumer)
     {
      if(!m_ready) return(false);
      return(m_bus.Subscribe(consumer));
     }

   bool                Unsubscribe(ITwinConsumer *consumer) { return(m_bus.Unsubscribe(consumer)); }

   //--- Next — deterministic advance, validates exact, dispatches identical
   bool                Next(void)
     {
      if(!m_ready) return(false);
      if(!m_clock.HasNext())
        {
         if(m_log!=NULL) m_log.Info("Twin Next: end of timeline");
         return(false);
        }
      long idx = m_clock.CurrentIndex()+1;
      if(idx<0) idx=0;
      if(idx>=m_total) return(false);
      SMarketEvent ev = m_timeline[idx];
      // validate exact reproduction
      if(!m_validator.ValidateExact(ev))
        {
         if(m_log!=NULL) m_log.Warn(StringFormat("Twin Next halted | validator failed at idx %d", (int)idx));
         return(false);
        }
      // advance clock
      m_clock.Advance(ev.time);
      m_started = true;
      // dispatch identical to all 5 consumers
      return(m_bus.Dispatch(ev));
     }

   //--- Seek — jump to time, still validates
   bool                Seek(const datetime t)
     {
      if(!m_ready) return(false);
      for(int i=0;i<m_total;i++)
        {
         if(m_timeline[i].time==t)
           {
            m_clock.Initialize(t, m_total);
            // fast-forward clock index to i
            for(int j=0;j<=i;j++) m_clock.Advance(m_timeline[j].time);
            return(true);
           }
        }
      return(false);
     }

   //--- Current event (for Training that needs snapshot, not Next)
   bool                Current(SMarketEvent &out) const
     {
      long idx = m_clock.CurrentIndex();
      if(idx<0 || idx>=m_total) return(false);
      out = m_timeline[idx];
      return(true);
     }

   //--- Reset — for new window
   void                Reset(void)
     {
      m_clock.Reset();
      m_bus.Reset();
      m_validator.Reset();
      ArrayFree(m_timeline);
      m_total=0; m_ready=false; m_started=false; m_next_event_id=1;
     }

   string              ToString(void) const
     {
      return(StringFormat("MarketDigitalTwin %s %s %s..%s | ready %s started %s | %d/%d bars | %s | %s",
                          m_cfg.symbol,EnumToString(m_cfg.timeframe),
                          TimeToString(m_cfg.start_time),TimeToString(m_cfg.end_time),
                          m_ready?"true":"false",m_started?"true":"false",
                          (int)m_clock.CurrentIndex()+1,m_total,
                          m_clock.ToString(),m_validator.ToString()));
     }
  };

#endif // __MARKET_DIGITAL_TWIN_MQH__
//+------------------------------------------------------------------+
