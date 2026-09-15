//+------------------------------------------------------------------+
//|                             EAHistory/TickExporter.mqh           |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Historical Data Platform: tick export     |
//+------------------------------------------------------------------+
#ifndef __EA_HISTORY_TICKS_MQH__
#define __EA_HISTORY_TICKS_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAData\DatabaseTypes.mqh>
#include <CandleBreakoutEA\EAHistory\HistoryTypes.mqh>
#include <CandleBreakoutEA\EAHistory\HistoryStore.mqh>

//+------------------------------------------------------------------+
//| TASK 1: raw tick archive. Full export, interruption recovery,    |
//| incremental sync, zero duplicates (UNIQUE + INSERT OR IGNORE).   |
//+------------------------------------------------------------------+
class CTickExporter
  {
private:
   const CEASettings  *m_set;
   CLogger            *m_log;
   CHistoryStore      *m_store;
   int                 m_symbol_id;
   int                 m_source_id;
   int                 m_broker_offset;
   long                m_progress_step;

   bool                EnsureTable(void)
     {
      IDataProvider *db = m_store.Provider();
      const string ddl[] =
        {
         StringFormat("CREATE TABLE IF NOT EXISTS %s ("
            "TickID INTEGER PRIMARY KEY AUTOINCREMENT,"
            "SymbolID INTEGER NOT NULL,"
            "BrokerTime INTEGER NOT NULL,"
            "UTCTime INTEGER NOT NULL,"
            "Bid REAL NOT NULL,"
            "Ask REAL NOT NULL,"
            "Last REAL,"
            "Volume INTEGER,"
            "Flags INTEGER,"
            "Spread REAL,"
            "Milliseconds INTEGER,"
            "BrokerOffset INTEGER,"
            "DataSourceID INTEGER,"
            "ImportBatchID INTEGER,"
            "ImportedAt TEXT NOT NULL,"
            "UNIQUE(SymbolID,BrokerTime,Milliseconds,Bid,Ask))",HIST_TABLE_TICKS),
         StringFormat("CREATE INDEX IF NOT EXISTS idx_tick_symbol ON %s(SymbolID)",HIST_TABLE_TICKS),
         StringFormat("CREATE INDEX IF NOT EXISTS idx_tick_btime ON %s(BrokerTime)",HIST_TABLE_TICKS),
         StringFormat("CREATE INDEX IF NOT EXISTS idx_tick_utc ON %s(UTCTime)",HIST_TABLE_TICKS)
        };
      for(int i=0; i<ArraySize(ddl); i++)
         if(!db.Execute(ddl[i]))
           {
            m_log.Warn("Tick table DDL failed");
            return(false);
           }
      return(true);
     }

   //--- core paged export from from_ms onward; returns imported rows
   long                ExportFromMs(const datetime from,const long batch_id)
     {
      IDataProvider *db = m_store.Provider();
      const string symbol = m_set.symbol_name;
      const string stamp  = TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES);
      ulong from_ms = (ulong)from*1000;
      long  imported = 0, since_log = 0;

      while(!IsStopped())
        {
         MqlTick ticks[];
         const uint got = CopyTicks(symbol,ticks,COPY_TICKS_ALL,from_ms,HIST_TICK_PAGE);
         if(got==0)
            break;

         db.BeginTransaction();
         for(uint i=0; i<got; i++)
           {
            const datetime broker_time = (datetime)(ticks[i].time_msc/1000);
            const int      ms          = (int)(ticks[i].time_msc%1000);
            const double   spread      = (ticks[i].ask>0.0 && ticks[i].bid>0.0
                                          ? (ticks[i].ask-ticks[i].bid)/CEAUtils::PointValue(symbol)
                                          : 0.0);
            const string sql = StringFormat(
               "INSERT OR IGNORE INTO %s (SymbolID,BrokerTime,UTCTime,Bid,Ask,Last,Volume,"
               "Flags,Spread,Milliseconds,BrokerOffset,DataSourceID,ImportBatchID,ImportedAt) "
               "VALUES (%d,%d,%d,%s,%s,%s,%d,%d,%s,%d,%d,%d,%d,'%s')",
               HIST_TABLE_TICKS,m_symbol_id,(int)broker_time,
               (int)(broker_time-(datetime)(m_broker_offset*3600)),
               DoubleToString(ticks[i].bid,8),DoubleToString(ticks[i].ask,8),
               DoubleToString(ticks[i].last,8),(int)ticks[i].volume,(int)ticks[i].flags,
               DoubleToString(spread,2),ms,m_broker_offset,m_source_id,(int)batch_id,stamp);
            if(db.Execute(sql))
              { imported++; since_log++; }
            const ulong last_ms = ticks[i].time_msc;
            if(last_ms+1>from_ms)
               from_ms = last_ms+1;   // resume point: strictly after the last seen tick
           }
         db.Commit();

         if(since_log>=m_progress_step)
           {
            m_log.Info(StringFormat("Tick export | %s | +%d rows | total %d | at %s",
                                    symbol,(int)since_log,(int)imported,
                                    TimeToString((datetime)(from_ms/1000),TIME_DATE|TIME_MINUTES)));
            since_log = 0;
           }
         if(got<HIST_TICK_PAGE)
            break;   // last page
        }
      return(imported);
     }

public:
                       CTickExporter(void) : m_set(NULL), m_log(NULL), m_store(NULL),
                          m_symbol_id(0), m_source_id(0), m_broker_offset(0),
                          m_progress_step(HIST_PROGRESS_TICKS) {}

   void                Initialize(const CEASettings &settings,CLogger &logger,
                                  CHistoryStore &store,const int source_id,
                                  const int broker_offset)
     {
      m_set           = &settings;
      m_log           = &logger;
      m_store         = &store;
      m_source_id     = source_id;
      m_broker_offset = broker_offset;
     }

   void                SetProgressStep(const long ticks) { if(ticks>0) m_progress_step = ticks; }

   //--- full history export (resumes automatically when rows exist)
   long                ExportHistory(const long batch_id)
     {
      if(m_store==NULL || !m_store.IsOpen())
         return(-1);
      m_symbol_id = m_store.SymbolId(m_set.symbol_name);
      if(m_symbol_id<=0 || !EnsureTable())
         return(-1);
      const datetime latest = m_store.LatestTimestamp(HIST_TABLE_TICKS,"BrokerTime",m_symbol_id);
      const datetime from   = (latest>0 ? latest : (datetime)(TimeCurrent()-3650*86400));
      m_log.Info(StringFormat("Tick export started | %s | from %s",m_set.symbol_name,
                              TimeToString(from,TIME_DATE|TIME_MINUTES)));
      const long imported = ExportFromMs(from,batch_id);
      m_log.Info(StringFormat("Tick export finished | %s | %d rows",m_set.symbol_name,(int)imported));
      return(imported);
     }

   //--- TASK 5: incremental sync - only what arrived since the last run
   long                SyncLatestTicks(const long batch_id)
     {
      if(m_store==NULL || !m_store.IsOpen())
         return(-1);
      m_symbol_id = m_store.SymbolId(m_set.symbol_name);
      if(m_symbol_id<=0 || !EnsureTable())
         return(-1);
      const datetime latest = m_store.LatestTimestamp(HIST_TABLE_TICKS,"BrokerTime",m_symbol_id);
      if(latest<=0)
         return(ExportHistory(batch_id));   // nothing stored yet: full pass
      return(ExportFromMs(latest,batch_id));
     }

   //--- resume after an interrupted run: continue from the stored maximum
   long                ResumeExport(const long batch_id)
     {
      return(ExportHistory(batch_id));
     }

   //--- TASK 4 (tick side): basic structural validation of the archive
   bool                ValidateTicks(string &report)
     {
      report = "";
      if(m_store==NULL || !m_store.IsOpen())
         return(false);
      IDataProvider *db = m_store.Provider();
      string rows[];
      if(db.Select(StringFormat(
            "SELECT COUNT(*),"
            "SUM(CASE WHEN Bid<=0 OR Ask<=0 THEN 1 ELSE 0 END),"
            "SUM(CASE WHEN Ask<Bid THEN 1 ELSE 0 END),"
            "SUM(CASE WHEN Spread<0 THEN 1 ELSE 0 END) FROM %s",HIST_TABLE_TICKS),rows)!=1)
         return(false);
      string c[];
      if(StringSplit(rows[0],';',c)!=4)
         return(false);
      report = StringFormat("ticks total=%s invalid_price=%s crossed=%s negative_spread=%s",
                            c[0],c[1],c[2],c[3]);
      return(true);
     }
  };

#endif // __EA_HISTORY_TICKS_MQH__
//+------------------------------------------------------------------+
