//+------------------------------------------------------------------+
//|                              EAData/DatabaseTypes.mqh            |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Data Access Layer: shared types           |
//+------------------------------------------------------------------+
#ifndef __EA_DAL_TYPES_MQH__
#define __EA_DAL_TYPES_MQH__

//+------------------------------------------------------------------+
//| Schema and file constants. The schema version moves only through |
//| an ADR + migration record.                                       |
//+------------------------------------------------------------------+
#define DB_SCHEMA_VERSION   11
#define DB_PRODUCT_NAME     "CandleBreakoutEA"
#define DB_FILE_PREFIX      "candlebreakout_"
#define DB_FILE_EXT         ".db"

//+------------------------------------------------------------------+
//| Metadata table names (schema v1 - metadata only, no trade data)  |
//+------------------------------------------------------------------+
#define DB_TABLE_INFO       "DatabaseInfo"
#define DB_TABLE_VERSION    "SchemaVersion"
#define DB_TABLE_MIGRATION  "MigrationHistory"
//--- schema v2: market intelligence (metadata + observations, no trade data)
#define DB_TABLE_SYMBOLS    "Symbols"
#define DB_TABLE_TIMEFRAMES "Timeframes"
#define DB_TABLE_SNAPSHOTS  "MarketSnapshots"
//--- schema v3: trade intelligence (metadata for research, not reporting)
#define DB_TABLE_TRADES     "Trades"
//--- schema v4: observation engine (market recording, trade-independent)
#define DB_TABLE_OBSERVATIONS "Observations"
//--- schema v5: label engine (ground-truth outcome labels)
#define DB_TABLE_LABELS     "ObservationLabels"
//--- schema v6: research datasets (ML export foundation)
#define DB_TABLE_DATASETS   "ResearchDatasets"
//--- schema v7: research data quality
#define DB_TABLE_QUALITY    "DatasetQuality"
//--- schema v8: feature registry (official feature catalogue)
#define DB_TABLE_FEATURES   "FeatureRegistry"
//--- schema v9: replay foundation
#define DB_TABLE_REPLAY     "ReplaySessions"
//--- schema v10: research platform
#define DB_TABLE_EXPERIMENTS "Experiments"
#define DB_TABLE_BENCHMARKS "Benchmarks"
#define DB_TABLE_WF_RUNS    "WalkForwardRuns"
//--- schema v11: historical data platform master tables (Sprint 6A)
#define DB_TABLE_SOURCES    "DataSources"
#define DB_TABLE_IMPORTS    "ImportHistory"

//+------------------------------------------------------------------+
//| Import run state (ImportHistory.ImportStatus)                    |
//+------------------------------------------------------------------+
enum ENUM_IMPORT_STATUS
  {
   IMPORT_RUNNING     = 0,
   IMPORT_FINISHED    = 1,
   IMPORT_FAILED      = 2,
   IMPORT_INTERRUPTED = 3   // resumable: next run continues from the last record
  };

//+------------------------------------------------------------------+
//| Experiment lifecycle. Completed experiments are immutable.       |
//+------------------------------------------------------------------+
enum ENUM_EXPERIMENT_STATUS
  {
   EXPERIMENT_CREATED   = 0,
   EXPERIMENT_RUNNING   = 1,
   EXPERIMENT_COMPLETED = 2,
   EXPERIMENT_CANCELLED = 3
  };

//+------------------------------------------------------------------+
//| Walk-forward window modes and run states                         |
//+------------------------------------------------------------------+
enum ENUM_WF_MODE
  {
   WF_ROLLING  = 0,  // fixed-length training window slides forward
   WF_EXPANDING= 1,  // training start anchored, end grows
   WF_FIXED    = 2   // disjoint consecutive train/test blocks
  };

enum ENUM_WF_STATUS
  {
   WF_CREATED  = 0,
   WF_RUNNING  = 1,
   WF_FINISHED = 2,
   WF_FAILED   = 3
  };

//+------------------------------------------------------------------+
//| STEP 2: feature categories                                       |
//+------------------------------------------------------------------+
enum ENUM_FEATURE_CATEGORY
  {
   FEATURE_PRICE       = 0,
   FEATURE_VOLATILITY  = 1,
   FEATURE_TREND       = 2,
   FEATURE_SESSION     = 3,
   FEATURE_TIME        = 4,
   FEATURE_STATISTICAL = 5,
   FEATURE_CUSTOM      = 6
  };
#define FEATURE_CATEGORIES_TOTAL 7

//+------------------------------------------------------------------+
//| Calculation status of a registered feature                       |
//+------------------------------------------------------------------+
enum ENUM_FEATURE_STATUS
  {
   FEATURE_ACTIVE     = 0, // calculated and validated
   FEATURE_RESERVED   = 1, // defined, not calculated yet
   FEATURE_DEPRECATED = 2  // superseded, kept for reproducibility
  };

//+------------------------------------------------------------------+
//| STEP 2: quality verdict of a dataset version                     |
//+------------------------------------------------------------------+
enum ENUM_QUALITY_STATUS
  {
   QUALITY_UNKNOWN = 0, // never analyzed
   QUALITY_PASS    = 1, // clean: safe for ML export
   QUALITY_WARNING = 2, // usable with caution, export blocked
   QUALITY_FAIL    = 3  // hard violation, export blocked
  };

//+------------------------------------------------------------------+
//| Export pipeline state of a dataset row                           |
//+------------------------------------------------------------------+
enum ENUM_DATASET_EXPORT
  {
   DATASET_EXPORT_NONE     = 0, // built, not exported yet
   DATASET_EXPORT_CSV      = 1, // reproducible CSV written
   DATASET_EXPORT_PARQUET  = 2, // placeholder for a future writer
   DATASET_EXPORT_INTERNAL = 3  // consumed inside SQLite only
  };

//+------------------------------------------------------------------+
//| Result of every DAL operation                                    |
//+------------------------------------------------------------------+
enum ENUM_DB_STATUS
  {
   DB_OK                = 0, // operation succeeded
   DB_ERR_OPEN          = 1, // database file could not be opened
   DB_ERR_CONNECTION    = 2, // handle invalid / connection lost
   DB_ERR_EXECUTE       = 3, // statement failed
   DB_ERR_SCHEMA        = 4, // metadata tables missing or damaged
   DB_ERR_VERSION       = 5, // schema version unsupported
   DB_ERR_TRANSACTION   = 6, // transactions unavailable
   DB_ERR_VALIDATION    = 7  // input rejected by validation rules
  };

//+------------------------------------------------------------------+
string DbStatusToString(const ENUM_DB_STATUS status)
  {
   switch(status)
     {
      case DB_OK:               return("OK");
      case DB_ERR_OPEN:         return("open failed");
      case DB_ERR_CONNECTION:   return("connection invalid");
      case DB_ERR_EXECUTE:      return("statement failed");
      case DB_ERR_SCHEMA:       return("schema damaged");
      case DB_ERR_VERSION:      return("version unsupported");
      case DB_ERR_TRANSACTION:  return("transactions unavailable");
      case DB_ERR_VALIDATION:   return("validation failed");
     }
   return("unknown");
  }

#endif // __EA_DAL_TYPES_MQH__
//+------------------------------------------------------------------+
