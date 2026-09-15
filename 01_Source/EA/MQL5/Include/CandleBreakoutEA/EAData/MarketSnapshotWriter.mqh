//+------------------------------------------------------------------+
//|                           EAData/MarketSnapshotWriter.mqh        |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Market Intelligence DB: snapshot writer   |
//+------------------------------------------------------------------+
#ifndef __EA_DAL_SNAPSHOT_WRITER_MQH__
#define __EA_DAL_SNAPSHOT_WRITER_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EAUtils.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAContext\EAContextLayer.mqh>
#include <CandleBreakoutEA\EAFeatureBuilder\EAFeatureBuilder.mqh>
#include <CandleBreakoutEA\EAData\DatabaseTypes.mqh>
#include <CandleBreakoutEA\EAData\DatabaseManager.mqh>

//+------------------------------------------------------------------+
//| Persists one market observation per completed main-TF bar into   |
//| MarketSnapshots (schema v2). Single responsibility: write.       |
//| Data source is the Feature Builder snapshot, cross-checked       |
//| against the Context Layer; raw OHLC comes from the same          |
//| completed bar. Strictly observation-only - no trade information. |
//+------------------------------------------------------------------+
class CMarketSnapshotWriter
  {
private:
   const CEASettings  *m_set;
   CLogger            *m_log;
   CDatabaseManager   *m_db;
   CFeatureBuilder    *m_features;
   CContextLayer      *m_contexts;
   int                 m_symbol_id;
   int                 m_timeframe_id;
   datetime            m_last_written;
   int                 m_written;

   //--- register symbol/timeframe once and cache their ids
   bool                EnsureReferences(void)
     {
      if(m_symbol_id>0 && m_timeframe_id>0)
         return(true);
      if(!m_db.IsOpen())
         return(false);

      const string stamp = TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES);
      const int    digits = (int)SymbolInfoInteger(m_set.symbol_name,SYMBOL_DIGITS);
      const double point  = CEAUtils::PointValue(m_set.symbol_name);
      const double tick_size  = SymbolInfoDouble(m_set.symbol_name,SYMBOL_TRADE_TICK_SIZE);
      const double tick_value = SymbolInfoDouble(m_set.symbol_name,SYMBOL_TRADE_TICK_VALUE);
      const double contract   = SymbolInfoDouble(m_set.symbol_name,SYMBOL_TRADE_CONTRACT_SIZE);

      const string ins_symbol = StringFormat(
         "INSERT OR IGNORE INTO %s (Symbol,Digits,Point,TickSize,TickValue,ContractSize,CreatedAt) "
         "VALUES ('%s',%d,%s,%s,%s,%s,'%s')",
         DB_TABLE_SYMBOLS,m_set.symbol_name,digits,
         DoubleToString(point,digits),DoubleToString(tick_size,digits),
         DoubleToString(tick_value,8),DoubleToString(contract,8),stamp);
      if(!m_db.Execute(ins_symbol))
         return(false);

      const string name = EnumToString(m_set.main_timeframe);
      const string ins_tf = StringFormat(
         "INSERT OR IGNORE INTO %s (TimeframeID,Name,Minutes) VALUES (%d,'%s',%d)",
         DB_TABLE_TIMEFRAMES,(int)m_set.main_timeframe,name,
         (int)(PeriodSeconds(m_set.main_timeframe)/60));
      if(!m_db.Execute(ins_tf))
         return(false);

      string rows[];
      if(m_db.Select(StringFormat("SELECT SymbolID FROM %s WHERE Symbol='%s'",
                                  DB_TABLE_SYMBOLS,m_set.symbol_name),rows)==1)
         m_symbol_id = (int)StringToInteger(rows[0]);
      if(m_db.Select(StringFormat("SELECT TimeframeID FROM %s WHERE TimeframeID=%d",
                                  DB_TABLE_TIMEFRAMES,(int)m_set.main_timeframe),rows)==1)
         m_timeframe_id = (int)StringToInteger(rows[0]);
      return(m_symbol_id>0 && m_timeframe_id>0);
     }

public:
                       CMarketSnapshotWriter(void) : m_set(NULL), m_log(NULL), m_db(NULL),
                          m_features(NULL), m_contexts(NULL), m_symbol_id(0),
                          m_timeframe_id(0), m_last_written(0), m_written(0) {}

   void                Initialize(const CEASettings &settings,CLogger &logger,
                                  CDatabaseManager &db,CFeatureBuilder &features,
                                  CContextLayer &contexts)
     {
      m_set      = &settings;
      m_log      = &logger;
      m_db       = &db;
      m_features = &features;
      m_contexts = &contexts;
      m_log.Info("Market snapshot writer initialized");
     }

   //--- per-tick entry: writes at most once per completed main-TF bar
   void                Update(void)
     {
      if(m_db==NULL || !m_db.IsOpen() || m_features==NULL || !m_features.IsReady())
         return;
      const datetime bar = iTime(m_set.symbol_name,m_set.main_timeframe,1);
      if(bar<=0 || bar==m_last_written)
         return;
      InsertMarketSnapshot();
     }

   //--- the single writer entry point (STEP 3)
   bool                InsertMarketSnapshot(void)
     {
      if(m_db==NULL || !m_db.IsOpen() || m_features==NULL || m_set==NULL)
         return(false);

      const datetime bar = iTime(m_set.symbol_name,m_set.main_timeframe,1);
      if(bar<=0 || bar==m_last_written)
         return(false);

      //--- STEP 4 validation: reuse the Feature Builder rule set
      const SFeatureSnapshot snap = m_features.GetSnapshot();
      if(CFeatureValidation::Validate(snap)!=FB_OK)
        {
         m_log.Warn("Snapshot rejected | feature validation failed");
         return(false);
        }
      const double o = iOpen (m_set.symbol_name,m_set.main_timeframe,1);
      const double h = iHigh (m_set.symbol_name,m_set.main_timeframe,1);
      const double l = iLow  (m_set.symbol_name,m_set.main_timeframe,1);
      const double c = iClose(m_set.symbol_name,m_set.main_timeframe,1);
      if(!CFeatureValidation::IsValidCandle(o,h,l,c))
        {
         m_log.Warn("Snapshot rejected | invalid OHLC");
         return(false);
        }
      //--- the two independent observation pipelines must agree
      if(m_contexts!=NULL &&
         (m_contexts.market.CurrentHour!=(int)snap.CurrentHour ||
          (int)m_contexts.market.CurrentSession!=(int)snap.Session))
        {
         m_log.Warn("Snapshot rejected | context/feature mismatch");
         return(false);
        }
      if(!EnsureReferences())
         return(false);

      //--- STEP 4: duplicate timestamps per symbol/timeframe are rejected
      string rows[];
      if(m_db.Select(StringFormat(
            "SELECT COUNT(*) FROM %s WHERE SymbolID=%d AND TimeframeID=%d AND SnapshotTime=%d",
            DB_TABLE_SNAPSHOTS,m_symbol_id,m_timeframe_id,(int)bar),rows)==1 &&
         StringToInteger(rows[0])>0)
        {
         m_last_written = bar;   // already persisted (e.g. before a restart)
         return(false);
        }

      const string stamp = TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES);
      const string sql = StringFormat(
         "INSERT INTO %s (SymbolID,TimeframeID,SnapshotTime,Spread,ATR,ATRRatio,"
         "Open,High,Low,Close,BodySize,BodyPercent,UpperShadow,LowerShadow,"
         "\"Range\",Volatility,TrendDirection,TrendStrength,CurrentSession,"
         "CurrentHour,Weekday,Month,Quarter,BrokerOffset,CreatedAt) VALUES "
         "(%d,%d,%d,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%d,%s,%d,%d,%d,%d,%d,%d,'%s')",
         DB_TABLE_SNAPSHOTS,m_symbol_id,m_timeframe_id,(int)bar,
         DoubleToString(snap.Spread,2),DoubleToString(snap.ATR,8),DoubleToString(snap.ATRRatio,4),
         DoubleToString(o,8),DoubleToString(h,8),DoubleToString(l,8),DoubleToString(c,8),
         DoubleToString(snap.BodySize,8),DoubleToString(snap.BodyPercent,2),
         DoubleToString(snap.UpperShadow,8),DoubleToString(snap.LowerShadow,8),
         DoubleToString(snap.CurrentRange,8),DoubleToString(snap.Volatility,2),
         (int)snap.TrendDirection,DoubleToString(snap.TrendStrength,2),
         (int)snap.Session,snap.CurrentHour,snap.Weekday,snap.Month,snap.Quarter,
         snap.BrokerOffset,stamp);

      if(m_db.Insert(sql)!=1)
        {
         m_log.Warn("Snapshot insert failed");
         return(false);
        }
      m_last_written = bar;
      m_written++;
      if(m_written==1)
         m_log.Info(StringFormat("Market snapshots: first row stored (%s)",stamp));
      else
         m_log.Debug(StringFormat("Market snapshot stored | bar %s",
                                  TimeToString(bar,TIME_DATE|TIME_MINUTES)));
      return(true);
     }

   int                 SnapshotsWritten(void) const { return(m_written); }

   //--- reference ids resolved for the managed symbol/timeframe (0 = unresolved)
   int                 SymbolId(void)    { EnsureReferences(); return(m_symbol_id); }
   int                 TimeframeId(void) { EnsureReferences(); return(m_timeframe_id); }
  };

#endif // __EA_DAL_SNAPSHOT_WRITER_MQH__
//+------------------------------------------------------------------+
