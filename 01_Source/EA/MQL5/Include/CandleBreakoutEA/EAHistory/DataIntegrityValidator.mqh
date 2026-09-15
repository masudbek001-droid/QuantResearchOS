//+------------------------------------------------------------------+
//|                        EAHistory/DataIntegrityValidator.mqh      |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Historical Data Platform: integrity (T4)  |
//+------------------------------------------------------------------+
#ifndef __EA_HISTORY_INTEGRITY_MQH__
#define __EA_HISTORY_INTEGRITY_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAHistory\HistoryTypes.mqh>
#include <CandleBreakoutEA\EAHistory\HistoryStore.mqh>

//+------------------------------------------------------------------+
//| TASK 4: integrity of both archives. All checks are aggregate     |
//| SQL scans; the validator writes nothing. Weekend gaps are        |
//| counted and reported, never treated as errors.                   |
//+------------------------------------------------------------------+
class CDataIntegrityValidator
  {
private:
   CLogger            *m_log;

   long                Scalar(CHistoryStore &store,const string sql)
     {
      string rows[];
      if(store.Provider().Select(sql,rows)!=1)
         return(-1);
      return(StringToInteger(rows[0]));
     }

public:
                       CDataIntegrityValidator(void) : m_log(NULL) {}

   void                Initialize(CLogger &logger) { m_log = &logger; }

   //--- Ticks.db: duplicates + invalid values
   bool                ValidateTicks(CHistoryStore &ticks,string &report)
     {
      report = "";
      if(!ticks.IsOpen())
         return(false);
      const long total     = Scalar(ticks,StringFormat("SELECT COUNT(*) FROM %s",HIST_TABLE_TICKS));
      const long distinct  = Scalar(ticks,StringFormat(
         "SELECT COUNT(*) FROM (SELECT DISTINCT SymbolID,BrokerTime,Milliseconds,Bid,Ask FROM %s)",
         HIST_TABLE_TICKS));
      const long invalid   = Scalar(ticks,StringFormat(
         "SELECT COUNT(*) FROM %s WHERE Bid<=0 OR Ask<=0 OR Spread<0",HIST_TABLE_TICKS));
      const long unordered = Scalar(ticks,StringFormat(
         "SELECT COUNT(*) FROM %s t1 JOIN %s t2 ON t2.TickID=t1.TickID+1 "
         "AND t2.SymbolID=t1.SymbolID WHERE t2.BrokerTime<t1.BrokerTime",
         HIST_TABLE_TICKS,HIST_TABLE_TICKS));
      if(total<0 || distinct<0 || invalid<0 || unordered<0)
         return(false);
      report = StringFormat("ticks: total=%d duplicates=%d invalid=%d out_of_order=%d",
                            (int)total,(int)(total-distinct),(int)invalid,(int)unordered);
      return(total-distinct==0 && invalid==0 && unordered==0);
     }

   //--- Market.db: per-timeframe continuity, weekend-aware
   bool                ValidateBars(CHistoryStore &market,string &report)
     {
      report = "";
      if(!market.IsOpen())
         return(false);
      bool clean = true;
      for(int i=0; i<7; i++)
        {
         const ENUM_TIMEFRAMES tf = HIST_TIMEFRAMES[i];
         const string where = StringFormat("WHERE TimeframeID=%d",(int)tf);
         const long total = Scalar(market,StringFormat(
            "SELECT COUNT(*) FROM %s %s",HIST_TABLE_BARS,where));
         if(total<=0)
            continue;   // timeframe not exported yet
         const long distinct = Scalar(market,StringFormat(
            "SELECT COUNT(*) FROM (SELECT DISTINCT SymbolID,OpenTime FROM %s %s)",
            HIST_TABLE_BARS,where));
         const long invalid = Scalar(market,StringFormat(
            "SELECT COUNT(*) FROM %s %s AND (High<Low OR Open<Low OR Open>High "
            "OR Close<Low OR Close>High OR Spread<0 OR Open<=0)",
            HIST_TABLE_BARS,where));

         string rows[];
         long missing = -1;
         if(market.Provider().Select(StringFormat(
               "SELECT MIN(OpenTime),MAX(OpenTime) FROM %s %s",HIST_TABLE_BARS,where),rows)==1)
           {
            string c[];
            if(StringSplit(rows[0],';',c)==2)
              {
               const datetime lo = (datetime)StringToInteger(c[0]);
               const datetime hi = (datetime)StringToInteger(c[1]);
               const int tf_sec = PeriodSeconds(tf);
               const long expected = (hi-lo)/tf_sec+1;
               //--- weekend slots inside the covered span (5-day trading week)
               const long span_days = (hi-lo)/86400+1;
               const long weekend_days = span_days/7*2;
               const long weekend_slots = weekend_days*(86400/tf_sec);
               missing = expected-weekend_slots-total;
               if(missing<0)
                  missing = 0;
              }
           }
         const bool tf_ok = (total==distinct && invalid==0);
         if(!tf_ok)
            clean = false;
         report += StringFormat("%s: total=%d duplicates=%d invalid=%d missing=%d\n",
                                EnumToString(tf),(int)total,(int)(total-distinct),
                                (int)invalid,(int)missing);
        }
      return(clean);
     }

   //--- cross-timeframe consistency: coarse bars vs their constituents
   bool                ValidateTimeframes(CHistoryStore &market,string &report)
     {
      report = "";
      if(!market.IsOpen())
         return(false);
      //--- H1 count vs M15 count/4 over the common coverage (2% tolerance)
      string rows[];
      if(market.Provider().Select(StringFormat(
            "SELECT "
            "MAX((SELECT MIN(OpenTime) FROM %s WHERE TimeframeID=%d),"
            "    (SELECT MIN(OpenTime) FROM %s WHERE TimeframeID=%d)),"
            "MIN((SELECT MAX(OpenTime) FROM %s WHERE TimeframeID=%d),"
            "    (SELECT MAX(OpenTime) FROM %s WHERE TimeframeID=%d))",
            HIST_TABLE_BARS,(int)PERIOD_H1,
            HIST_TABLE_BARS,(int)PERIOD_M15,
            HIST_TABLE_BARS,(int)PERIOD_H1,
            HIST_TABLE_BARS,(int)PERIOD_M15),rows)!=1)
         return(false);
      string c[];
      if(StringSplit(rows[0],';',c)!=2)
         return(false);
      const datetime common_from = (datetime)StringToInteger(c[0]);
      const datetime common_to   = (datetime)StringToInteger(c[1]);
      if(common_from<=0 || common_to<=0 || common_from>common_to)
        {
         report = "timeframe consistency: no common H1/M15 coverage";
         return(false);
        }
      if(market.Provider().Select(StringFormat(
            "SELECT (SELECT COUNT(*) FROM %s WHERE TimeframeID=%d AND OpenTime>=%d AND OpenTime<=%d),"
            "(SELECT COUNT(*) FROM %s WHERE TimeframeID=%d AND OpenTime>=%d AND OpenTime<=%d)",
            HIST_TABLE_BARS,(int)PERIOD_H1,(int)common_from,(int)common_to,
            HIST_TABLE_BARS,(int)PERIOD_M15,(int)common_from,(int)common_to),rows)!=1)
         return(false);
      if(StringSplit(rows[0],';',c)!=2)
         return(false);
      const long h1 = StringToInteger(c[0]);
      const long m15 = StringToInteger(c[1]);
      bool consistent = true;
      if(h1>0 && m15>0)
        {
         const double ratio = (double)m15/(double)h1;   // expected ~4
         consistent = (ratio>3.9 && ratio<4.1);
        }
      report = StringFormat("timeframe consistency: common=%s..%s H1=%d M15=%d ratio=%.2f (expect ~4) -> %s",
                            TimeToString(common_from,TIME_DATE),
                            TimeToString(common_to,TIME_DATE),
                            (int)h1,(int)m15,(h1>0 ? (double)m15/h1 : 0.0),
                            (consistent ? "OK" : "MISMATCH"));
      return(consistent);
     }
  };

#endif // __EA_HISTORY_INTEGRITY_MQH__
//+------------------------------------------------------------------+
