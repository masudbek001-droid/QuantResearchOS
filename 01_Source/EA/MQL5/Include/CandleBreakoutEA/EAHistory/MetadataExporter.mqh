//+------------------------------------------------------------------+
//|                           EAHistory/MetadataExporter.mqh         |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Historical Data Platform: metadata (T3)   |
//+------------------------------------------------------------------+
#ifndef __EA_HISTORY_METADATA_MQH__
#define __EA_HISTORY_METADATA_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EAUtils.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAHistory\HistoryTypes.mqh>
#include <CandleBreakoutEA\EAHistory\HistoryStore.mqh>

//+------------------------------------------------------------------+
//| TASK 3: market metadata snapshot. Symbol specification, broker   |
//| offset, DST, spread, trading sessions - stored as key/value rows |
//| per store so every archive carries the context it was taken in.  |
//+------------------------------------------------------------------+
#define HIST_TABLE_METADATA "MarketMetadata"

class CMetadataExporter
  {
private:
   const CEASettings  *m_set;
   CLogger            *m_log;
   CHistoryStore      *m_store;
   int                 m_source_id;

   bool                Put(const int symbol_id,const string key,const string value)
     {
      const string stamp = TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES);
      return(m_store.Provider().Execute(StringFormat(
                "INSERT INTO %s (SymbolID,MetaKey,MetaValue,DataSourceID,UpdatedAt) "
                "VALUES (%d,'%s','%s',%d,'%s') "
                "ON CONFLICT(SymbolID,MetaKey) DO UPDATE SET MetaValue=excluded.MetaValue,"
                "DataSourceID=excluded.DataSourceID,UpdatedAt=excluded.UpdatedAt",
                HIST_TABLE_METADATA,symbol_id,key,value,m_source_id,stamp)));
     }

   //--- trading hours of one weekday as "from-to" minutes, "" when closed
   string              SessionOf(const string symbol,const int weekday)
     {
      datetime from = 0, to = 0;
      if(!SymbolInfoSessionTrade(symbol,(ENUM_DAY_OF_WEEK)weekday,0,from,to))
         return("");
      MqlDateTime fs, ts;
      TimeToStruct(from,fs);
      TimeToStruct(to,ts);
      return(StringFormat("%02d:%02d-%02d:%02d",fs.hour,fs.min,ts.hour,ts.min));
     }

public:
                       CMetadataExporter(void) : m_set(NULL), m_log(NULL), m_store(NULL),
                          m_source_id(0) {}

   void                Initialize(const CEASettings &settings,CLogger &logger,
                                  CHistoryStore &store,const int source_id)
     {
      m_set       = &settings;
      m_log       = &logger;
      m_store     = &store;
      m_source_id = source_id;
     }

   bool                ExportMetadata(void)
     {
      if(m_store==NULL || !m_store.IsOpen() || m_set==NULL)
         return(false);
      IDataProvider *db = m_store.Provider();
      if(!db.Execute(StringFormat(
            "CREATE TABLE IF NOT EXISTS %s ("
            "MetaID INTEGER PRIMARY KEY AUTOINCREMENT,"
            "SymbolID INTEGER NOT NULL,"
            "MetaKey TEXT NOT NULL,"
            "MetaValue TEXT NOT NULL,"
            "DataSourceID INTEGER,"
            "UpdatedAt TEXT NOT NULL,"
            "UNIQUE(SymbolID,MetaKey))",HIST_TABLE_METADATA)))
         return(false);

      const string symbol = m_set.symbol_name;
      const int symbol_id = m_store.SymbolId(symbol);
      if(symbol_id<=0)
         return(false);

      const int    digits   = (int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
      const double point    = CEAUtils::PointValue(symbol);
      const double spread   = CEAUtils::SpreadPoints(symbol);
      const int    offset   = (int)MathRound((double)(TimeCurrent()-TimeGMT())/3600.0);
      MqlDateTime now;
      TimeToStruct(TimeCurrent(),now);

      bool ok = true;
      ok = ok && Put(symbol_id,"Digits",IntegerToString(digits));
      ok = ok && Put(symbol_id,"Point",DoubleToString(point,digits));
      ok = ok && Put(symbol_id,"TickSize",DoubleToString(SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE),digits));
      ok = ok && Put(symbol_id,"TickValue",DoubleToString(SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE),8));
      ok = ok && Put(symbol_id,"ContractSize",DoubleToString(SymbolInfoDouble(symbol,SYMBOL_TRADE_CONTRACT_SIZE),8));
      ok = ok && Put(symbol_id,"SpreadPoints",DoubleToString(spread,2));
      ok = ok && Put(symbol_id,"BrokerOffsetHours",IntegerToString(offset));
      //--- DST heuristic: server-vs-GMT offset differs from the winter baseline
      ok = ok && Put(symbol_id,"DSTActive",(offset!=0 && (now.mon>=4 && now.mon<=9) ? "1" : "0"));
      ok = ok && Put(symbol_id,"BaseCurrency",SymbolInfoString(symbol,SYMBOL_CURRENCY_BASE));
      ok = ok && Put(symbol_id,"QuoteCurrency",SymbolInfoString(symbol,SYMBOL_CURRENCY_PROFIT));
      ok = ok && Put(symbol_id,"TradeMode",IntegerToString((int)SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE)));
      for(int wd=1; wd<=5; wd++)
         ok = ok && Put(symbol_id,StringFormat("Session%d",wd),SessionOf(symbol,wd));

      if(ok)
         m_log.Info(StringFormat("Metadata exported | %s | digits %d | offset %+d h | spread %.0f pts",
                                 symbol,digits,offset,spread));
      else
         m_log.Warn("Metadata export incomplete");
      return(ok);
     }
  };

#endif // __EA_HISTORY_METADATA_MQH__
//+------------------------------------------------------------------+
