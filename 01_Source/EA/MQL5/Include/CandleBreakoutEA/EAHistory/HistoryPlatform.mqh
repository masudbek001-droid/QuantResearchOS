//+------------------------------------------------------------------+
//|                            EAHistory/HistoryPlatform.mqh         |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Historical Data Platform: facade          |
//+------------------------------------------------------------------+
#ifndef __EA_HISTORY_PLATFORM_MQH__
#define __EA_HISTORY_PLATFORM_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAData\DatabaseTypes.mqh>
#include <CandleBreakoutEA\EAData\DatabaseManager.mqh>
#include <CandleBreakoutEA\EAHistory\HistoryTypes.mqh>
#include <CandleBreakoutEA\EAHistory\HistoryStore.mqh>
#include <CandleBreakoutEA\EAHistory\TickExporter.mqh>
#include <CandleBreakoutEA\EAHistory\BarExporter.mqh>
#include <CandleBreakoutEA\EAHistory\MetadataExporter.mqh>
#include <CandleBreakoutEA\EAHistory\DataIntegrityValidator.mqh>

//+------------------------------------------------------------------+
//| The single entry point of the Historical Data Platform.          |
//| Owns Ticks.db / Market.db / Models.db, registers the broker as   |
//| a DataSource, tracks imports in Research.db (ImportHistory) and  |
//| exposes full export, incremental sync, integrity and statistics. |
//| Dormant at init: exports run only through explicit calls.        |
//+------------------------------------------------------------------+
class CHistoryPlatform
  {
private:
   const CEASettings  *m_set;
   CLogger            *m_log;
   CDatabaseManager   *m_research;      // Research.db through the DAL

   CHistoryStore       m_ticks;
   CHistoryStore       m_market;
   CHistoryStore       m_models;

   CTickExporter       m_tick_exporter;
   CBarExporter        m_bar_exporter;
   CMetadataExporter   m_ticks_meta;
   CMetadataExporter   m_market_meta;
   CDataIntegrityValidator m_integrity;

   int                 m_source_id;
   int                 m_broker_offset;
   bool                m_ready;

   //--- register (or find) this broker/server/account as a data source
   bool                RegisterDataSource(void)
     {
      const string broker  = TerminalInfoString(TERMINAL_COMPANY);
      const string server  = AccountInfoString(ACCOUNT_SERVER);
      const string account = (AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO
                              ? "demo" : "real");
      const string platform= "MT5 build " + IntegerToString(TerminalInfoInteger(TERMINAL_BUILD));
      const string stamp   = TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES);
      const string sql = StringFormat(
         "INSERT OR IGNORE INTO %s (BrokerName,ServerName,AccountType,Platform,CreatedAt) "
         "VALUES ('%s','%s','%s','%s','%s')",
         DB_TABLE_SOURCES,broker,server,account,platform,stamp);
      if(!m_research.Execute(sql))
         return(false);
      string rows[];
      if(m_research.Select(StringFormat(
            "SELECT DataSourceID FROM %s WHERE BrokerName='%s' AND ServerName='%s' AND AccountType='%s'",
            DB_TABLE_SOURCES,broker,server,account),rows)!=1)
         return(false);
      m_source_id = (int)StringToInteger(rows[0]);
      return(m_source_id>0);
     }

   //--- Models.db: architecture only, single version table
   bool                PrepareModelsDb(void)
     {
      if(!m_models.Provider().Execute(StringFormat(
            "CREATE TABLE IF NOT EXISTS %s (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL)",
            HIST_TABLE_MODELV)))
         return(false);
      string rows[];
      if(m_models.Provider().Select(StringFormat(
            "SELECT COUNT(*) FROM %s",HIST_TABLE_MODELV),rows)==1 &&
         StringToInteger(rows[0])==0)
         return(m_models.Provider().Execute(StringFormat(
            "INSERT INTO %s (version,applied_at) VALUES (1,'%s')",HIST_TABLE_MODELV,
            TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES))));
      return(true);
     }

public:
                       CHistoryPlatform(void) : m_set(NULL), m_log(NULL), m_research(NULL),
                          m_source_id(0), m_broker_offset(0), m_ready(false) {}

   bool                Initialize(const CEASettings &settings,CLogger &logger,
                                  CDatabaseManager &research)
     {
      m_set      = &settings;
      m_log      = &logger;
      m_research = &research;
      if(!m_research.IsOpen())
        {
         m_log.Warn("History platform idle | research database is closed");
         return(false);
        }
      m_broker_offset = (int)MathRound((double)(TimeCurrent()-TimeGMT())/3600.0);
      if(!RegisterDataSource())
        {
         m_log.Warn("History platform idle | data source registration failed");
         return(false);
        }
      if(!m_ticks.Open(HIST_DB_TICKS,logger) || !m_market.Open(HIST_DB_MARKET,logger) ||
         !m_models.Open(HIST_DB_MODELS,logger) || !PrepareModelsDb())
        {
         m_log.Warn("History platform idle | store open failed");
         return(false);
        }

      m_tick_exporter.Initialize(settings,logger,m_ticks,m_source_id,m_broker_offset);
      m_bar_exporter.Initialize(settings,logger,m_market,m_source_id,m_broker_offset);
      m_ticks_meta.Initialize(settings,logger,m_ticks,m_source_id);
      m_market_meta.Initialize(settings,logger,m_market,m_source_id);
      m_integrity.Initialize(logger);

      m_ready = true;
      m_log.Info(StringFormat("History platform ready | source #%d | offset %+d h",
                              m_source_id,m_broker_offset));
      return(true);
     }

   bool                IsReady(void) const { return(m_ready); }

   //--- import bookkeeping in Research.db
   long                BeginImport(const string database_name)
     {
      const string stamp = TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES);
      if(m_research.Insert(StringFormat(
            "INSERT INTO %s (DatabaseName,DataSourceID,StartedAt,ImportStatus) "
            "VALUES ('%s',%d,'%s',%d)",
            DB_TABLE_IMPORTS,database_name,m_source_id,stamp,(int)IMPORT_RUNNING))!=1)
         return(0);
      string rows[];
      if(m_research.Select(StringFormat("SELECT MAX(ImportID) FROM %s",DB_TABLE_IMPORTS),rows)!=1)
         return(0);
      return(StringToInteger(rows[0]));
     }

   void                FinishImport(const long import_id,const long records,
                                    const string checksum,const ENUM_IMPORT_STATUS status)
     {
      m_research.Update(StringFormat(
         "UPDATE %s SET FinishedAt='%s',RecordsImported=%d,Checksum='%s',ImportStatus=%d "
         "WHERE ImportID=%d",
         DB_TABLE_IMPORTS,TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES),
         (int)records,checksum,(int)status,(int)import_id));
     }

   //--- full export: ticks + all bar timeframes + metadata (resumable)
   bool                ExportAllHistory(string &report)
     {
      if(!m_ready)
         return(false);
      const long tick_batch = BeginImport(m_ticks.Name());
      const long ticks = m_tick_exporter.ExportHistory(tick_batch);
      FinishImport(tick_batch,(ticks>0 ? ticks : 0),
                   IntegerToString(ticks>0 ? ticks : 0),
                   (ticks>=0 ? IMPORT_FINISHED : IMPORT_FAILED));
      m_ticks_meta.ExportMetadata();

      const long bar_batch = BeginImport(m_market.Name());
      const long bars = m_bar_exporter.ExportBars(bar_batch);
      FinishImport(bar_batch,(bars>0 ? bars : 0),
                   IntegerToString(bars>0 ? bars : 0),
                   (bars>=0 ? IMPORT_FINISHED : IMPORT_FAILED));
      m_market_meta.ExportMetadata();

      report = StringFormat("export: ticks=%d bars=%d",(int)ticks,(int)bars);
      return(ticks>=0 && bars>=0);
     }

   //--- TASK 5: incremental synchronization (missing history only)
   bool                SyncIncremental(string &report)
     {
      if(!m_ready)
         return(false);
      const long tick_batch = BeginImport(m_ticks.Name());
      const long ticks = m_tick_exporter.SyncLatestTicks(tick_batch);
      FinishImport(tick_batch,(ticks>0 ? ticks : 0),IntegerToString(ticks>0 ? ticks : 0),
                   (ticks>=0 ? IMPORT_FINISHED : IMPORT_FAILED));

      const long bar_batch = BeginImport(m_market.Name());
      const long bars = m_bar_exporter.SynchronizeBars(bar_batch);
      FinishImport(bar_batch,(bars>0 ? bars : 0),IntegerToString(bars>0 ? bars : 0),
                   (bars>=0 ? IMPORT_FINISHED : IMPORT_FAILED));

      report = StringFormat("sync: new ticks=%d new bars=%d",(int)ticks,(int)bars);
      return(ticks>=0 && bars>=0);
     }

   //--- TASK 4: full integrity pass with a combined report
   bool                ValidateIntegrity(string &report)
     {
      if(!m_ready)
         return(false);
      string tick_report = "", bar_report = "", tf_report = "";
      const bool ticks_ok = m_integrity.ValidateTicks(m_ticks,tick_report);
      const bool bars_ok  = m_integrity.ValidateBars(m_market,bar_report);
      const bool tfs_ok   = m_integrity.ValidateTimeframes(m_market,tf_report);
      report = tick_report + "\n" + bar_report + tf_report;
      return(ticks_ok && bars_ok && tfs_ok);
     }

   //--- TASK 6: platform statistics
   bool                GenerateStatistics(string &report)
     {
      if(!m_ready)
         return(false);
      const long tick_count = m_ticks.CountRows(HIST_TABLE_TICKS);
      const long bar_count  = m_market.CountRows(HIST_TABLE_BARS);
      string tf_lines = "";
      for(int i=0; i<7; i++)
        {
         const ENUM_TIMEFRAMES tf = HIST_TIMEFRAMES[i];
         string rows[];
         long count = 0;
         string coverage = "";
         if(m_market.Provider().Select(StringFormat(
               "SELECT COUNT(*),MIN(OpenTime),MAX(OpenTime) FROM %s WHERE TimeframeID=%d",
               HIST_TABLE_BARS,(int)tf),rows)==1)
           {
            string c[];
            if(StringSplit(rows[0],';',c)==3)
              {
               count = StringToInteger(c[0]);
               if(count>0)
                  coverage = StringFormat(" %s..%s",
                     TimeToString((datetime)StringToInteger(c[1]),TIME_DATE),
                     TimeToString((datetime)StringToInteger(c[2]),TIME_DATE));
              }
           }
         tf_lines += StringFormat("  %s: %d%s\n",EnumToString(tf),(int)count,coverage);
        }
      report = StringFormat(
         "history statistics | %s\n"
         "ticks total: %d (Ticks.db %d bytes)\n"
         "bars total: %d (Market.db %d bytes)\n"
         "Models.db %d bytes (architecture only)\n"
         "per timeframe:\n%s",
         m_set.symbol_name,
         (int)tick_count,(int)m_ticks.FileSizeBytes(),
         (int)bar_count,(int)m_market.FileSizeBytes(),
         (int)m_models.FileSizeBytes(),
         tf_lines);
      return(true);
     }

   void                Shutdown(void)
     {
      m_ticks.Close();
      m_market.Close();
      m_models.Close();
      m_ready = false;
     }
  };

#endif // __EA_HISTORY_PLATFORM_MQH__
//+------------------------------------------------------------------+
