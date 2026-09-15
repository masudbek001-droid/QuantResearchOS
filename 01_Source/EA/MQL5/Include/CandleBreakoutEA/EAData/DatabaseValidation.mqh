//+------------------------------------------------------------------+
//|                            EAData/DatabaseValidation.mqh         |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Data Access Layer: validation rules       |
//+------------------------------------------------------------------+
#ifndef __EA_DAL_VALIDATION_MQH__
#define __EA_DAL_VALIDATION_MQH__

#include <CandleBreakoutEA\EAData\DatabaseTypes.mqh>

//+------------------------------------------------------------------+
//| Stateless checks used by the provider and the manager. No I/O    |
//| beyond probing table existence through the MT5 Database API.     |
//+------------------------------------------------------------------+
class CDatabaseValidation
  {
public:
   //--- file name sanity: non-empty, .db suffix, no control characters
   static bool         IsValidFileName(const string file_name)
     {
      if(StringLen(file_name)==0)
         return(false);
      if(StringFind(file_name,DB_FILE_EXT,StringLen(file_name)-StringLen(DB_FILE_EXT))<0)
         return(false);
      for(int i=0; i<StringLen(file_name); i++)
        {
         const ushort ch = StringGetCharacter(file_name,i);
         if(ch<32 || ch=='"' || ch=='\'' || ch==';')
            return(false);
        }
      return(true);
     }

   //--- the DAL only supports versions 1..DB_SCHEMA_VERSION
   static bool         IsSupportedVersion(const int version)
     {
      return(version>=1 && version<=DB_SCHEMA_VERSION);
     }

   //--- schema health: the three metadata tables must exist
   static ENUM_DB_STATUS ValidateSchema(const int db)
     {
      if(db==0)
         return(DB_ERR_CONNECTION);
      if(!DatabaseTableExists(db,DB_TABLE_INFO))
         return(DB_ERR_SCHEMA);
      if(!DatabaseTableExists(db,DB_TABLE_VERSION))
         return(DB_ERR_SCHEMA);
      if(!DatabaseTableExists(db,DB_TABLE_MIGRATION))
         return(DB_ERR_SCHEMA);
      return(DB_OK);
     }

   //--- transaction probe: begin+rollback must both succeed
   static bool         AreTransactionsAvailable(const int db)
     {
      if(db==0)
         return(false);
      if(!DatabaseTransactionBegin(db))
         return(false);
      return(DatabaseTransactionRollback(db));
     }
  };

#endif // __EA_DAL_VALIDATION_MQH__
//+------------------------------------------------------------------+
