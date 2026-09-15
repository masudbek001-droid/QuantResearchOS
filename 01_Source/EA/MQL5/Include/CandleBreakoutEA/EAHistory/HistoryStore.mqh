//+------------------------------------------------------------------+
//|                              EAHistory/HistoryStore.mqh          |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Historical Data Platform: dedicated store |
//+------------------------------------------------------------------+
#ifndef __EA_HISTORY_STORE_MQH__
#define __EA_HISTORY_STORE_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EAUtils.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAData\DatabaseTypes.mqh>
#include <CandleBreakoutEA\EAData\SQLiteProvider.mqh>
#include <CandleBreakoutEA\EAHistory\HistoryTypes.mqh>

//+------------------------------------------------------------------+
//| One dedicated .db file behind the DAL provider (IDataProvider).  |
//| Owns its local Symbols/Timeframes masters (SQLite cannot share   |
//| FKs across files) and the platform-specific tables.              |
//+------------------------------------------------------------------+
class CHistoryStore
  {
private:
   CSQLiteProvider     m_provider;
   CLogger            *m_log;
   string              m_file;
   string              m_db_name;
   bool                m_ready;

   bool                EnsureSymbolColumns(void)
     {
      string rows[];
      if(m_provider.Select(StringFormat("PRAGMA table_info(%s)",HIST_TABLE_SYMBOLS),rows)<0)
         return(false);
      bool tick_value=false,base=false,quote=false,active=false;
      for(int i=0; i<ArraySize(rows); i++)
        {
         string c[];
         if(StringSplit(rows[i],';',c)>=2)
           {
            if(c[1]=="TickValue")     tick_value=true;
            if(c[1]=="BaseCurrency")  base=true;
            if(c[1]=="QuoteCurrency") quote=true;
            if(c[1]=="Active")        active=true;
           }
        }
      if(!tick_value && !m_provider.Execute(StringFormat(
            "ALTER TABLE %s ADD COLUMN TickValue REAL NOT NULL DEFAULT 0",HIST_TABLE_SYMBOLS)))
         return(false);
      if(!base && !m_provider.Execute(StringFormat(
            "ALTER TABLE %s ADD COLUMN BaseCurrency TEXT",HIST_TABLE_SYMBOLS)))
         return(false);
      if(!quote && !m_provider.Execute(StringFormat(
            "ALTER TABLE %s ADD COLUMN QuoteCurrency TEXT",HIST_TABLE_SYMBOLS)))
         return(false);
      if(!active && !m_provider.Execute(StringFormat(
            "ALTER TABLE %s ADD COLUMN Active INTEGER NOT NULL DEFAULT 1",HIST_TABLE_SYMBOLS)))
         return(false);
      return(true);
     }

public:
                       CHistoryStore(void) : m_log(NULL), m_ready(false) {}
                      ~CHistoryStore(void) { Close(); }

   bool                Open(const string file,CLogger &logger)
     {
      m_log  = &logger;
      m_file = file;
      //--- derive a short name ("Ticks.db") for logs and import rows
      const int slash = StringFind(m_file,"\\");
      m_db_name = (slash>=0 ? StringSubstr(m_file,slash+1) : m_file);
      if(!m_provider.Initialize(m_file))
        {
         m_log.Warn(StringFormat("History store rejected | %s",m_file));
         return(false);
        }
      if(!m_provider.Open())
        {
         m_log.Warn(StringFormat("History store open failed | %s",m_file));
         return(false);
        }
      if(!EnsureMasters())
        {
         m_provider.Close();
         return(false);
        }
      m_ready = true;
      m_log.Info(StringFormat("History store ready | %s",m_db_name));
      return(true);
     }

   void                Close(void)
     {
      m_provider.Close();
      m_ready = false;
     }

   bool                IsOpen(void) const { return(m_ready && m_provider.IsOpen()); }
   string              Name(void)   const { return(m_db_name); }
   IDataProvider      *Provider(void) { return(&m_provider); }

   //--- master tables + the seven timeframes (idempotent)
   bool                EnsureMasters(void)
     {
      const string ddl[] =
        {
         StringFormat("CREATE TABLE IF NOT EXISTS %s ("
            "SymbolID INTEGER PRIMARY KEY AUTOINCREMENT,"
            "Symbol TEXT NOT NULL UNIQUE,"
            "Digits INTEGER NOT NULL,"
            "Point REAL NOT NULL,"
            "TickSize REAL NOT NULL,"
            "TickValue REAL NOT NULL DEFAULT 0,"
            "ContractSize REAL NOT NULL,"
            "BaseCurrency TEXT,"
            "QuoteCurrency TEXT,"
            "Active INTEGER NOT NULL DEFAULT 1)",HIST_TABLE_SYMBOLS),
         StringFormat("CREATE TABLE IF NOT EXISTS %s ("
            "TimeframeID INTEGER PRIMARY KEY,"
            "Name TEXT NOT NULL UNIQUE,"
            "Minutes INTEGER NOT NULL)",HIST_TABLE_TFS)
        };
      for(int i=0; i<ArraySize(ddl); i++)
         if(!m_provider.Execute(ddl[i]))
           {
            m_log.Warn(StringFormat("Master DDL failed | %s",m_db_name));
           return(false);
           }
      if(!EnsureSymbolColumns())
        {
         m_log.Warn(StringFormat("Symbol master migration failed | %s",m_db_name));
         return(false);
        }
      //--- remove pre-v11 minute-based timeframe IDs; MQL5 enum IDs are authoritative
      if(!m_provider.Execute(StringFormat("DELETE FROM %s WHERE TimeframeID IN (60,240,1440)",
                                          HIST_TABLE_TFS)))
         return(false);
      for(int i=0; i<7; i++)
        {
         const ENUM_TIMEFRAMES tf = HIST_TIMEFRAMES[i];
         const string sql = StringFormat(
            "INSERT OR IGNORE INTO %s (TimeframeID,Name,Minutes) VALUES (%d,'%s',%d)",
            HIST_TABLE_TFS,(int)tf,EnumToString(tf),(int)(PeriodSeconds(tf)/60));
         if(!m_provider.Execute(sql))
            return(false);
        }
      return(true);
     }

   //--- register/read the symbol master row, return its id (0 = failure)
   int                 SymbolId(const string symbol)
     {
      string existing_rows[];
      const int existing_count=m_provider.Select(StringFormat(
         "SELECT SymbolID FROM %s WHERE Symbol='%s'",HIST_TABLE_SYMBOLS,symbol),existing_rows);
      if(existing_count==1)
         return((int)StringToInteger(existing_rows[0]));

      const int    digits   = (int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
      const double point    = CEAUtils::PointValue(symbol);
      const double tick_sz  = SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
      const double contract = SymbolInfoDouble(symbol,SYMBOL_TRADE_CONTRACT_SIZE);
      const string base     = SymbolInfoString(symbol,SYMBOL_CURRENCY_BASE);
      const string quote    = SymbolInfoString(symbol,SYMBOL_CURRENCY_PROFIT);
      const string ins = StringFormat(
         "INSERT INTO %s (Symbol,Digits,Point,TickSize,TickValue,ContractSize,"
         "CreatedAt,BaseCurrency,QuoteCurrency,Active) VALUES ('%s',%d,%s,%s,%s,%s,'%s','%s','%s',1)",
         HIST_TABLE_SYMBOLS,symbol,digits,DoubleToString(point,digits),
         DoubleToString(tick_sz,digits),
         DoubleToString(SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE),8),
         DoubleToString(contract,8),TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES),base,quote);
      PrintFormat("[CBEA HISTORY] symbol insert | db=%s | sql=%s",m_db_name,ins);
      if(!m_provider.Execute(ins))
        {
         m_log.Warn(StringFormat("Symbol master insert failed | %s | symbol=%s",m_db_name,symbol));
         return(0);
        }
      string rows[];
      const int selected=m_provider.Select(StringFormat("SELECT SymbolID FROM %s WHERE Symbol='%s'",
                                                        HIST_TABLE_SYMBOLS,symbol),rows);
      PrintFormat("[CBEA HISTORY] symbol select | db=%s | rows=%d | total=%d",
                  m_db_name,selected,ArraySize(rows));
      if(selected!=1)
        {
         m_log.Warn(StringFormat("Symbol master select failed | %s | symbol=%s",m_db_name,symbol));
         return(0);
        }
      return((int)StringToInteger(rows[0]));
     }

   //--- resume support: the newest stored moment of a table column
   datetime            LatestTimestamp(const string table,const string column,const int symbol_id)
     {
      string rows[];
      if(m_provider.Select(StringFormat(
            "SELECT MAX(%s) FROM %s WHERE SymbolID=%d",column,table,symbol_id),rows)!=1)
         return(0);
      return((datetime)StringToInteger(rows[0]));
     }

   long                CountRows(const string table)
     {
      string rows[];
      if(m_provider.Select(StringFormat("SELECT COUNT(*) FROM %s",table),rows)!=1)
         return(-1);
      return(StringToInteger(rows[0]));
     }

   //--- database file size in bytes (0 when unavailable)
   long                FileSizeBytes(void) const
     {
      const int handle = FileOpen(m_file,FILE_READ|FILE_BIN);
      if(handle==INVALID_HANDLE)
         return(0);
      const long size = (long)FileSize(handle);
      FileClose(handle);
      return(size);
     }
  };

#endif // __EA_HISTORY_STORE_MQH__
//+------------------------------------------------------------------+
