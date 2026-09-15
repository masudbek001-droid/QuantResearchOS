//+------------------------------------------------------------------+
//|                            EAData/ObservationWriter.mqh          |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Observation Engine: market recorder       |
//+------------------------------------------------------------------+
#ifndef __EA_DAL_OBSERVATION_WRITER_MQH__
#define __EA_DAL_OBSERVATION_WRITER_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EAUtils.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAFeatureBuilder\EAFeatureBuilder.mqh>
#include <CandleBreakoutEA\EAData\DatabaseTypes.mqh>
#include <CandleBreakoutEA\EAData\DatabaseManager.mqh>
#include <CandleBreakoutEA\EAData\MarketSnapshotWriter.mqh>

//+------------------------------------------------------------------+
//| STEP 2: observation vocabulary. Descriptive labels only - none   |
//| of them feeds any trading decision.                              |
//+------------------------------------------------------------------+
enum ENUM_OBSERVATION_TYPE
  {
   OBS_NEW_BAR        = 0,  // plain completed candle (default label)
   OBS_BREAKOUT_UP    = 1,  // close beyond the previous bar high
   OBS_BREAKOUT_DOWN  = 2,  // close beyond the previous bar low
   OBS_INSIDE_BAR     = 3,  // high/low inside the previous bar range
   OBS_OUTSIDE_BAR    = 4,  // high/low engulf the previous bar range
   OBS_HIGH_VOLATILITY= 5,  // bar range >= 1.5 x ATR
   OBS_LOW_VOLATILITY = 6,  // bar range <= 0.75 x ATR
   OBS_SESSION_OPEN   = 7,  // first bar of a session (server clock)
   OBS_SESSION_CLOSE  = 8,  // last bar of a session (server clock)
   OBS_CUSTOM         = 9   // reserved for future recorders
  };

#define OBS_TYPES_TOTAL       10
//--- volatility labelling thresholds (bar range vs ATR)
#define OBS_ATR_RATIO_HIGH    1.5
#define OBS_ATR_RATIO_LOW     0.75

//+------------------------------------------------------------------+
//| The Observation Engine: records the market, one observation per  |
//| completed candle, completely independent from trading. Data      |
//| sources: Feature Builder snapshot + Context Layer; persistence   |
//| through the DAL only. No business logic, no trading side effects.|
//+------------------------------------------------------------------+
class CObservationWriter
  {
private:
   const CEASettings  *m_set;
   CLogger            *m_log;
   CDatabaseManager   *m_db;
   CFeatureBuilder    *m_features;
   CMarketSnapshotWriter *m_snapshots;
   datetime            m_last_recorded;
   int                 m_recorded;

   //--- the snapshot row that describes exactly this completed bar
   long                SnapshotOfBar(const datetime bar_time)
     {
      if(m_snapshots==NULL)
         return(-1);
      const int sym = m_snapshots.SymbolId();
      const int tf  = m_snapshots.TimeframeId();
      if(sym<=0 || tf<=0)
         return(-1);
      string rows[];
      if(m_db.Select(StringFormat(
            "SELECT SnapshotID FROM %s WHERE SymbolID=%d AND TimeframeID=%d AND SnapshotTime=%d",
            DB_TABLE_SNAPSHOTS,sym,tf,(int)bar_time),rows)==1)
         return(StringToInteger(rows[0]));
      return(-1);
     }

public:
                       CObservationWriter(void) : m_set(NULL), m_log(NULL), m_db(NULL),
                          m_features(NULL), m_snapshots(NULL), m_last_recorded(0), m_recorded(0) {}

   void                Initialize(const CEASettings &settings,CLogger &logger,
                                  CDatabaseManager &db,CFeatureBuilder &features,
                                  CMarketSnapshotWriter &snapshots)
     {
      m_set       = &settings;
      m_log       = &logger;
      m_db        = &db;
      m_features  = &features;
      m_snapshots = &snapshots;
      m_log.Info("Observation Engine initialized");
     }

   //--- descriptive label of a completed bar (priority order)
   ENUM_OBSERVATION_TYPE ClassifyBar(const SFeatureSnapshot &snap)
     {
      const double prev_high = iHigh (m_set.symbol_name,m_set.main_timeframe,2);
      const double prev_low  = iLow  (m_set.symbol_name,m_set.main_timeframe,2);
      const double close     = iClose(m_set.symbol_name,m_set.main_timeframe,1);
      const double high      = iHigh (m_set.symbol_name,m_set.main_timeframe,1);
      const double low       = iLow  (m_set.symbol_name,m_set.main_timeframe,1);

      if(prev_high>0.0 && close>prev_high)
         return(OBS_BREAKOUT_UP);
      if(prev_low>0.0 && close<prev_low)
         return(OBS_BREAKOUT_DOWN);
      if(prev_high>0.0 && prev_low>0.0 && high>prev_high && low<prev_low)
         return(OBS_OUTSIDE_BAR);
      if(prev_high>0.0 && prev_low>0.0 && high<prev_high && low>prev_low)
         return(OBS_INSIDE_BAR);
      if(snap.ATRRatio>=OBS_ATR_RATIO_HIGH)
         return(OBS_HIGH_VOLATILITY);
      if(snap.ATRRatio>0.0 && snap.ATRRatio<=OBS_ATR_RATIO_LOW)
         return(OBS_LOW_VOLATILITY);
      if(snap.CurrentHour==FB_ASIA_END_HOUR || snap.CurrentHour==FB_LONDON_END_HOUR)
         return(OBS_SESSION_OPEN);
      if(snap.CurrentHour==FB_ASIA_END_HOUR-1 || snap.CurrentHour==FB_LONDON_END_HOUR-1)
         return(OBS_SESSION_CLOSE);
      return(OBS_NEW_BAR);
     }

   //--- STEP 5: validation rules shared by every insert
   bool                ValidateObservation(const datetime bar_time,const int observation_type,
                                           const long feature_snapshot_id)
     {
      if(bar_time<=0 || bar_time>TimeCurrent())
        { m_log.Warn("Observation rejected | invalid bar time"); return(false); }
      if(observation_type<0 || observation_type>=OBS_TYPES_TOTAL)
        { m_log.Warn("Observation rejected | invalid observation type"); return(false); }
      if(feature_snapshot_id<=0)
        { m_log.Warn("Observation rejected | missing feature snapshot"); return(false); }
      string rows[];
      if(m_db.Select(StringFormat("SELECT COUNT(*) FROM %s WHERE SnapshotID=%d",
                                  DB_TABLE_SNAPSHOTS,(int)feature_snapshot_id),rows)!=1 ||
         StringToInteger(rows[0])!=1)
        { m_log.Warn("Observation rejected | missing feature snapshot"); return(false); }
      return(true);
     }

   //--- STEP 3: the single insert entry point
   bool                InsertObservation(const datetime bar_time,const ENUM_OBSERVATION_TYPE type,
                                         const long feature_snapshot_id,const long trade_id,
                                         const int session,const int hour,
                                         const int weekday,const int month)
     {
      if(m_db==NULL || !m_db.IsOpen() || m_snapshots==NULL)
         return(false);
      const int sym = m_snapshots.SymbolId();
      const int tf  = m_snapshots.TimeframeId();
      if(sym<=0 || tf<=0)
         return(false);
      if(!ValidateObservation(bar_time,(int)type,feature_snapshot_id))
         return(false);

      //--- STEP 5: duplicate observation
      string rows[];
      if(m_db.Select(StringFormat(
            "SELECT COUNT(*) FROM %s WHERE SymbolID=%d AND TimeframeID=%d AND BarTime=%d AND ObservationType=%d",
            DB_TABLE_OBSERVATIONS,sym,tf,(int)bar_time,(int)type),rows)==1 &&
         StringToInteger(rows[0])>0)
        {
         m_last_recorded = bar_time;   // already stored (e.g. before a restart)
         return(false);
        }

      const string stamp = TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES);
      const string trade_ref = (trade_id>0 ? IntegerToString((long)trade_id) : "NULL");
      const string sql = StringFormat(
         "INSERT INTO %s (SymbolID,TimeframeID,ObservationTime,BarTime,ObservationType,"
         "FeatureSnapshotID,TradeID,Session,Hour,Weekday,Month,CreatedAt) "
         "VALUES (%d,%d,%d,%d,%d,%d,%s,%d,%d,%d,%d,'%s')",
         DB_TABLE_OBSERVATIONS,sym,tf,(int)TimeCurrent(),(int)bar_time,(int)type,
         (int)feature_snapshot_id,trade_ref,session,hour,weekday,month,stamp);

      if(m_db.Insert(sql)!=1)
        {
         m_log.Warn(StringFormat("Observation insert failed | bar %s",
                                 TimeToString(bar_time,TIME_DATE|TIME_MINUTES)));
         return(false);
        }
      m_last_recorded = bar_time;
      m_recorded++;
      if(m_recorded==1)
         m_log.Info("Observation Engine: first observation stored");
      else
         m_log.Debug(StringFormat("Observation stored | %s | type %d",
                                  TimeToString(bar_time,TIME_DATE|TIME_MINUTES),(int)type));
      return(true);
     }

   //--- STEP 4: one observation per completed candle, trades or no trades
   void                Update(void)
     {
      if(m_db==NULL || !m_db.IsOpen() || m_features==NULL || !m_features.IsReady())
         return;
      const datetime bar = iTime(m_set.symbol_name,m_set.main_timeframe,1);
      if(bar<=0 || bar==m_last_recorded)
         return;

      const SFeatureSnapshot snap = m_features.GetSnapshot();
      if(CFeatureValidation::Validate(snap)!=FB_OK)
         return;

      const long snapshot_id = SnapshotOfBar(bar);
      InsertObservation(bar,ClassifyBar(snap),snapshot_id,-1,
                        (int)snap.Session,snap.CurrentHour,snap.Weekday,snap.Month);
     }

   int                 ObservationsRecorded(void) const { return(m_recorded); }
  };

#endif // __EA_DAL_OBSERVATION_WRITER_MQH__
//+------------------------------------------------------------------+
