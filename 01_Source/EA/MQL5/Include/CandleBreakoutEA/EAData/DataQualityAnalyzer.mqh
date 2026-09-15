//+------------------------------------------------------------------+
//|                          EAData/DataQualityAnalyzer.mqh          |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Research data quality: analyze & report   |
//+------------------------------------------------------------------+
#ifndef __EA_DAL_QUALITY_MQH__
#define __EA_DAL_QUALITY_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAData\DatabaseTypes.mqh>
#include <CandleBreakoutEA\EAData\DatabaseManager.mqh>
#include <CandleBreakoutEA\EAData\LabelGenerator.mqh>

//--- deep per-row look-ahead scan window (most recent rows)
#define QUALITY_SCAN_LIMIT 500

//+------------------------------------------------------------------+
//| Validates research datasets before they may be used for ML.      |
//| Reports are deterministic: the same dataset state always yields  |
//| the same scores. No business logic, no trading impact.           |
//+------------------------------------------------------------------+
class CDataQualityAnalyzer
  {
private:
   const CEASettings  *m_set;
   CLogger            *m_log;
   CDatabaseManager   *m_db;
   datetime            m_last_pass;
   ENUM_QUALITY_STATUS m_last_status;

   long                CountOf(const string sql)
     {
      string rows[];
      if(m_db.Select(sql,rows)!=1)
         return(-1);
      return(StringToInteger(rows[0]));
     }

   //--- STEP 4: per-row look-ahead scan of the most recent rows.
   //--- a label must have been generated no earlier than the end of its window.
   long                ScanLookAhead(const int version)
     {
      string rows[];
      const int found = m_db.Select(StringFormat(
         "SELECT o.BarTime,l.LookaheadBars,l.GeneratedAt FROM %s d "
         "JOIN %s o ON o.ObservationID=d.ObservationID "
         "JOIN %s l ON l.LabelID=d.LabelID "
         "WHERE d.DatasetVersion=%d ORDER BY d.ObservationID DESC LIMIT %d",
         DB_TABLE_DATASETS,DB_TABLE_OBSERVATIONS,DB_TABLE_LABELS,
         version,QUALITY_SCAN_LIMIT),rows);
      if(found<0)
         return(-1);
      const int tf_seconds = PeriodSeconds(m_set.main_timeframe);
      long violations = 0;
      for(int i=0; i<found; i++)
        {
         string cells[];
         if(StringSplit(rows[i],';',cells)!=3)
            continue;
         const datetime bar  = (datetime)StringToInteger(cells[0]);
         const int      look = (int)StringToInteger(cells[1]);
         const datetime gen  = StringToTime(cells[2]);
         if(bar<=0 || gen<=0)
            continue;
         if(gen<bar+(datetime)(look*tf_seconds))
            violations++;
        }
      return(violations);
     }

public:
                       CDataQualityAnalyzer(void) : m_set(NULL), m_log(NULL), m_db(NULL),
                          m_last_pass(0), m_last_status(QUALITY_UNKNOWN) {}

   void                Initialize(const CEASettings &settings,CLogger &logger,CDatabaseManager &db)
     {
      m_set = &settings;
      m_log = &logger;
      m_db  = &db;
      m_log.Info("Data Quality Engine initialized");
     }

   //--- STEP 3: full analysis of one dataset version; stores a report row
   ENUM_QUALITY_STATUS AnalyzeDataset(const int version)
     {
      if(m_db==NULL || !m_db.IsOpen())
         return(QUALITY_UNKNOWN);

      const long row_count = CountOf(StringFormat(
         "SELECT COUNT(*) FROM %s WHERE DatasetVersion=%d",DB_TABLE_DATASETS,version));
      if(row_count<0)
         return(QUALITY_UNKNOWN);

      long duplicates = 0, missing_snap = 0, missing_label = 0, broken = 0, mismatch = 0;
      long invalid_ts = 0, invalid_feat = 0, lookahead = 0;

      if(row_count>0)
        {
         duplicates = CountOf(StringFormat(
            "SELECT COUNT(*)-COUNT(DISTINCT ObservationID) FROM %s WHERE DatasetVersion=%d",
            DB_TABLE_DATASETS,version));

         //--- broken foreign keys (observation / trade)
         broken = CountOf(StringFormat(
            "SELECT COUNT(*) FROM %s d "
            "LEFT JOIN %s o ON o.ObservationID=d.ObservationID "
            "LEFT JOIN %s t ON t.TradeID=d.TradeID "
            "WHERE d.DatasetVersion=%d AND (o.ObservationID IS NULL "
            "OR (d.TradeID IS NOT NULL AND t.TradeID IS NULL))",
            DB_TABLE_DATASETS,DB_TABLE_OBSERVATIONS,DB_TABLE_TRADES,version));

         //--- missing snapshots / labels
         missing_snap = CountOf(StringFormat(
            "SELECT COUNT(*) FROM %s d LEFT JOIN %s s ON s.SnapshotID=d.SnapshotID "
            "WHERE d.DatasetVersion=%d AND s.SnapshotID IS NULL",
            DB_TABLE_DATASETS,DB_TABLE_SNAPSHOTS,version));
         missing_label = CountOf(StringFormat(
            "SELECT COUNT(*) FROM %s d LEFT JOIN %s l ON l.LabelID=d.LabelID "
            "WHERE d.DatasetVersion=%d AND l.LabelID IS NULL",
            DB_TABLE_DATASETS,DB_TABLE_LABELS,version));

         //--- dataset version mismatch: wrong label version inside the set
         mismatch = CountOf(StringFormat(
            "SELECT COUNT(*) FROM %s d JOIN %s l ON l.LabelID=d.LabelID "
            "WHERE d.DatasetVersion=%d AND l.LabelVersion<>1",
            DB_TABLE_DATASETS,DB_TABLE_LABELS,version));

         //--- invalid timestamps on the observation side
         invalid_ts = CountOf(StringFormat(
            "SELECT COUNT(*) FROM %s d JOIN %s o ON o.ObservationID=d.ObservationID "
            "WHERE d.DatasetVersion=%d AND (o.BarTime<=0 OR o.ObservationTime<=0 "
            "OR o.ObservationTime<o.BarTime)",
            DB_TABLE_DATASETS,DB_TABLE_OBSERVATIONS,version));

         //--- invalid features: NULL (SQLite cannot store NaN in a NOT NULL REAL),
         //--- negative ATR/spread, inconsistent OHLC
         invalid_feat = CountOf(StringFormat(
            "SELECT COUNT(*) FROM %s d JOIN %s s ON s.SnapshotID=d.SnapshotID "
            "WHERE d.DatasetVersion=%d AND (s.ATR IS NULL OR s.Spread IS NULL "
            "OR s.ATR<0 OR s.Spread<0 OR s.High<s.Low OR s.Close<s.Low OR s.Close>s.High)",
            DB_TABLE_DATASETS,DB_TABLE_SNAPSHOTS,version));

         lookahead = ScanLookAhead(version);
        }

      //--- STEP 5: scores 0..100
      const long denom = (row_count>0 ? row_count : 1);
      const long problems = duplicates+missing_snap+missing_label+broken+mismatch+
                            invalid_ts+invalid_feat;
      const long valid_rows  = (row_count>problems ? row_count-problems : 0);
      const int completeness = (int)(100*valid_rows/denom);
      const int integrity    = (int)(100*(denom-(broken+missing_snap+missing_label+duplicates))/denom);
      const int consistency  = (int)(100*(denom-(lookahead+mismatch+invalid_ts+invalid_feat))/denom);
      const int overall      = (completeness+integrity+consistency)/3;

      //--- hard violations always fail, regardless of the score
      ENUM_QUALITY_STATUS status = QUALITY_PASS;
      if(lookahead>0 || broken>0 || missing_snap>0 || missing_label>0 ||
         duplicates>0 || mismatch>0 || invalid_ts>0 || invalid_feat>0)
         status = QUALITY_FAIL;
      else if(overall<100)
         status = QUALITY_WARNING;

      const string stamp = TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES);
      const string sql = StringFormat(
         "INSERT INTO %s (DatasetVersion,RowCount,ValidRows,InvalidRows,DuplicateRows,"
         "MissingSnapshots,MissingLabels,BrokenReferences,LookAheadViolations,"
         "ConsistencyScore,CompletenessScore,IntegrityScore,OverallScore,QualityStatus,GeneratedAt) "
         "VALUES (%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,'%s')",
         DB_TABLE_QUALITY,version,(int)row_count,(int)valid_rows,(int)problems,
         (int)duplicates,(int)missing_snap,(int)missing_label,(int)broken,(int)lookahead,
         consistency,completeness,integrity,overall,(int)status,stamp);
      if(m_db.Insert(sql)!=1)
        {
         m_log.Warn(StringFormat("Quality report insert failed | dataset v%d",version));
         return(QUALITY_UNKNOWN);
        }

      m_last_status = status;
      m_log.Info(StringFormat("Dataset v%d quality | %s | rows %d | valid %d | C%d/I%d/K%d | overall %d",
                              version,
                              (status==QUALITY_PASS ? "PASS" :
                               (status==QUALITY_WARNING ? "WARNING" : "FAIL")),
                              (int)row_count,(int)valid_rows,
                              completeness,integrity,consistency,overall));
      return(status);
     }

   //--- STEP 3: human-readable report from the latest stored analysis
   bool                GenerateQualityReport(const int version,string &report)
     {
      report = "";
      if(m_db==NULL || !m_db.IsOpen())
         return(false);
      string rows[];
      if(m_db.Select(StringFormat(
            "SELECT RowCount,ValidRows,InvalidRows,DuplicateRows,MissingSnapshots,"
            "MissingLabels,BrokenReferences,LookAheadViolations,CompletenessScore,"
            "IntegrityScore,ConsistencyScore,OverallScore,QualityStatus,GeneratedAt "
            "FROM %s WHERE DatasetVersion=%d ORDER BY QualityID DESC LIMIT 1",
            DB_TABLE_QUALITY,version),rows)!=1)
         return(false);
      string c[];
      if(StringSplit(rows[0],';',c)!=14)
         return(false);
      report = StringFormat(
         "dataset v%s | rows %s (valid %s, invalid %s) | duplicates %s | missing snap %s | "
         "missing labels %s | broken refs %s | look-ahead %s | completeness %s | "
         "integrity %s | consistency %s | overall %s | status %d | %s",
         IntegerToString(version),c[0],c[1],c[2],c[3],c[4],c[5],c[6],c[7],
         c[8],c[9],c[10],c[11],(int)StringToInteger(c[12]),c[13]);
      return(true);
     }

   //--- STEP 3/6: gate used by the export path
   bool                ValidateDataset(const int version)
     {
      if(m_db==NULL || !m_db.IsOpen())
         return(false);
      string rows[];
      if(m_db.Select(StringFormat(
            "SELECT QualityStatus FROM %s WHERE DatasetVersion=%d ORDER BY QualityID DESC LIMIT 1",
            DB_TABLE_QUALITY,version),rows)!=1)
         return(false);   // never analyzed -> not exportable
      return((int)StringToInteger(rows[0])==(int)QUALITY_PASS);
     }

   //--- per-tick entry: one analysis per completed bar
   void                Update(void)
     {
      if(m_db==NULL || !m_db.IsOpen() || m_set==NULL)
         return;
      const datetime bar = iTime(m_set.symbol_name,m_set.main_timeframe,0);
      if(bar<=0 || bar==m_last_pass)
         return;
      m_last_pass = bar;
      AnalyzeDataset(1);   // DATASET_VERSION is defined with the builder; v1 in this phase
     }

   ENUM_QUALITY_STATUS LastStatus(void) const { return(m_last_status); }
  };

#endif // __EA_DAL_QUALITY_MQH__
//+------------------------------------------------------------------+
