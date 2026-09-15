//+------------------------------------------------------------------+
//|                               EAReplay/ReplayTimeline.mqh        |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Replay: deterministic playback timeline   |
//+------------------------------------------------------------------+
#ifndef __EA_REPLAY_TIMELINE_MQH__
#define __EA_REPLAY_TIMELINE_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAData\DatabaseTypes.mqh>
#include <CandleBreakoutEA\EAData\DatabaseManager.mqh>
#include <CandleBreakoutEA\EAReplay\ReplayTypes.mqh>

//+------------------------------------------------------------------+
//| TASK 0014: the playback timeline. Deterministic by construction: |
//| the window is loaded once from the database, ordered by          |
//| SnapshotTime, and only walked in memory. No CopyRates, no broker |
//| calls of any kind - the database is the ONLY data source.        |
//+------------------------------------------------------------------+
class CReplayTimeline
  {
private:
   const CEASettings  *m_set;
   CLogger            *m_log;
   CDatabaseManager   *m_db;

   int                 m_dataset_version;
   int                 m_symbol_id;
   int                 m_timeframe_id;
   datetime            m_window_start;
   datetime            m_window_end;

   SReplaySnapshot     m_bars[];      // deterministic, SnapshotTime ascending
   int                 m_index;       // current position (-1 = not loaded)
   bool                m_loaded;

   bool                ParseSnapshotRow(const string &row,SReplaySnapshot &out)
     {
      string c[];
      if(StringSplit(row,';',c)!=23)
         return(false);
      out.Reset();
      out.snapshot_id     = StringToInteger(c[0]);
      out.bar_time        = (datetime)StringToInteger(c[1]);
      out.spread          = StringToDouble(c[2]);
      out.atr             = StringToDouble(c[3]);
      out.atr_ratio       = StringToDouble(c[4]);
      out.open            = StringToDouble(c[5]);
      out.high            = StringToDouble(c[6]);
      out.low             = StringToDouble(c[7]);
      out.close           = StringToDouble(c[8]);
      out.body_size       = StringToDouble(c[9]);
      out.body_percent    = StringToDouble(c[10]);
      out.upper_shadow    = StringToDouble(c[11]);
      out.lower_shadow    = StringToDouble(c[12]);
      out.range           = StringToDouble(c[13]);
      out.volatility      = StringToDouble(c[14]);
      out.trend_direction = (int)StringToInteger(c[15]);
      out.trend_strength  = StringToDouble(c[16]);
      out.session         = (int)StringToInteger(c[17]);
      out.hour            = (int)StringToInteger(c[18]);
      out.weekday         = (int)StringToInteger(c[19]);
      out.month           = (int)StringToInteger(c[20]);
      out.quarter         = (int)StringToInteger(c[21]);
      out.broker_offset   = (int)StringToInteger(c[22]);
      return(true);
     }

public:
                       CReplayTimeline(void) : m_set(NULL), m_log(NULL), m_db(NULL),
                          m_dataset_version(0), m_symbol_id(0), m_timeframe_id(0),
                          m_window_start(0), m_window_end(0), m_index(-1), m_loaded(false) {}

   void                Initialize(const CEASettings &settings,CLogger &logger,CDatabaseManager &db)
     {
      m_set = &settings;
      m_log = &logger;
      m_db  = &db;
     }

   //--- load the whole replay window once (deterministic order)
   bool                LoadReplayWindow(const int dataset_version,const int symbol_id,
                                        const int timeframe_id,const datetime start_time,
                                        const datetime end_time)
     {
      if(m_db==NULL || !m_db.IsOpen())
         return(false);
      ArrayResize(m_bars,0);
      m_index  = -1;
      m_loaded = false;

      string rows[];
      const int found = m_db.Select(StringFormat(
         "SELECT SnapshotID,SnapshotTime,Spread,ATR,ATRRatio,Open,High,Low,Close,"
         "BodySize,BodyPercent,UpperShadow,LowerShadow,\"Range\",Volatility,"
         "TrendDirection,TrendStrength,CurrentSession,CurrentHour,Weekday,Month,Quarter,"
         "BrokerOffset FROM %s WHERE SymbolID=%d AND TimeframeID=%d "
         "AND SnapshotTime>=%d AND SnapshotTime<=%d ORDER BY SnapshotTime ASC",
         DB_TABLE_SNAPSHOTS,symbol_id,timeframe_id,(int)start_time,(int)end_time),rows);
      if(found<=0)
        {
         m_log.Warn("Replay timeline rejected | window has no snapshots");
         return(false);
        }

      ArrayResize(m_bars,found);
      datetime previous = 0;
      for(int i=0; i<found; i++)
        {
         SReplaySnapshot bar;
         if(!ParseSnapshotRow(rows[i],bar))
           {
            m_log.Warn(StringFormat("Replay timeline rejected | unparsable row %d",i));
            ArrayResize(m_bars,0);
            return(false);
           }
         if(i>0 && bar.bar_time<=previous)
           {
            m_log.Warn("Replay timeline rejected | out of order / duplicate timestamp");
            ArrayResize(m_bars,0);
            return(false);
           }
         previous   = bar.bar_time;
         m_bars[i]  = bar;
        }

      m_dataset_version = dataset_version;
      m_symbol_id       = symbol_id;
      m_timeframe_id    = timeframe_id;
      m_window_start    = start_time;
      m_window_end      = end_time;
      m_index           = 0;
      m_loaded          = true;
      m_log.Info(StringFormat("Replay timeline loaded | %d bars | %s .. %s",found,
                              TimeToString(m_bars[0].bar_time,TIME_DATE|TIME_MINUTES),
                              TimeToString(m_bars[found-1].bar_time,TIME_DATE|TIME_MINUTES)));
      return(true);
     }

   //--- navigation
   bool                MoveNext(void)
     {
      if(!m_loaded || m_index>=ArraySize(m_bars)-1)
         return(false);
      m_index++;
      return(true);
     }

   bool                MovePrevious(void)
     {
      if(!m_loaded || m_index<=0)
         return(false);
      m_index--;
      return(true);
     }

   //--- last bar with SnapshotTime <= moment (false: before the window)
   bool                JumpToTime(const datetime moment)
     {
      if(!m_loaded)
         return(false);
      int found = -1;
      for(int i=0; i<ArraySize(m_bars); i++)
        {
         if(m_bars[i].bar_time<=moment)
            found = i;
         else
            break;
        }
      if(found<0)
         return(false);
      m_index = found;
      return(true);
     }

   bool                JumpToBar(const int index)
     {
      if(!m_loaded || index<0 || index>=ArraySize(m_bars))
         return(false);
      m_index = index;
      return(true);
     }

   //--- current recorded bar
   bool                GetCurrentSnapshot(SReplaySnapshot &out) const
     {
      if(!m_loaded || m_index<0 || m_index>=ArraySize(m_bars))
         return(false);
      out = m_bars[m_index];
      return(true);
     }

   //--- synchronize the observation recorded for the current bar
   bool                SynchronizeCurrentObservation(SReplayObservation &out)
     {
      if(!m_loaded || m_db==NULL)
         return(false);
      SReplaySnapshot bar;
      if(!GetCurrentSnapshot(bar))
         return(false);
      string rows[];
      if(m_db.Select(StringFormat(
            "SELECT ObservationID,BarTime,ObservationType,Session,Hour,Weekday,Month "
            "FROM %s WHERE SymbolID=%d AND TimeframeID=%d AND BarTime=%d LIMIT 1",
            DB_TABLE_OBSERVATIONS,m_symbol_id,m_timeframe_id,(int)bar.bar_time),rows)!=1)
         return(false);
      string c[];
      if(StringSplit(rows[0],';',c)!=7)
         return(false);
      out.observation_id = StringToInteger(c[0]);
      out.bar_time       = (datetime)StringToInteger(c[1]);
      out.type           = (int)StringToInteger(c[2]);
      out.session        = (int)StringToInteger(c[3]);
      out.hour           = (int)StringToInteger(c[4]);
      out.weekday        = (int)StringToInteger(c[5]);
      out.month          = (int)StringToInteger(c[6]);
      return(true);
     }

   //--- synchronize the dataset trade active during the current bar
   bool                SynchronizeCurrentTrade(SReplayTrade &out)
     {
      if(!m_loaded || m_db==NULL)
         return(false);
      SReplaySnapshot bar;
      if(!GetCurrentSnapshot(bar))
         return(false);
      const datetime bar_end = bar.bar_time+(datetime)PeriodSeconds((ENUM_TIMEFRAMES)m_timeframe_id);
      string rows[];
      if(m_db.Select(StringFormat(
            "SELECT t.Ticket,t.Direction,t.Lots,t.EntryTime,t.ExitTime,t.EntryPrice,"
            "t.ExitPrice,t.Profit,t.ExitReason FROM %s d "
            "JOIN %s t ON t.TradeID=d.TradeID "
            "WHERE d.DatasetVersion=%d AND d.TradeID IS NOT NULL "
            "AND t.EntryTime<%d AND (t.ExitTime IS NULL OR t.ExitTime>=%d) "
            "ORDER BY t.EntryTime DESC LIMIT 1",
            DB_TABLE_DATASETS,DB_TABLE_TRADES,m_dataset_version,
            (int)bar_end,(int)bar.bar_time),rows)!=1)
         return(false);
      string c[];
      if(StringSplit(rows[0],';',c)!=9)
         return(false);
      out.ticket      = StringToInteger(c[0]);
      out.direction   = (int)StringToInteger(c[1]);
      out.lots        = StringToDouble(c[2]);
      out.entry_time  = (datetime)StringToInteger(c[3]);
      out.exit_time   = (datetime)StringToInteger(c[4]);
      out.entry_price = StringToDouble(c[5]);
      out.exit_price  = StringToDouble(c[6]);
      out.profit      = StringToDouble(c[7]);
      out.exit_reason = (int)StringToInteger(c[8]);
      return(true);
     }

   //--- synchronize the ground-truth label of the current bar
   bool                SynchronizeCurrentLabel(SReplayLabel &out)
     {
      if(!m_loaded || m_db==NULL)
         return(false);
      SReplaySnapshot bar;
      if(!GetCurrentSnapshot(bar))
         return(false);
      string rows[];
      if(m_db.Select(StringFormat(
            "SELECT l.LabelID,l.LookaheadBars,l.FutureHigh,l.FutureLow,l.FutureClose,"
            "l.MaxFavorableExcursion,l.MaxAdverseExcursion,l.DirectionLabel,l.BreakoutSuccess "
            "FROM %s o JOIN %s l ON l.ObservationID=o.ObservationID "
            "WHERE o.SymbolID=%d AND o.TimeframeID=%d AND o.BarTime=%d "
            "ORDER BY l.LabelID DESC LIMIT 1",
            DB_TABLE_OBSERVATIONS,DB_TABLE_LABELS,
            m_symbol_id,m_timeframe_id,(int)bar.bar_time),rows)!=1)
         return(false);
      string c[];
      if(StringSplit(rows[0],';',c)!=9)
         return(false);
      out.label_id        = StringToInteger(c[0]);
      out.lookahead       = (int)StringToInteger(c[1]);
      out.future_high     = StringToDouble(c[2]);
      out.future_low      = StringToDouble(c[3]);
      out.future_close    = StringToDouble(c[4]);
      out.mfe             = StringToDouble(c[5]);
      out.mae             = StringToDouble(c[6]);
      out.direction       = (int)StringToInteger(c[7]);
      out.breakout_success= (int)StringToInteger(c[8]);
      return(true);
     }

   //--- state
   bool                IsLoaded(void)  const { return(m_loaded); }
   int                 CurrentIndex(void) const { return(m_index); }
   int                 TotalBars(void) const { return(ArraySize(m_bars)); }
   datetime            CurrentTime(void) const
     {
      SReplaySnapshot bar;
      return(GetCurrentSnapshot(bar) ? bar.bar_time : 0);
     }
   bool                AtEnd(void) const
     {
      return(!m_loaded || m_index>=ArraySize(m_bars)-1);
     }
  };

#endif // __EA_REPLAY_TIMELINE_MQH__
//+------------------------------------------------------------------+
