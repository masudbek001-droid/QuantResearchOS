//+------------------------------------------------------------------+
//|                              EAHistory/BarExporter.mqh           |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Historical Data Platform: bar export      |
//+------------------------------------------------------------------+
#ifndef __EA_HISTORY_BARS_MQH__
#define __EA_HISTORY_BARS_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAData\DatabaseTypes.mqh>
#include <CandleBreakoutEA\EAHistory\HistoryTypes.mqh>
#include <CandleBreakoutEA\EAHistory\HistoryStore.mqh>

//+------------------------------------------------------------------+
//| TASK 2: historical OHLC archive for M1..D1. Paged, resumable,    |
//| incremental, duplicate-free (UNIQUE + INSERT OR IGNORE).         |
//+------------------------------------------------------------------+
class CBarExporter
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
            "BarID INTEGER PRIMARY KEY AUTOINCREMENT,"
            "SymbolID INTEGER NOT NULL,"
            "TimeframeID INTEGER NOT NULL,"
            "OpenTime INTEGER NOT NULL,"
            "Open REAL NOT NULL,"
            "High REAL NOT NULL,"
            "Low REAL NOT NULL,"
            "Close REAL NOT NULL,"
            "TickVolume INTEGER NOT NULL,"
            "RealVolume INTEGER NOT NULL DEFAULT 0,"
            "Spread REAL,"
            "Session INTEGER,"
            "Weekday INTEGER,"
            "Month INTEGER,"
            "Quarter INTEGER,"
            "DST INTEGER,"
            "BrokerOffset INTEGER,"
            "DataSourceID INTEGER,"
            "ImportBatchID INTEGER,"
            "ImportedAt TEXT NOT NULL,"
            "UNIQUE(SymbolID,TimeframeID,OpenTime))",HIST_TABLE_BARS),
         StringFormat("CREATE INDEX IF NOT EXISTS idx_bar_symbol ON %s(SymbolID)",HIST_TABLE_BARS),
         StringFormat("CREATE INDEX IF NOT EXISTS idx_bar_tf ON %s(TimeframeID)",HIST_TABLE_BARS),
         StringFormat("CREATE INDEX IF NOT EXISTS idx_bar_time ON %s(OpenTime)",HIST_TABLE_BARS)
        };
      for(int i=0; i<ArraySize(ddl); i++)
         if(!db.Execute(ddl[i]))
           {
            m_log.Warn("Bar table DDL failed");
            return(false);
           }
      //--- cleanup from early builds that stored H1/H4/D1 as minute IDs
      if(!db.Execute(StringFormat("DELETE FROM %s WHERE TimeframeID IN (60,240,1440)",
                                  HIST_TABLE_BARS)))
        {
         m_log.Warn("Legacy bar timeframe cleanup failed");
         return(false);
        }
      return(true);
     }

   //--- clock fields of a bar open time
   void                ClockOf(const datetime moment,int &session,int &weekday,
                               int &month,int &quarter)
     {
      MqlDateTime stamp;
      TimeToStruct(moment,stamp);
      weekday = stamp.day_of_week;
      month   = stamp.mon;
      quarter = (stamp.mon-1)/3+1;
      session = (stamp.hour<8 ? 0 : (stamp.hour<15 ? 1 : 2));
     }

   long                ExportTimeframe(const ENUM_TIMEFRAMES tf,const long batch_id)
     {
      IDataProvider *db = m_store.Provider();
      const string symbol = m_set.symbol_name;
      const string stamp  = TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES);

      datetime start = m_store.LatestTimestamp(HIST_TABLE_BARS,"OpenTime",m_symbol_id);
      //--- LatestTimestamp is table-wide; refine per timeframe
      string rows[];
      if(db.Select(StringFormat(
            "SELECT MAX(OpenTime) FROM %s WHERE SymbolID=%d AND TimeframeID=%d",
            HIST_TABLE_BARS,m_symbol_id,(int)tf),rows)==1)
         start = (datetime)StringToInteger(rows[0]);
      if(start<=0)
         start = (datetime)(TimeCurrent()-3650*86400);

      long imported = 0, since_log = 0;
      const int tf_id = (int)tf;
      while(!IsStopped())
        {
         MqlRates rates[];
         const long page_seconds=(long)PeriodSeconds(tf)*(HIST_BAR_PAGE-1);
         datetime stop=(datetime)(start+page_seconds);
         const datetime now=TimeCurrent();
         if(stop>now)
            stop=now;
         const int got = CopyRates(symbol,tf,start,stop,rates);
         if(got<=0)
           {
            m_log.Warn(StringFormat("Bar CopyRates returned %d | %s | from %s | last_error=%d | synchronized=%d",
                                    got,EnumToString(tf),TimeToString(start,TIME_DATE|TIME_MINUTES),
                                    GetLastError(),(int)SeriesInfoInteger(symbol,tf,SERIES_SYNCHRONIZED)));
            break;
           }
         db.BeginTransaction();
         for(int i=0; i<got; i++)
           {
            int session = 0, weekday = 0, month = 0, quarter = 0;
            ClockOf(rates[i].time,session,weekday,month,quarter);
            const double spread = (double)rates[i].spread;
            const string sql = StringFormat(
               "INSERT OR IGNORE INTO %s (SymbolID,TimeframeID,OpenTime,Open,High,Low,Close,"
               "TickVolume,RealVolume,Spread,Session,Weekday,Month,Quarter,DST,BrokerOffset,"
               "DataSourceID,ImportBatchID,ImportedAt) "
               "VALUES (%d,%d,%d,%s,%s,%s,%s,%d,%d,%s,%d,%d,%d,%d,0,%d,%d,%d,'%s')",
               HIST_TABLE_BARS,m_symbol_id,tf_id,(int)rates[i].time,
               DoubleToString(rates[i].open,8),DoubleToString(rates[i].high,8),
               DoubleToString(rates[i].low,8),DoubleToString(rates[i].close,8),
               (int)rates[i].tick_volume,(int)rates[i].real_volume,
               DoubleToString(spread,2),session,weekday,month,quarter,
               m_broker_offset,m_source_id,(int)batch_id,stamp);
            if(db.Execute(sql))
              { imported++; since_log++; }
            if(rates[i].time+(datetime)PeriodSeconds(tf)>start)
               start = rates[i].time+(datetime)PeriodSeconds(tf);   // resume point
           }
         db.Commit();
         if(since_log>=m_progress_step)
           {
            m_log.Info(StringFormat("Bar export %s | +%d | total %d | at %s",
                                    EnumToString(tf),(int)since_log,(int)imported,
                                    TimeToString(start,TIME_DATE|TIME_MINUTES)));
            since_log = 0;
           }
         if(got<HIST_BAR_PAGE)
            break;
        }
      m_log.Info(StringFormat("Bar export finished | %s | %d rows",EnumToString(tf),(int)imported));
      return(imported);
     }

public:
                       CBarExporter(void) : m_set(NULL), m_log(NULL), m_store(NULL),
                          m_symbol_id(0), m_source_id(0), m_broker_offset(0),
                          m_progress_step(HIST_PROGRESS_BARS) {}

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

   void                SetProgressStep(const long bars) { if(bars>0) m_progress_step = bars; }

   //--- all seven timeframes (each resumes from its own stored maximum)
   long                ExportBars(const long batch_id)
     {
      if(m_store==NULL || !m_store.IsOpen())
         return(-1);
      m_symbol_id = m_store.SymbolId(m_set.symbol_name);
      if(m_symbol_id<=0 || !EnsureTable())
         return(-1);
      long total = 0;
      for(int i=0; i<7; i++)
        {
         const long imported = ExportTimeframe(HIST_TIMEFRAMES[i],batch_id);
         if(imported<0)
            return(-1);
         total += imported;
        }
      return(total);
     }

   //--- resume after interruption: identical path, resume points come from storage
   long                ResumeBars(const long batch_id) { return(ExportBars(batch_id)); }

   //--- TASK 5: incremental sync - same entry point; paged loops stop at the newest bar
   long                SynchronizeBars(const long batch_id) { return(ExportBars(batch_id)); }

   //--- TASK 4 (bar side): invalid OHLC / negative spread scan
   bool                ValidateBars(string &report)
     {
      report = "";
      if(m_store==NULL || !m_store.IsOpen())
         return(false);
      IDataProvider *db = m_store.Provider();
      string rows[];
      if(db.Select(StringFormat(
            "SELECT COUNT(*),"
            "SUM(CASE WHEN High<Low OR Open<Low OR Open>High OR Close<Low OR Close>High THEN 1 ELSE 0 END),"
            "SUM(CASE WHEN Spread<0 THEN 1 ELSE 0 END),"
            "SUM(CASE WHEN Open<=0 OR Close<=0 THEN 1 ELSE 0 END) FROM %s",HIST_TABLE_BARS),rows)!=1)
         return(false);
      string c[];
      if(StringSplit(rows[0],';',c)!=4)
         return(false);
      report = StringFormat("bars total=%s invalid_ohlc=%s negative_spread=%s invalid_price=%s",
                            c[0],c[1],c[2],c[3]);
      return(true);
     }
  };

#endif // __EA_HISTORY_BARS_MQH__
//+------------------------------------------------------------------+
