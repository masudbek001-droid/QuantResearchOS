//+------------------------------------------------------------------+
//|                             EAHistory/HistoryTypes.mqh           |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Historical Data Platform: shared types    |
//+------------------------------------------------------------------+
#ifndef __EA_HISTORY_TYPES_MQH__
#define __EA_HISTORY_TYPES_MQH__

//+------------------------------------------------------------------+
//| The four databases of the platform (Sprint 6A).                  |
//| Research.db is the existing EA database (schema v11) and is      |
//| managed by the DAL; the other three are dedicated stores.        |
//+------------------------------------------------------------------+
#define HIST_DIR        "CBEA"
#define HIST_DB_TICKS   "CBEA_Ticks.db"
#define HIST_DB_MARKET  "CBEA_Market.db"
#define HIST_DB_MODELS  "CBEA_Models.db"

//--- table names inside the dedicated stores
#define HIST_TABLE_TICKS   "Ticks"
#define HIST_TABLE_BARS    "Bars"
#define HIST_TABLE_SYMBOLS "Symbols"
#define HIST_TABLE_TFS     "Timeframes"
#define HIST_TABLE_MODELV  "ModelsSchemaVersion"

//--- export paging / progress defaults (configurable through the facade)
#define HIST_TICK_PAGE       100000   // ticks per CopyTicks page
#define HIST_BAR_PAGE        50000    // bars per CopyRates page
#define HIST_PROGRESS_TICKS  1000000  // log line every N ticks
#define HIST_PROGRESS_BARS   100000   // log line every N bars

//+------------------------------------------------------------------+
//| The seven stored timeframes, keyed by ENUM_TIMEFRAMES values     |
//+------------------------------------------------------------------+
const ENUM_TIMEFRAMES HIST_TIMEFRAMES[7] =
  {PERIOD_M1,PERIOD_M5,PERIOD_M15,PERIOD_M30,PERIOD_H1,PERIOD_H4,PERIOD_D1};

#endif // __EA_HISTORY_TYPES_MQH__
//+------------------------------------------------------------------+
