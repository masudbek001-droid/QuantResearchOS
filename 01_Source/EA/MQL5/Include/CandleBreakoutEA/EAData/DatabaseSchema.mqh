//+------------------------------------------------------------------+
//|                              EAData/DatabaseSchema.mqh           |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Data Access Layer: schema v1 (metadata)   |
//+------------------------------------------------------------------+
#ifndef __EA_DAL_SCHEMA_MQH__
#define __EA_DAL_SCHEMA_MQH__

#include <CandleBreakoutEA\EAData\DatabaseTypes.mqh>

//+------------------------------------------------------------------+
//| Schema v1: metadata tables only. Trade tables arrive with a      |
//| future ADR + migration; nothing here stores trading data.        |
//+------------------------------------------------------------------+
class CDatabaseSchema
  {
public:
   //--- DDL of the current schema version (idempotent)
   static bool         Create(const int db)
     {
      if(db==0)
         return(false);

      const string create_info =
         StringFormat("CREATE TABLE IF NOT EXISTS %s (key TEXT PRIMARY KEY, value TEXT NOT NULL)",
                      DB_TABLE_INFO);
      const string create_version =
         StringFormat("CREATE TABLE IF NOT EXISTS %s (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL)",
                      DB_TABLE_VERSION);
      const string create_migration =
         StringFormat("CREATE TABLE IF NOT EXISTS %s (id INTEGER PRIMARY KEY AUTOINCREMENT, "
                      "from_version INTEGER NOT NULL, to_version INTEGER NOT NULL, "
                      "description TEXT, applied_at TEXT NOT NULL)",
                      DB_TABLE_MIGRATION);

      if(!DatabaseExecute(db,create_info))
         return(false);
      if(!DatabaseExecute(db,create_version))
         return(false);
      if(!DatabaseExecute(db,create_migration))
         return(false);
      return(true);
     }

   //--- identity of this installation (created once, last_open refreshed)
   static bool         WriteInfo(const int db,const ulong magic,const string symbol)
     {
      if(db==0)
         return(false);

      const string stamp = TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES);
      const string keys[]  = {"product","magic","symbol","created"};
      const string values[]= {DB_PRODUCT_NAME,IntegerToString((long)magic),symbol,stamp};

      for(int i=0; i<ArraySize(keys); i++)
        {
         const string sql = StringFormat(
            "INSERT OR IGNORE INTO %s (key,value) VALUES ('%s','%s')",
            DB_TABLE_INFO,keys[i],values[i]);
         if(!DatabaseExecute(db,sql))
            return(false);
        }

      const string last_open = StringFormat(
         "INSERT INTO %s (key,value) VALUES ('last_open','%s') "
         "ON CONFLICT(key) DO UPDATE SET value=excluded.value",
         DB_TABLE_INFO,stamp);
      return(DatabaseExecute(db,last_open));
     }

   //--- schema v2: market intelligence tables + indexes (Task 0006)
   static void         MigrationToV2(string &ddl[])
     {
      ArrayResize(ddl,9);

      ddl[0] = StringFormat(
         "CREATE TABLE IF NOT EXISTS %s ("
         "SymbolID INTEGER PRIMARY KEY AUTOINCREMENT,"
         "Symbol TEXT NOT NULL UNIQUE,"
         "Digits INTEGER NOT NULL,"
         "Point REAL NOT NULL,"
         "TickSize REAL NOT NULL,"
         "TickValue REAL NOT NULL,"
         "ContractSize REAL NOT NULL,"
         "CreatedAt TEXT NOT NULL)",DB_TABLE_SYMBOLS);

      ddl[1] = StringFormat(
         "CREATE TABLE IF NOT EXISTS %s ("
         "TimeframeID INTEGER PRIMARY KEY,"
         "Name TEXT NOT NULL UNIQUE,"
         "Minutes INTEGER NOT NULL)",DB_TABLE_TIMEFRAMES);

      ddl[2] = StringFormat(
         "CREATE TABLE IF NOT EXISTS %s ("
         "SnapshotID INTEGER PRIMARY KEY AUTOINCREMENT,"
         "SymbolID INTEGER NOT NULL,"
         "TimeframeID INTEGER NOT NULL,"
         "SnapshotTime INTEGER NOT NULL,"
         "Spread REAL NOT NULL,"
         "ATR REAL NOT NULL,"
         "ATRRatio REAL,"
         "Open REAL,"
         "High REAL,"
         "Low REAL,"
         "Close REAL,"
         "BodySize REAL,"
         "BodyPercent REAL,"
         "UpperShadow REAL,"
         "LowerShadow REAL,"
         "\"Range\" REAL,"
         "Volatility REAL,"
         "TrendDirection INTEGER,"
         "TrendStrength REAL,"
         "CurrentSession INTEGER,"
         "CurrentHour INTEGER,"
         "Weekday INTEGER,"
         "Month INTEGER,"
         "Quarter INTEGER,"
         "BrokerOffset INTEGER,"
         "CreatedAt TEXT NOT NULL,"
         "UNIQUE(SymbolID,TimeframeID,SnapshotTime))",DB_TABLE_SNAPSHOTS);

      ddl[3] = StringFormat("CREATE INDEX IF NOT EXISTS idx_snap_time ON %s(SnapshotTime)",DB_TABLE_SNAPSHOTS);
      ddl[4] = StringFormat("CREATE INDEX IF NOT EXISTS idx_snap_symbol ON %s(SymbolID)",DB_TABLE_SNAPSHOTS);
      ddl[5] = StringFormat("CREATE INDEX IF NOT EXISTS idx_snap_tf ON %s(TimeframeID)",DB_TABLE_SNAPSHOTS);
      ddl[6] = StringFormat("CREATE INDEX IF NOT EXISTS idx_snap_session ON %s(CurrentSession)",DB_TABLE_SNAPSHOTS);
      ddl[7] = StringFormat("CREATE INDEX IF NOT EXISTS idx_snap_hour ON %s(CurrentHour)",DB_TABLE_SNAPSHOTS);
      ddl[8] = StringFormat("CREATE INDEX IF NOT EXISTS idx_snap_weekday ON %s(Weekday)",DB_TABLE_SNAPSHOTS);
     }

   //--- schema v3: trade intelligence table + indexes (Task 0007)
   static void         MigrationToV3(string &ddl[])
     {
      ArrayResize(ddl,7);

      ddl[0] = StringFormat(
         "CREATE TABLE IF NOT EXISTS %s ("
         "TradeID INTEGER PRIMARY KEY AUTOINCREMENT,"
         "Ticket INTEGER NOT NULL UNIQUE,"
         "SymbolID INTEGER NOT NULL,"
         "TimeframeID INTEGER NOT NULL,"
         "Magic INTEGER NOT NULL,"
         "Direction INTEGER NOT NULL,"
         "Lots REAL NOT NULL,"
         "EntryTime INTEGER NOT NULL,"
         "ExitTime INTEGER,"
         "EntryPrice REAL NOT NULL,"
         "ExitPrice REAL,"
         "Profit REAL,"
         "Swap REAL,"
         "Commission REAL,"
         "NetProfit REAL,"
         "TradeDurationSeconds INTEGER,"
         "TradeDurationBars INTEGER,"
         "ExitReason INTEGER,"
         "BreakEvenUsed INTEGER NOT NULL DEFAULT 0,"
         "CarryUsed INTEGER NOT NULL DEFAULT 0,"
         "MomentumUsed INTEGER NOT NULL DEFAULT 0,"
         "ProfitLockUsed INTEGER NOT NULL DEFAULT 0,"
         "EntrySnapshotID INTEGER REFERENCES %s(SnapshotID),"
         "ExitSnapshotID INTEGER REFERENCES %s(SnapshotID),"
         "CreatedAt TEXT NOT NULL)",
         DB_TABLE_TRADES,DB_TABLE_SNAPSHOTS,DB_TABLE_SNAPSHOTS);

      ddl[1] = StringFormat("CREATE INDEX IF NOT EXISTS idx_trade_ticket ON %s(Ticket)",DB_TABLE_TRADES);
      ddl[2] = StringFormat("CREATE INDEX IF NOT EXISTS idx_trade_entry ON %s(EntryTime)",DB_TABLE_TRADES);
      ddl[3] = StringFormat("CREATE INDEX IF NOT EXISTS idx_trade_exit ON %s(ExitTime)",DB_TABLE_TRADES);
      ddl[4] = StringFormat("CREATE INDEX IF NOT EXISTS idx_trade_dir ON %s(Direction)",DB_TABLE_TRADES);
      ddl[5] = StringFormat("CREATE INDEX IF NOT EXISTS idx_trade_reason ON %s(ExitReason)",DB_TABLE_TRADES);
      ddl[6] = StringFormat("CREATE INDEX IF NOT EXISTS idx_trade_symbol ON %s(SymbolID)",DB_TABLE_TRADES);
     }

   //--- schema v4: observation engine tables + indexes (Task 0008)
   static void         MigrationToV4(string &ddl[])
     {
      ArrayResize(ddl,6);

      ddl[0] = StringFormat(
         "CREATE TABLE IF NOT EXISTS %s ("
         "ObservationID INTEGER PRIMARY KEY AUTOINCREMENT,"
         "SymbolID INTEGER NOT NULL,"
         "TimeframeID INTEGER NOT NULL,"
         "ObservationTime INTEGER NOT NULL,"
         "BarTime INTEGER NOT NULL,"
         "ObservationType INTEGER NOT NULL,"
         "FeatureSnapshotID INTEGER REFERENCES %s(SnapshotID),"
         "TradeID INTEGER REFERENCES %s(TradeID),"
         "Session INTEGER,"
         "Hour INTEGER,"
         "Weekday INTEGER,"
         "Month INTEGER,"
         "CreatedAt TEXT NOT NULL,"
         "UNIQUE(SymbolID,TimeframeID,BarTime,ObservationType))",
         DB_TABLE_OBSERVATIONS,DB_TABLE_SNAPSHOTS,DB_TABLE_TRADES);

      ddl[1] = StringFormat("CREATE INDEX IF NOT EXISTS idx_obs_time ON %s(ObservationTime)",DB_TABLE_OBSERVATIONS);
      ddl[2] = StringFormat("CREATE INDEX IF NOT EXISTS idx_obs_bar ON %s(BarTime)",DB_TABLE_OBSERVATIONS);
      ddl[3] = StringFormat("CREATE INDEX IF NOT EXISTS idx_obs_type ON %s(ObservationType)",DB_TABLE_OBSERVATIONS);
      ddl[4] = StringFormat("CREATE INDEX IF NOT EXISTS idx_obs_symbol ON %s(SymbolID)",DB_TABLE_OBSERVATIONS);
      ddl[5] = StringFormat("CREATE INDEX IF NOT EXISTS idx_obs_tf ON %s(TimeframeID)",DB_TABLE_OBSERVATIONS);
     }

   //--- schema v5: label engine tables + indexes (Task 0009)
   static void         MigrationToV5(string &ddl[])
     {
      ArrayResize(ddl,5);

      ddl[0] = StringFormat(
         "CREATE TABLE IF NOT EXISTS %s ("
         "LabelID INTEGER PRIMARY KEY AUTOINCREMENT,"
         "ObservationID INTEGER NOT NULL REFERENCES %s(ObservationID),"
         "LabelVersion INTEGER NOT NULL,"
         "LookaheadBars INTEGER NOT NULL,"
         "FutureHigh REAL NOT NULL,"
         "FutureLow REAL NOT NULL,"
         "FutureClose REAL NOT NULL,"
         "MaxFavorableExcursion REAL NOT NULL,"
         "MaxAdverseExcursion REAL NOT NULL,"
         "DirectionLabel INTEGER NOT NULL,"
         "BreakoutSuccess INTEGER NOT NULL DEFAULT 0,"
         "LabelQuality INTEGER NOT NULL,"
         "GeneratedAt TEXT NOT NULL,"
         "UNIQUE(ObservationID,LabelVersion))",
         DB_TABLE_LABELS,DB_TABLE_OBSERVATIONS);

      ddl[1] = StringFormat("CREATE INDEX IF NOT EXISTS idx_label_obs ON %s(ObservationID)",DB_TABLE_LABELS);
      ddl[2] = StringFormat("CREATE INDEX IF NOT EXISTS idx_label_dir ON %s(DirectionLabel)",DB_TABLE_LABELS);
      ddl[3] = StringFormat("CREATE INDEX IF NOT EXISTS idx_label_look ON %s(LookaheadBars)",DB_TABLE_LABELS);
      ddl[4] = StringFormat("CREATE INDEX IF NOT EXISTS idx_label_gen ON %s(GeneratedAt)",DB_TABLE_LABELS);
     }

   //--- schema v6: research dataset tables + indexes (Task 0010)
   static void         MigrationToV6(string &ddl[])
     {
      ArrayResize(ddl,5);

      ddl[0] = StringFormat(
         "CREATE TABLE IF NOT EXISTS %s ("
         "DatasetID INTEGER PRIMARY KEY AUTOINCREMENT,"
         "DatasetVersion INTEGER NOT NULL,"
         "ObservationID INTEGER NOT NULL REFERENCES %s(ObservationID),"
         "SnapshotID INTEGER NOT NULL REFERENCES %s(SnapshotID),"
         "LabelID INTEGER NOT NULL REFERENCES %s(LabelID),"
         "TradeID INTEGER REFERENCES %s(TradeID),"
         "ExportStatus INTEGER NOT NULL DEFAULT 0,"
         "CreatedAt TEXT NOT NULL,"
         "UNIQUE(DatasetVersion,ObservationID))",
         DB_TABLE_DATASETS,DB_TABLE_OBSERVATIONS,DB_TABLE_SNAPSHOTS,
         DB_TABLE_LABELS,DB_TABLE_TRADES);

      ddl[1] = StringFormat("CREATE INDEX IF NOT EXISTS idx_ds_obs ON %s(ObservationID)",DB_TABLE_DATASETS);
      ddl[2] = StringFormat("CREATE INDEX IF NOT EXISTS idx_ds_label ON %s(LabelID)",DB_TABLE_DATASETS);
      ddl[3] = StringFormat("CREATE INDEX IF NOT EXISTS idx_ds_version ON %s(DatasetVersion)",DB_TABLE_DATASETS);
      ddl[4] = StringFormat("CREATE INDEX IF NOT EXISTS idx_ds_export ON %s(ExportStatus)",DB_TABLE_DATASETS);
     }

   //--- schema v7: data quality reports (Task 0011)
   static void         MigrationToV7(string &ddl[])
     {
      ArrayResize(ddl,2);

      ddl[0] = StringFormat(
         "CREATE TABLE IF NOT EXISTS %s ("
         "QualityID INTEGER PRIMARY KEY AUTOINCREMENT,"
         "DatasetVersion INTEGER NOT NULL,"
         "RowCount INTEGER NOT NULL,"
         "ValidRows INTEGER NOT NULL,"
         "InvalidRows INTEGER NOT NULL,"
         "DuplicateRows INTEGER NOT NULL,"
         "MissingSnapshots INTEGER NOT NULL,"
         "MissingLabels INTEGER NOT NULL,"
         "BrokenReferences INTEGER NOT NULL,"
         "LookAheadViolations INTEGER NOT NULL,"
         "ConsistencyScore INTEGER NOT NULL,"
         "CompletenessScore INTEGER NOT NULL,"
         "IntegrityScore INTEGER NOT NULL,"
         "OverallScore INTEGER NOT NULL,"
         "QualityStatus INTEGER NOT NULL,"
         "GeneratedAt TEXT NOT NULL)",
         DB_TABLE_QUALITY);

      ddl[1] = StringFormat("CREATE INDEX IF NOT EXISTS idx_quality_version ON %s(DatasetVersion)",DB_TABLE_QUALITY);
     }

   //--- schema v8: feature registry (Task 0012)
   static void         MigrationToV8(string &ddl[])
     {
      ArrayResize(ddl,2);

      ddl[0] = StringFormat(
         "CREATE TABLE IF NOT EXISTS %s ("
         "FeatureID INTEGER PRIMARY KEY AUTOINCREMENT,"
         "FeatureName TEXT NOT NULL,"
         "FeatureVersion INTEGER NOT NULL,"
         "FeatureCategory INTEGER NOT NULL,"
         "Description TEXT NOT NULL,"
         "Owner TEXT NOT NULL,"
         "ValidationRule TEXT NOT NULL,"
         "Status INTEGER NOT NULL DEFAULT 0,"
         "CreatedAt TEXT NOT NULL,"
         "DeprecatedAt TEXT,"
         "UNIQUE(FeatureName,FeatureVersion))",
         DB_TABLE_FEATURES);

      ddl[1] = StringFormat("CREATE INDEX IF NOT EXISTS idx_feature_name ON %s(FeatureName)",DB_TABLE_FEATURES);
     }

   //--- schema v9: replay sessions (Sprint 4)
   static void         MigrationToV9(string &ddl[])
     {
      ArrayResize(ddl,2);

      ddl[0] = StringFormat(
         "CREATE TABLE IF NOT EXISTS %s ("
         "ReplayID INTEGER PRIMARY KEY AUTOINCREMENT,"
         "DatasetVersion INTEGER NOT NULL,"
         "SymbolID INTEGER NOT NULL,"
         "TimeframeID INTEGER NOT NULL,"
         "StartTime INTEGER NOT NULL,"
         "EndTime INTEGER NOT NULL,"
         "CurrentReplayTime INTEGER NOT NULL,"
         "ReplayState INTEGER NOT NULL,"
         "ReplaySpeed INTEGER NOT NULL,"
         "CurrentBar INTEGER NOT NULL,"
         "TotalBars INTEGER NOT NULL,"
         "CreatedAt TEXT NOT NULL)",
         DB_TABLE_REPLAY);

      ddl[1] = StringFormat("CREATE INDEX IF NOT EXISTS idx_replay_state ON %s(ReplayState)",DB_TABLE_REPLAY);
     }

   //--- schema v10: research platform tables + indexes (Sprint 5)
   static void         MigrationToV10(string &ddl[])
     {
      ArrayResize(ddl,5);

      ddl[0] = StringFormat(
         "CREATE TABLE IF NOT EXISTS %s ("
         "ExperimentID INTEGER PRIMARY KEY AUTOINCREMENT,"
         "ExperimentName TEXT NOT NULL,"
         "DatasetVersion INTEGER NOT NULL,"
         "FeatureVersion INTEGER NOT NULL,"
         "LabelVersion INTEGER NOT NULL,"
         "QualityVersion INTEGER NOT NULL,"
         "ReplayVersion INTEGER NOT NULL,"
         "ConfigurationHash TEXT NOT NULL,"
         "StartTime INTEGER,"
         "EndTime INTEGER,"
         "DurationSeconds INTEGER,"
         "Status INTEGER NOT NULL DEFAULT 0,"
         "Notes TEXT,"
         "CreatedAt TEXT NOT NULL)",
         DB_TABLE_EXPERIMENTS);

      ddl[1] = StringFormat(
         "CREATE TABLE IF NOT EXISTS %s ("
         "BenchmarkID INTEGER PRIMARY KEY AUTOINCREMENT,"
         "ExperimentID INTEGER NOT NULL REFERENCES %s(ExperimentID),"
         "MetricName TEXT NOT NULL,"
         "MetricValue REAL NOT NULL,"
         "MetricUnit TEXT NOT NULL,"
         "CreatedAt TEXT NOT NULL)",
         DB_TABLE_BENCHMARKS,DB_TABLE_EXPERIMENTS);

      ddl[2] = StringFormat(
         "CREATE TABLE IF NOT EXISTS %s ("
         "RunID INTEGER PRIMARY KEY AUTOINCREMENT,"
         "ExperimentID INTEGER NOT NULL REFERENCES %s(ExperimentID),"
         "TrainingStart INTEGER NOT NULL,"
         "TrainingEnd INTEGER NOT NULL,"
         "TestingStart INTEGER NOT NULL,"
         "TestingEnd INTEGER NOT NULL,"
         "WindowNumber INTEGER NOT NULL,"
         "ResultStatus INTEGER NOT NULL DEFAULT 0,"
         "CreatedAt TEXT NOT NULL)",
         DB_TABLE_WF_RUNS,DB_TABLE_EXPERIMENTS);

      ddl[3] = StringFormat("CREATE INDEX IF NOT EXISTS idx_bench_exp ON %s(ExperimentID)",DB_TABLE_BENCHMARKS);
      ddl[4] = StringFormat("CREATE INDEX IF NOT EXISTS idx_wf_exp ON %s(ExperimentID)",DB_TABLE_WF_RUNS);
     }

   //--- schema v11: historical data platform masters (Sprint 6A)
   static void         MigrationToV11(string &ddl[])
     {
      ArrayResize(ddl,3);

      ddl[0] = StringFormat(
         "CREATE TABLE IF NOT EXISTS %s ("
         "DataSourceID INTEGER PRIMARY KEY AUTOINCREMENT,"
         "BrokerName TEXT NOT NULL,"
         "ServerName TEXT NOT NULL,"
         "AccountType TEXT NOT NULL,"
         "Platform TEXT NOT NULL,"
         "CreatedAt TEXT NOT NULL,"
         "UNIQUE(BrokerName,ServerName,AccountType))",
         DB_TABLE_SOURCES);

      ddl[1] = StringFormat(
         "CREATE TABLE IF NOT EXISTS %s ("
         "ImportID INTEGER PRIMARY KEY AUTOINCREMENT,"
         "DatabaseName TEXT NOT NULL,"
         "DataSourceID INTEGER NOT NULL,"
         "StartedAt TEXT NOT NULL,"
         "FinishedAt TEXT,"
         "RecordsImported INTEGER NOT NULL DEFAULT 0,"
         "Checksum TEXT,"
         "ImportStatus INTEGER NOT NULL DEFAULT 0)",
         DB_TABLE_IMPORTS);

      ddl[2] = StringFormat("CREATE INDEX IF NOT EXISTS idx_import_db ON %s(DatabaseName)",DB_TABLE_IMPORTS);
     }
  };

#endif // __EA_DAL_SCHEMA_MQH__
//+------------------------------------------------------------------+
