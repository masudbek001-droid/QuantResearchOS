//+------------------------------------------------------------------+
//|                              EAReplay/ReplayValidator.mqh        |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Replay: validation & consistency          |
//+------------------------------------------------------------------+
#ifndef __EA_REPLAY_VALIDATOR_MQH__
#define __EA_REPLAY_VALIDATOR_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAData\DatabaseTypes.mqh>
#include <CandleBreakoutEA\EAData\DatabaseManager.mqh>

//+------------------------------------------------------------------+
//| TASK 0015: integrity of a replay window. Every check reads only  |
//| the database. A replay whose integrity fails must stop.          |
//+------------------------------------------------------------------+
class CReplayValidator
  {
private:
   const CEASettings  *m_set;
   CLogger            *m_log;
   CDatabaseManager   *m_db;

   long                CountOf(const string sql)
     {
      string rows[];
      if(m_db.Select(sql,rows)!=1)
         return(-1);
      return(StringToInteger(rows[0]));
     }

public:
                       CReplayValidator(void) : m_set(NULL), m_log(NULL), m_db(NULL) {}

   void                Initialize(const CEASettings &settings,CLogger &logger,CDatabaseManager &db)
     {
      m_set = &settings;
      m_log = &logger;
      m_db  = &db;
     }

   //--- the window itself: ordered, non-empty, inside the recorded history
   bool                ValidateReplayRange(const int symbol_id,const int timeframe_id,
                                           const datetime start_time,const datetime end_time)
     {
      if(start_time<=0 || end_time<=start_time)
        { m_log.Warn("Replay range rejected | invalid bounds"); return(false); }
      const long bars = CountOf(StringFormat(
         "SELECT COUNT(*) FROM %s WHERE SymbolID=%d AND TimeframeID=%d "
         "AND SnapshotTime>=%d AND SnapshotTime<=%d",
         DB_TABLE_SNAPSHOTS,symbol_id,timeframe_id,(int)start_time,(int)end_time));
      if(bars<=0)
        { m_log.Warn("Replay range rejected | no snapshots in window"); return(false); }
      return(true);
     }

   //--- the dataset must exist and have passed the quality gate
   bool                ValidateDatasetVersion(const int dataset_version)
     {
      const long rows = CountOf(StringFormat(
         "SELECT COUNT(*) FROM %s WHERE DatasetVersion=%d",DB_TABLE_DATASETS,dataset_version));
      if(rows<=0)
        { m_log.Warn(StringFormat("Replay rejected | dataset v%d is empty",dataset_version)); return(false); }
      const long passed = CountOf(StringFormat(
         "SELECT COUNT(*) FROM %s WHERE DatasetVersion=%d AND QualityStatus=%d",
         DB_TABLE_QUALITY,dataset_version,(int)QUALITY_PASS));
      if(passed<=0)
        { m_log.Warn(StringFormat("Replay rejected | dataset v%d never passed quality",dataset_version)); return(false); }
      return(true);
     }

   //--- missing snapshots / duplicates / broken timeline inside the window
   bool                ValidateSnapshotContinuity(const int symbol_id,const int timeframe_id,
                                                  const datetime start_time,const datetime end_time)
     {
      string rows[];
      if(m_db.Select(StringFormat(
            "SELECT COUNT(*),COUNT(DISTINCT SnapshotTime),MIN(SnapshotTime),MAX(SnapshotTime) "
            "FROM %s WHERE SymbolID=%d AND TimeframeID=%d AND SnapshotTime>=%d AND SnapshotTime<=%d",
            DB_TABLE_SNAPSHOTS,symbol_id,timeframe_id,
            (int)start_time,(int)end_time),rows)!=1)
         return(false);
      string c[];
      if(StringSplit(rows[0],';',c)!=4)
         return(false);
      const long total    = StringToInteger(c[0]);
      const long distinct = StringToInteger(c[1]);
      const datetime lo   = (datetime)StringToInteger(c[2]);
      const datetime hi   = (datetime)StringToInteger(c[3]);
      if(total!=distinct)
        { m_log.Warn("Snapshot continuity failed | duplicate timestamps"); return(false); }
      const int tf_seconds = PeriodSeconds((ENUM_TIMEFRAMES)timeframe_id);
      if(tf_seconds<=0)
        { m_log.Warn("Snapshot continuity failed | invalid timeframe"); return(false); }
      const long expected = (long)((hi-lo)/tf_seconds)+1;
      if(total!=expected)
        {
         m_log.Warn(StringFormat("Snapshot continuity failed | missing bars (%d of %d)",
                                 (int)(expected-total),(int)expected));
         return(false);
        }
      return(true);
     }

   //--- one observation per recorded bar, no duplicates
   bool                ValidateObservationContinuity(const int symbol_id,const int timeframe_id,
                                                     const datetime start_time,const datetime end_time)
     {
      const long obs = CountOf(StringFormat(
         "SELECT COUNT(*) FROM %s WHERE SymbolID=%d AND TimeframeID=%d "
         "AND BarTime>=%d AND BarTime<=%d",
         DB_TABLE_OBSERVATIONS,symbol_id,timeframe_id,(int)start_time,(int)end_time));
      const long distinct = CountOf(StringFormat(
         "SELECT COUNT(DISTINCT BarTime) FROM %s WHERE SymbolID=%d AND TimeframeID=%d "
         "AND BarTime>=%d AND BarTime<=%d",
         DB_TABLE_OBSERVATIONS,symbol_id,timeframe_id,(int)start_time,(int)end_time));
      if(obs!=distinct)
        { m_log.Warn("Observation continuity failed | duplicate bar observations"); return(false); }
      const long snaps = CountOf(StringFormat(
         "SELECT COUNT(*) FROM %s WHERE SymbolID=%d AND TimeframeID=%d "
         "AND SnapshotTime>=%d AND SnapshotTime<=%d",
         DB_TABLE_SNAPSHOTS,symbol_id,timeframe_id,(int)start_time,(int)end_time));
      if(obs!=snaps)
        { m_log.Warn("Observation continuity failed | observations do not cover snapshots"); return(false); }
      return(true);
     }

   //--- dataset trade references must resolve and be time-consistent
   bool                ValidateTradeContinuity(const int dataset_version)
     {
      const long broken_fk = CountOf(StringFormat(
         "SELECT COUNT(*) FROM %s d LEFT JOIN %s t ON t.TradeID=d.TradeID "
         "WHERE d.DatasetVersion=%d AND d.TradeID IS NOT NULL AND t.TradeID IS NULL",
         DB_TABLE_DATASETS,DB_TABLE_TRADES,dataset_version));
      if(broken_fk!=0)
        { m_log.Warn("Trade continuity failed | broken trade references"); return(false); }
      const long reversed = CountOf(StringFormat(
         "SELECT COUNT(*) FROM %s d JOIN %s t ON t.TradeID=d.TradeID "
         "WHERE d.DatasetVersion=%d AND d.TradeID IS NOT NULL "
         "AND t.ExitTime IS NOT NULL AND t.ExitTime<t.EntryTime",
         DB_TABLE_DATASETS,DB_TABLE_TRADES,dataset_version));
      if(reversed!=0)
        { m_log.Warn("Trade continuity failed | exit before entry"); return(false); }
      return(true);
     }

   //--- a loaded timeline must be strictly increasing (out-of-order replay guard)
   bool                ValidateTimeline(const datetime &times[])
     {
      const int n = ArraySize(times);
      for(int i=1; i<n; i++)
         if(times[i]<=times[i-1])
           {
            m_log.Warn(StringFormat("Timeline invalid | out of order at index %d",i));
            return(false);
           }
      return(n>0);
     }

   //--- full integrity gate for one replay session
   bool                ValidateReplayIntegrity(const int dataset_version,const int symbol_id,
                                               const int timeframe_id,const datetime start_time,
                                               const datetime end_time)
     {
      if(!ValidateDatasetVersion(dataset_version))
         return(false);
      if(!ValidateReplayRange(symbol_id,timeframe_id,start_time,end_time))
         return(false);
      if(!ValidateSnapshotContinuity(symbol_id,timeframe_id,start_time,end_time))
         return(false);
      if(!ValidateObservationContinuity(symbol_id,timeframe_id,start_time,end_time))
         return(false);
      if(!ValidateTradeContinuity(dataset_version))
         return(false);
      return(true);
     }
  };

#endif // __EA_REPLAY_VALIDATOR_MQH__
//+------------------------------------------------------------------+
