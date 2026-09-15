//+------------------------------------------------------------------+
//|                            EAData/DatabaseManager.mqh            |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Data Access Layer: the ONLY public class  |
//+------------------------------------------------------------------+
#ifndef __EA_DAL_MANAGER_MQH__
#define __EA_DAL_MANAGER_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAData\DatabaseTypes.mqh>
#include <CandleBreakoutEA\EAData\IDataProvider.mqh>
#include <CandleBreakoutEA\EAData\SQLiteProvider.mqh>

//+------------------------------------------------------------------+
//| Facade over IDataProvider. Every future persistence consumer     |
//| (trade journal, statistics, replay, AI store) talks to THIS      |
//| class and nothing else; SQLite stays isolated behind the         |
//| interface. Foundation only: no business logic, no trade tables.  |
//+------------------------------------------------------------------+
class CDatabaseManager
  {
private:
   IDataProvider      *m_provider;
   CSQLiteProvider    *m_sqlite;    // same object, provider-specific extras
   const CEASettings  *m_set;
   CLogger            *m_log;
   ENUM_DB_STATUS      m_status;

public:
                       CDatabaseManager(void) : m_provider(NULL), m_sqlite(NULL), m_set(NULL), m_log(NULL),
                                                m_status(DB_ERR_CONNECTION) {}
                      ~CDatabaseManager(void)
                        {
                         Close();
                         if(m_sqlite!=NULL)
                           {
                            delete m_sqlite;
                            m_sqlite=NULL;
                            m_provider=NULL;
                           }
                        }

   void                Initialize(const CEASettings &settings,CLogger &logger)
     {
      m_set = &settings;
      m_log = &logger;
      if(m_provider==NULL)
        {
         m_sqlite   = new CSQLiteProvider();
         m_provider = m_sqlite;
        }
      const string file = DB_FILE_PREFIX+IntegerToString(m_set.magic)+DB_FILE_EXT;
      if(!m_provider.Initialize(file))
        {
         m_status = DB_ERR_VALIDATION;
         m_log.Warn(StringFormat("Database rejected file name | %s",file));
         return;
        }
      m_status = DB_OK;
      m_log.Info(StringFormat("Database Manager initialized | %s | schema v%d",
                              file,DB_SCHEMA_VERSION));
     }

   //--- open + stamp identity; failures never touch trading
   bool                Open(void)
     {
      if(m_provider==NULL)
         return(false);
      if(m_provider.IsOpen())
         return(true);
      if(!m_provider.Open())
        {
         m_status = DB_ERR_OPEN;
         m_log.Warn(StringFormat("Database open failed | %s",DbStatusToString(m_status)));
         return(false);
        }
      if(m_sqlite!=NULL && !m_sqlite.WriteIdentity(m_set.magic,m_set.symbol_name))
         m_log.Warn("Database identity stamp failed");
      m_status = m_provider.Validate();
      if(m_status!=DB_OK)
        {
         m_log.Warn(StringFormat("Database validation failed | %s",DbStatusToString(m_status)));
         m_provider.Close();
         return(false);
        }
      m_log.Info(StringFormat("Database ready | schema v%d | %s",
                              DB_SCHEMA_VERSION,DbStatusToString(m_status)));
      return(true);
     }

   void                Close(void)
     {
      if(m_provider!=NULL)
         m_provider.Close();
     }

   bool                IsOpen(void) const
     {
      return(m_provider!=NULL && m_provider.IsOpen());
     }

   ENUM_DB_STATUS      LastStatus(void) const { return(m_status); }

   //--- pass-through persistence API (the whole project sees only this)
   bool                BeginTransaction(void) const { return(m_provider!=NULL && m_provider.BeginTransaction()); }
   bool                Commit(void) const           { return(m_provider!=NULL && m_provider.Commit()); }
   bool                Rollback(void) const         { return(m_provider!=NULL && m_provider.Rollback()); }
   bool                Execute(const string sql) const { return(m_provider!=NULL && m_provider.Execute(sql)); }
   int                 Prepare(const string sql) const { return(m_provider!=NULL ? m_provider.Prepare(sql) : 0); }
   int                 Insert(const string sql) const  { return(m_provider!=NULL ? m_provider.Insert(sql) : -1); }
   int                 Update(const string sql) const  { return(m_provider!=NULL ? m_provider.Update(sql) : -1); }
   int                 Delete(const string sql) const  { return(m_provider!=NULL ? m_provider.Delete(sql) : -1); }
   int                 Select(const string sql,string &rows[]) const
     {
      return(m_provider!=NULL ? m_provider.Select(sql,rows) : -1);
     }
   bool                Backup(const string path) const  { return(m_provider!=NULL && m_provider.Backup(path)); }
   bool                Restore(const string path) const { return(m_provider!=NULL && m_provider.Restore(path)); }
   ENUM_DB_STATUS      Validate(void)
     {
      m_status = (m_provider!=NULL ? m_provider.Validate() : DB_ERR_CONNECTION);
      return(m_status);
     }

   string              ToString(void) const
     {
      return(StringFormat("database: %s | schema v%d",
                          (IsOpen() ? "open" : "closed"),DB_SCHEMA_VERSION));
     }
  };

#endif // __EA_DAL_MANAGER_MQH__
//+------------------------------------------------------------------+
