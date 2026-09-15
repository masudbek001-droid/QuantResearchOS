//+------------------------------------------------------------------+
//|                    EAMarketDigitalTwin/TwinTypes.mqh             |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Market Digital Twin — single source of    |
//|                        truth event types (ADR-0022)              |
//+------------------------------------------------------------------+
#ifndef __TWIN_TYPES_MQH__
#define __TWIN_TYPES_MQH__

//+------------------------------------------------------------------+
//| Event type — the Twin emits the same sequence that history       |
//| stored. TICK is raw tick, BAR is OHLCV as stored in Market.db,  |
//| CANDLE_CLOSE is the H1/H4 close that trading decisions use.       |
//+------------------------------------------------------------------+
enum ENUM_TWIN_EVENT_TYPE
  {
   TWIN_EVENT_BAR          = 0, // OHLCV bar as stored (exact Market.db row)
   TWIN_EVENT_TICK         = 1, // raw tick as stored in Ticks.db (if available)
   TWIN_EVENT_CANDLE_CLOSE = 2  // derived close event (bar_time + 1 period)
  };

//+------------------------------------------------------------------+
//| Immutable market event — once emitted, bytes are identical for   |
//| every consumer. source_hash is FNV-1a of raw bar fields as       |
//| stored; event_hash is hash of this struct (proves identical      |
//| dispatch). No consumer may mutate.                               |
//+------------------------------------------------------------------+
struct SMarketEvent
  {
   long                event_id;      // monotonic 1..N per Twin session
   datetime            time;          // bar/tick time exactly as stored (UTC)
   ENUM_TWIN_EVENT_TYPE type;
   string              symbol;        // e.g., EURUSD
   ENUM_TIMEFRAMES     timeframe;     // e.g., PERIOD_M1, PERIOD_H1
   double              open;
   double              high;
   double              low;
   double              close;
   long                tick_volume;
   long                volume;        // real volume if available
   double              spread;        // as stored
   double              atr;           // snapshot atr if available (0 if tick)
   long                source_hash;   // FNV-1a of raw bar (open/high/low/close/volume/time)
   long                event_hash;    // FNV-1a of this struct's fields (dispatch proof)

   void Reset(void)
     {
      event_id=0; time=0; type=TWIN_EVENT_BAR;
      symbol=""; timeframe=PERIOD_CURRENT;
      open=0; high=0; low=0; close=0;
      tick_volume=0; volume=0; spread=0; atr=0;
      source_hash=0; event_hash=0;
     }
  };

//+------------------------------------------------------------------+
//| Consumer interface — Replay, Training, Risk, Research, AI all    |
//| implement this. Twin dispatches by value copy, guaranteeing       |
//| identical bytes per consumer.                                    |
//+------------------------------------------------------------------+
class ITwinConsumer
  {
public:
   virtual void        OnMarketEvent(const SMarketEvent &event) = 0;
   virtual string      ConsumerName(void) const = 0;
  };

//+------------------------------------------------------------------+
//| FNV-1a 64-bit hash for MQL5 — deterministic, fast, exact bytes   |
//+------------------------------------------------------------------+
long TwinFNV1a(const string data)
  {
   // FNV-1a 64-bit offset basis and prime, truncated to 63-bit for MQL5 long sign
   long hash = 1469598103934665601;
   const long prime = 1099511628211;
   for(int i=0; i<StringLen(data); i++)
     {
      hash ^= StringGetCharacter(data, i);
      hash *= prime;
     }
   // ensure positive (MQL5 long is signed 64)
   if(hash<0) hash = -hash;
   return(hash);
  }

long TwinHashBar(const string symbol,const ENUM_TIMEFRAMES tf,const datetime t,
                 const double o,const double h,const double l,const double c,
                 const long vol)
  {
   // canonical string: symbol|tf|time|o|h|l|c|vol with fixed precision
   string s = StringFormat("%s|%d|%d|%.5f|%.5f|%.5f|%.5f|%d",
                           symbol,(int)tf,(int)t,o,h,l,c,vol);
   return(TwinFNV1a(s));
  }

long TwinHashEvent(const SMarketEvent &e)
  {
   string s = StringFormat("%d|%d|%d|%s|%d|%.5f|%.5f|%.5f|%.5f|%d|%d|%.5f|%.5f|%d",
                           (int)e.event_id,(int)e.time,(int)e.type,
                           e.symbol,(int)e.timeframe,
                           e.open,e.high,e.low,e.close,
                           e.tick_volume,e.volume,e.spread,e.atr,
                           e.source_hash);
   return(TwinFNV1a(s));
  }

#endif // __TWIN_TYPES_MQH__
//+------------------------------------------------------------------+
