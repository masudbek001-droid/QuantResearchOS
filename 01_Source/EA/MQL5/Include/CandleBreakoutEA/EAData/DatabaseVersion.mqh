//+------------------------------------------------------------------+
//|                              EAData/DatabaseVersion.mqh          |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Data Access Layer: schema versioning      |
//+------------------------------------------------------------------+
#ifndef __EA_DAL_VERSION_MQH__
#define __EA_DAL_VERSION_MQH__

#include <CandleBreakoutEA\EAData\DatabaseTypes.mqh>
#include <CandleBreakoutEA\EAData\DatabaseValidation.mqh>
#include <CandleBreakoutEA\EAData\DatabaseSchema.mqh>

//+------------------------------------------------------------------+
//| Schema version bookkeeping. v1 = metadata only; every future     |
//| version must be recorded through ApplyMigration().               |
//+------------------------------------------------------------------+
class CDatabaseVersion
  {
public:
   //--- highest recorded version, -1 when unreadable
   static int          GetVersion(const int db)
     {
      if(db==0 || !DatabaseTableExists(db,DB_TABLE_VERSION))
         return(-1);
      const int stmt = DatabasePrepare(db,
         StringFormat("SELECT MAX(version) FROM %s",DB_TABLE_VERSION));
      if(stmt==0)
         return(-1);
      long version = -1;
      if(DatabaseRead(stmt))
        {
         long value = -1;
         if(DatabaseColumnLong(stmt,0,value))
            version = value;
        }
      DatabaseFinalize(stmt);
      return((int)version);
     }

   //--- bring any supported file up to DB_SCHEMA_VERSION.
   //--- brand-new files are stamped v1 first, then migrated like everyone else,
   //--- so the version history of every database looks identical.
   static bool         EnsureVersion(const int db)
     {
      int version = GetVersion(db);
      // A legacy/partially-created file can contain the metadata table while
      // having no valid version row; treat version 0 exactly like a fresh v1
      // database so the additive migration chain can bootstrap deterministically.
      if(version<=0)
        {
         const string sql = StringFormat(
            "INSERT INTO %s (version,applied_at) VALUES (1,'%s')",
            DB_TABLE_VERSION,
            TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES));
         if(!DatabaseExecute(db,sql))
            return(false);
         version = 1;
        }
      if(version==DB_SCHEMA_VERSION)
         return(true);
      if(version==1)
        {
         string ddl[];
         CDatabaseSchema::MigrationToV2(ddl);
         if(!ApplyMigration(db,1,2,"market intelligence phase 1",ddl))
            return(false);
         version = 2;
        }
      if(version==2)
        {
         string ddl[];
         CDatabaseSchema::MigrationToV3(ddl);
         if(!ApplyMigration(db,2,3,"trade intelligence phase 1",ddl))
            return(false);
         version = 3;
        }
      if(version==3)
        {
         string ddl[];
         CDatabaseSchema::MigrationToV4(ddl);
         if(!ApplyMigration(db,3,4,"observation engine",ddl))
            return(false);
         version = 4;
        }
      if(version==4)
        {
         string ddl[];
         CDatabaseSchema::MigrationToV5(ddl);
         if(!ApplyMigration(db,4,5,"label engine foundation",ddl))
            return(false);
         version = 5;
        }
      if(version==5)
        {
         string ddl[];
         CDatabaseSchema::MigrationToV6(ddl);
         if(!ApplyMigration(db,5,6,"research dataset builder",ddl))
            return(false);
         version = 6;
        }
      if(version==6)
        {
         string ddl[];
         CDatabaseSchema::MigrationToV7(ddl);
         if(!ApplyMigration(db,6,7,"research data quality engine",ddl))
            return(false);
         version = 7;
        }
      if(version==7)
        {
         string ddl[];
         CDatabaseSchema::MigrationToV8(ddl);
         if(!ApplyMigration(db,7,8,"feature registry",ddl))
            return(false);
         version = 8;
        }
      if(version==8)
        {
         string ddl[];
         CDatabaseSchema::MigrationToV9(ddl);
         if(!ApplyMigration(db,8,9,"replay foundation",ddl))
            return(false);
         version = 9;
        }
      if(version==9)
        {
         string ddl[];
         CDatabaseSchema::MigrationToV10(ddl);
         if(!ApplyMigration(db,9,10,"research platform",ddl))
            return(false);
         version = 10;
        }
      if(version==10)
        {
         string ddl[];
         CDatabaseSchema::MigrationToV11(ddl);
         return(ApplyMigration(db,10,11,"historical data platform masters",ddl));
        }
      return(false);   // unsupported versions are never auto-migrated
     }

   //--- single funnel for future schema migrations (recorded in history)
   static bool         ApplyMigration(const int db,const int from_version,
                                      const int to_version,const string description,
                                      const string &ddl[])
     {
      if(db==0 || GetVersion(db)!=from_version)
         return(false);
      if(!CDatabaseValidation::IsSupportedVersion(to_version))
         return(false);
      if(!DatabaseTransactionBegin(db))
         return(false);
      for(int i=0; i<ArraySize(ddl); i++)
         if(!DatabaseExecute(db,ddl[i]))
           {
            DatabaseTransactionRollback(db);
            return(false);
           }
      const string stamp = TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES);
      const string mark = StringFormat(
         "INSERT INTO %s (version,applied_at) VALUES (%d,'%s')",
         DB_TABLE_VERSION,to_version,stamp);
      const string history = StringFormat(
         "INSERT INTO %s (from_version,to_version,description,applied_at) VALUES (%d,%d,'%s','%s')",
         DB_TABLE_MIGRATION,from_version,to_version,description,stamp);
      if(!DatabaseExecute(db,mark) || !DatabaseExecute(db,history))
        {
         DatabaseTransactionRollback(db);
         return(false);
        }
      return(DatabaseTransactionCommit(db));
     }
  };

#endif // __EA_DAL_VERSION_MQH__
//+------------------------------------------------------------------+
