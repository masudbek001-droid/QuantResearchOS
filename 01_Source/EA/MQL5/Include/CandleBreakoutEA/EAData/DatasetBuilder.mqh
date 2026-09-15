//+------------------------------------------------------------------+
//|                              EAData/DatasetBuilder.mqh           |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Research datasets: build / validate / export |
//+------------------------------------------------------------------+
#ifndef __EA_DAL_DATASET_BUILDER_MQH__
#define __EA_DAL_DATASET_BUILDER_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAData\DatabaseTypes.mqh>
#include <CandleBreakoutEA\EAData\DatabaseManager.mqh>
#include <CandleBreakoutEA\EAData\DataQualityAnalyzer.mqh>

//--- dataset contract
#define DATASET_VERSION       1   // bump only through an ADR
#define DATASET_BATCH_LIMIT  50   // rows built per pass
#define DATASET_EXPORT_DIR   "CBEA"
#define DATASET_CSV_COLUMNS  \
   "ObservationID;BarTime;ObservationType;Session;Hour;Weekday;Month;" \
   "Spread;ATR;ATRRatio;Open;High;Low;Close;BodySize;BodyPercent;" \
   "UpperShadow;LowerShadow;Range;Volatility;TrendDirection;TrendStrength;" \
   "CurrentHour;BrokerOffset;LookaheadBars;FutureHigh;FutureLow;FutureClose;" \
   "MFE;MAE;DirectionLabel;BreakoutSuccess;LabelQuality;TradeID"

//+------------------------------------------------------------------+
//| Joins Observations + MarketSnapshots + ObservationLabels (+ the  |
//| optional Trade reference) into one reproducible research dataset.|
//| Ground truth only: no prediction, no trading decisions.          |
//+------------------------------------------------------------------+
class CDatasetBuilder
  {
private:
   const CEASettings  *m_set;
   CLogger            *m_log;
   CDatabaseManager   *m_db;
   CDataQualityAnalyzer *m_quality;   // optional gate (Task 0011, STEP 6)
   datetime            m_last_pass;
   int                 m_built;

   //--- one reproducible wide SELECT for a dataset version
   string              DatasetSelect(const int version) const
     {
      return(StringFormat(
         "SELECT d.ObservationID,o.BarTime,o.ObservationType,o.Session,o.Hour,o.Weekday,o.Month,"
         "s.Spread,s.ATR,s.ATRRatio,s.Open,s.High,s.Low,s.Close,s.BodySize,s.BodyPercent,"
         "s.UpperShadow,s.LowerShadow,s.\"Range\",s.Volatility,s.TrendDirection,s.TrendStrength,"
         "s.CurrentHour,s.BrokerOffset,l.LookaheadBars,l.FutureHigh,l.FutureLow,l.FutureClose,"
         "l.MaxFavorableExcursion,l.MaxAdverseExcursion,l.DirectionLabel,l.BreakoutSuccess,"
         "l.LabelQuality,d.TradeID "
         "FROM %s d "
         "JOIN %s o ON o.ObservationID=d.ObservationID "
         "JOIN %s s ON s.SnapshotID=d.SnapshotID "
         "JOIN %s l ON l.LabelID=d.LabelID "
         "WHERE d.DatasetVersion=%d ORDER BY d.ObservationID ASC",
         DB_TABLE_DATASETS,DB_TABLE_OBSERVATIONS,DB_TABLE_SNAPSHOTS,
         DB_TABLE_LABELS,version));
     }

public:
                       CDatasetBuilder(void) : m_set(NULL), m_log(NULL), m_db(NULL),
                          m_quality(NULL), m_last_pass(0), m_built(0) {}

   //--- STEP 6 (Task 0011): once attached, CSV export is blocked unless the
   //--- latest quality report of the version is QUALITY_PASS. No override.
   void                AttachQuality(CDataQualityAnalyzer &quality)
     {
      m_quality = &quality;
     }

   void                Initialize(const CEASettings &settings,CLogger &logger,CDatabaseManager &db)
     {
      m_set = &settings;
      m_log = &logger;
      m_db  = &db;
      m_log.Info(StringFormat("Dataset Builder initialized | dataset v%d",DATASET_VERSION));
     }

   //--- STEP 2/3: append every complete (observation+snapshot+label) row not yet in the set.
   //--- INNER joins + NOT NULL snapshot guarantee: no missing foreign keys.
   int                 BuildDataset(const int version)
     {
      if(m_db==NULL || !m_db.IsOpen())
         return(0);
      if(version<=0)
        { m_log.Warn("Dataset build rejected | invalid version"); return(0); }

      const string stamp = TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES);
      const string sql = StringFormat(
         "INSERT INTO %s (DatasetVersion,ObservationID,SnapshotID,LabelID,TradeID,ExportStatus,CreatedAt) "
         "SELECT %d,o.ObservationID,o.FeatureSnapshotID,l.LabelID,o.TradeID,%d,'%s' "
         "FROM %s o JOIN %s l ON l.ObservationID=o.ObservationID AND l.LabelVersion=1 "
         "WHERE o.FeatureSnapshotID IS NOT NULL "
         "AND NOT EXISTS (SELECT 1 FROM %s d WHERE d.DatasetVersion=%d AND d.ObservationID=o.ObservationID) "
         "ORDER BY o.BarTime ASC LIMIT %d",
         DB_TABLE_DATASETS,version,DATASET_EXPORT_NONE,stamp,
         DB_TABLE_OBSERVATIONS,DB_TABLE_LABELS,
         DB_TABLE_DATASETS,version,DATASET_BATCH_LIMIT);

      const int added = m_db.Insert(sql);   // rows affected via SQL changes()
      if(added<0)
        {
         m_log.Warn(StringFormat("Dataset build failed | version %d",version));
         return(0);
        }
      if(added>0)
        {
         m_built += added;
         m_log.Debug(StringFormat("Dataset v%d | +%d rows | total %d",version,added,m_built));
        }
      return(added);
     }

   //--- STEP 4: integrity of one dataset version (0 broken rows expected)
   bool                ValidateDataset(const int version)
     {
      if(m_db==NULL || !m_db.IsOpen())
         return(false);
      string rows[];
      const int found = m_db.Select(StringFormat(
         "SELECT COUNT(*) FROM %s d "
         "LEFT JOIN %s o ON o.ObservationID=d.ObservationID "
         "LEFT JOIN %s s ON s.SnapshotID=d.SnapshotID "
         "LEFT JOIN %s l ON l.LabelID=d.LabelID "
         "LEFT JOIN %s t ON t.TradeID=d.TradeID "
         "WHERE d.DatasetVersion=%d AND (o.ObservationID IS NULL OR s.SnapshotID IS NULL "
         "OR l.LabelID IS NULL OR (d.TradeID IS NOT NULL AND t.TradeID IS NULL))",
         DB_TABLE_DATASETS,DB_TABLE_OBSERVATIONS,DB_TABLE_SNAPSHOTS,
         DB_TABLE_LABELS,DB_TABLE_TRADES,version),rows);
      if(found!=1)
         return(false);
      if(StringToInteger(rows[0])!=0)
        {
         m_log.Warn(StringFormat("Dataset v%d | broken FK rows: %s",version,rows[0]));
         return(false);
        }
      //--- duplicate detection inside the version
      if(m_db.Select(StringFormat(
            "SELECT COUNT(*)-COUNT(DISTINCT ObservationID) FROM %s WHERE DatasetVersion=%d",
            DB_TABLE_DATASETS,version),rows)==1 && StringToInteger(rows[0])!=0)
        {
         m_log.Warn(StringFormat("Dataset v%d | duplicate rows: %s",version,rows[0]));
         return(false);
        }
      return(true);
     }

   //--- STEP 6: export. CSV is deterministic (fixed order, columns, precision).
   bool                ExportDataset(const int version,const ENUM_DATASET_EXPORT format)
     {
      if(m_db==NULL || !m_db.IsOpen())
         return(false);
      if(!ValidateDataset(version))
         return(false);

      //--- STEP 6 export protection: no quality gate, no CSV - override is not allowed
      if(format==DATASET_EXPORT_CSV && m_quality!=NULL && !m_quality.ValidateDataset(version))
        {
         m_log.Warn(StringFormat(
            "Dataset v%d CSV export blocked | quality status is not PASS",version));
         return(false);
        }

      string rows[];
      const int count = m_db.Select(DatasetSelect(version),rows);
      if(count<0)
        {
         m_log.Warn(StringFormat("Dataset v%d | export select failed",version));
         return(false);
        }

      bool ok = true;
      switch(format)
        {
         case DATASET_EXPORT_CSV:
           {
            const string file = StringFormat("%s\\dataset_v%d.csv",DATASET_EXPORT_DIR,version);
            const int handle = FileOpen(file,FILE_WRITE|FILE_TXT|FILE_ANSI);
            if(handle==INVALID_HANDLE)
              {
               m_log.Warn(StringFormat("Dataset v%d | cannot open %s",version,file));
               return(false);
              }
            FileWriteString(handle,DATASET_CSV_COLUMNS+"\n");
            for(int i=0; i<count; i++)
               FileWriteString(handle,rows[i]+"\n");
            FileClose(handle);
            m_log.Info(StringFormat("Dataset v%d exported to CSV | %d rows | %s",
                                    version,count,file));
            break;
           }
         case DATASET_EXPORT_INTERNAL:
            break;   // the dataset table itself is the internal format
         case DATASET_EXPORT_PARQUET:
            m_log.Warn("Parquet export is a placeholder | not implemented yet");
            return(false);
         default:
            return(false);
        }

      if(ok && m_db.Update(StringFormat(
            "UPDATE %s SET ExportStatus=%d WHERE DatasetVersion=%d",
            DB_TABLE_DATASETS,(int)format,version))<0)
         m_log.Warn(StringFormat("Dataset v%d | export status update failed",version));
      return(ok);
     }

   //--- per-tick entry: extend the current dataset version once per completed bar
   void                Update(void)
     {
      if(m_db==NULL || !m_db.IsOpen() || m_set==NULL)
         return;
      const datetime bar = iTime(m_set.symbol_name,m_set.main_timeframe,0);
      if(bar<=0 || bar==m_last_pass)
         return;
      m_last_pass = bar;
      BuildDataset(DATASET_VERSION);
     }

   int                 RowsBuilt(void) const { return(m_built); }
  };

#endif // __EA_DAL_DATASET_BUILDER_MQH__
//+------------------------------------------------------------------+
