//+------------------------------------------------------------------+
//|                              EAData/SQLiteProvider.mqh           |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Data Access Layer: SQLite implementation  |
//+------------------------------------------------------------------+
#ifndef __EA_DAL_SQLITE_MQH__
#define __EA_DAL_SQLITE_MQH__

#include <CandleBreakoutEA\EAData\DatabaseTypes.mqh>
#include <CandleBreakoutEA\EAData\IDataProvider.mqh>
#include <CandleBreakoutEA\EAData\DatabaseValidation.mqh>
#include <CandleBreakoutEA\EAData\DatabaseSchema.mqh>
#include <CandleBreakoutEA\EAData\DatabaseVersion.mqh>

//+------------------------------------------------------------------+
//| Basic SQLite binding behind IDataProvider: open/close, schema    |
//| creation, version check, connection validation, transactions and |
//| generic statement helpers. No trade storage yet. Internal class -|
//| the rest of the project only sees CDatabaseManager.              |
//+------------------------------------------------------------------+
class CSQLiteProvider : public IDataProvider
  {
private:
   int                 m_db;
   string              m_file;
   bool                m_in_transaction;

public:
                       CSQLiteProvider(void) : m_db(0), m_in_transaction(false) {}
                      ~CSQLiteProvider(void) { Close(); }

   virtual bool        Initialize(const string file_name) override
     {
      if(!CDatabaseValidation::IsValidFileName(file_name))
         return(false);
      Close();
      m_file = file_name;
      return(true);
     }

   virtual bool        Open(void) override
     {
      if(m_db!=0)
         return(true);
      if(StringLen(m_file)==0)
         return(false);
      m_db = (int)DatabaseOpen(m_file,DATABASE_OPEN_CREATE|DATABASE_OPEN_READWRITE);
      if(m_db<=0)
        {
         m_db=0;
         PrintFormat("[CBEA DB] DatabaseOpen failed | file=%s | last_error=%d | terminal=%s | data_path=%s",
                     m_file,GetLastError(),TerminalInfoString(TERMINAL_PATH),
                     TerminalInfoString(TERMINAL_DATA_PATH));
         return(false);
        }
      if(!CDatabaseSchema::Create(m_db))
        {
         PrintFormat("[CBEA DB] schema create failed | file=%s | handle=%d | last_error=%d",
                     m_file,m_db,GetLastError());
         Close();
         return(false);
        }
      if(!CDatabaseVersion::EnsureVersion(m_db))
        {
         PrintFormat("[CBEA DB] schema migration/version failed | file=%s | handle=%d | version=%d | last_error=%d",
                     m_file,m_db,CDatabaseVersion::GetVersion(m_db),GetLastError());
         Close();
         return(false);
        }
      return(true);
     }

   virtual void        Close(void) override
     {
      if(m_db!=0)
        {
         if(m_in_transaction)
           {
            DatabaseTransactionRollback(m_db);
            m_in_transaction = false;
           }
         DatabaseClose(m_db);
         m_db = 0;
        }
     }

   virtual bool        IsOpen(void) const override { return(m_db!=0); }

   //--- provider-level identity metadata (not part of the interface)
   bool                WriteIdentity(const ulong magic,const string symbol)
     {
      return(CDatabaseSchema::WriteInfo(m_db,magic,symbol));
     }

   virtual bool        BeginTransaction(void) override
     {
      if(m_db==0 || m_in_transaction)
         return(false);
      m_in_transaction = DatabaseTransactionBegin(m_db);
      return(m_in_transaction);
     }

   virtual bool        Commit(void) override
     {
      if(m_db==0 || !m_in_transaction)
         return(false);
      m_in_transaction = false;
      return(DatabaseTransactionCommit(m_db));
     }

   virtual bool        Rollback(void) override
     {
      if(m_db==0 || !m_in_transaction)
         return(false);
      m_in_transaction = false;
      return(DatabaseTransactionRollback(m_db));
     }

   virtual bool        Execute(const string sql) override
     {
      if(m_db==0)
         return(false);
      return(DatabaseExecute(m_db,sql));
     }

   virtual int         Prepare(const string sql) override
     {
      if(m_db==0)
         return(0);
      return(DatabasePrepare(m_db,sql));
     }

   virtual int         Insert(const string sql) override { return(RowsAffected(sql)); }
   virtual int         Update(const string sql) override { return(RowsAffected(sql)); }
   virtual int         Delete(const string sql) override { return(RowsAffected(sql)); }

   virtual int         Select(const string sql,string &rows[]) override
     {
      ArrayResize(rows,0);
      if(m_db==0)
         return(-1);
      const int stmt = DatabasePrepare(m_db,sql);
      if(stmt==0)
         return(-1);
      const int cols = DatabaseColumnsCount(stmt);
      int count = 0;
      while(DatabaseRead(stmt))
        {
         string row = "";
         for(int c=0; c<cols; c++)
           {
            string text = "";
            DatabaseColumnText(stmt,c,text);
            if(c>0)
               row += ";";
            row += text;
           }
         const int idx = ArraySize(rows);
         ArrayResize(rows,idx+1);
         rows[idx] = row;
         count++;
        }
      DatabaseFinalize(stmt);
      return(count);
     }

   //--- export every metadata table to the given folder as CSV
   virtual bool        Backup(const string path) override
     {
      if(m_db==0)
         return(false);
      const string tables[] = {DB_TABLE_INFO,DB_TABLE_VERSION,DB_TABLE_MIGRATION};
      for(int i=0; i<ArraySize(tables); i++)
         if(!DatabaseExport(m_db,tables[i],path+"\\"+tables[i]+".csv",0,";"))
            return(false);
      return(true);
     }

   //--- rebuild metadata tables from previously exported CSV files
   virtual bool        Restore(const string path) override
     {
      if(!Open())
         return(false);
      const string tables[] = {DB_TABLE_INFO,DB_TABLE_VERSION,DB_TABLE_MIGRATION};
      if(!BeginTransaction())
         return(false);
      for(int i=0; i<ArraySize(tables); i++)
        {
         if(!Execute(StringFormat("DELETE FROM %s",tables[i])))
           {
            Rollback();
            return(false);
           }
         if(DatabaseImport(m_db,tables[i],path+"\\"+tables[i]+".csv",
                           DATABASE_IMPORT_HEADER|DATABASE_IMPORT_APPEND,";",0,"")<0)
           {
            Rollback();
            return(false);
           }
        }
      return(Commit());
     }

   virtual ENUM_DB_STATUS Validate(void) override
     {
      if(m_db==0)
         return(DB_ERR_CONNECTION);
      const ENUM_DB_STATUS schema = CDatabaseValidation::ValidateSchema(m_db);
      if(schema!=DB_OK)
         return(schema);
      const int version = CDatabaseVersion::GetVersion(m_db);
      if(!CDatabaseValidation::IsSupportedVersion(version))
         return(DB_ERR_VERSION);
      if(!CDatabaseValidation::AreTransactionsAvailable(m_db))
         return(DB_ERR_TRANSACTION);
      return(DB_OK);
     }

private:
   int                 RowsAffected(const string sql)
     {
      if(m_db==0)
         return(-1);
      if(!DatabaseExecute(m_db,sql))
         return(-1);
      //--- this build has no DatabaseRowsAffected(); SQLite's changes() is the source
      const int stmt = DatabasePrepare(m_db,"SELECT changes()");
      if(stmt==0)
         return(-1);
      long rows = 0;
      if(DatabaseRead(stmt))
         DatabaseColumnLong(stmt,0,rows);
      DatabaseFinalize(stmt);
      return((int)rows);
     }
  };

#endif // __EA_DAL_SQLITE_MQH__
//+------------------------------------------------------------------+
