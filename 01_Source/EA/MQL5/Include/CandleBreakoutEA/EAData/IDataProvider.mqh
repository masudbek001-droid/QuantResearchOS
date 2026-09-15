//+------------------------------------------------------------------+
//|                              EAData/IDataProvider.mqh            |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Data Access Layer: pure interface         |
//+------------------------------------------------------------------+
#ifndef __EA_DAL_IPROVIDER_MQH__
#define __EA_DAL_IPROVIDER_MQH__

#include <CandleBreakoutEA\EAData\DatabaseTypes.mqh>

//+------------------------------------------------------------------+
//| Pure persistence interface. No module outside EAData/ may ever   |
//| talk to SQLite directly - everything goes through this contract  |
//| and the DatabaseManager facade on top of it.                     |
//+------------------------------------------------------------------+
class IDataProvider
  {
public:
   //--- lifecycle
   virtual bool                Initialize(const string file_name)=0;
   virtual bool                Open(void)=0;
   virtual void                Close(void)=0;
   virtual bool                IsOpen(void) const=0;

   //--- transactions
   virtual bool                BeginTransaction(void)=0;
   virtual bool                Commit(void)=0;
   virtual bool                Rollback(void)=0;

   //--- statements
   virtual bool                Execute(const string sql)=0;
   virtual int                 Prepare(const string sql)=0;   // statement handle, 0 = error
   virtual int                 Insert(const string sql)=0;   // affected rows, -1 = error
   virtual int                 Update(const string sql)=0;   // affected rows, -1 = error
   virtual int                 Delete(const string sql)=0;   // affected rows, -1 = error
   virtual int                 Select(const string sql,string &rows[])=0; // row count, -1 = error

   //--- maintenance
   virtual bool                Backup(const string path)=0;
   virtual bool                Restore(const string path)=0;
   virtual ENUM_DB_STATUS      Validate(void)=0;
  };

#endif // __EA_DAL_IPROVIDER_MQH__
//+------------------------------------------------------------------+
