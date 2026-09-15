//+------------------------------------------------------------------+
//|                                                  EAExitStats.mqh|
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Exit statistics + CSV journal             |
//+------------------------------------------------------------------+
#ifndef __EA_EXIT_STATS_MQH__
#define __EA_EXIT_STATS_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAExitEngine.mqh>

//--- number of exit reasons tracked (mirrors ENUM_EXIT_REASON)
const int EXIT_REASON_COUNT = 7;

//+------------------------------------------------------------------+
//| One closed trade, fully described for the CSV journal            |
//+------------------------------------------------------------------+
struct SExitRecord
  {
   ulong               ticket;
   datetime            open_time;
   datetime            close_time;
   ENUM_POSITION_TYPE  side;
   double              lots;
   double              profit;
   ENUM_EXIT_REASON    reason;
   SExitSnapshot       snap;
   double              entry_price;    // 0 when unknown (safe default)
   double              exit_price;     // 0 when unknown (safe default)
   bool                break_even_used;
  };

//+------------------------------------------------------------------+
//| Counts exits per reason and appends every closed trade to a CSV  |
//| file in the terminal Files folder.                               |
//+------------------------------------------------------------------+
class CExitStats
  {
private:
   const CEASettings  *m_set;
   CLogger            *m_log;
   int                 m_counts[];
   int                 m_handle;

   void                WriteHeader(void)
     {
      FileWrite(m_handle,
                "Ticket","OpenTime","CloseTime","Side","Lots","Profit",
                "ExitReason","MaximumFloatingProfit","MaximumFloatingLoss",
                "ProfitLocked","CarryUsed","MomentumScore",
                "EntryPrice","ExitPrice","BreakEvenUsed","MomentumExit");
     }

public:
                       CExitStats(void) : m_set(NULL), m_log(NULL), m_handle(INVALID_HANDLE)
     {
      ArrayResize(m_counts,EXIT_REASON_COUNT);
      ArrayInitialize(m_counts,0);
     }

   void                Init(const CEASettings &settings,CLogger &logger)
     {
      m_set = &settings;
      m_log = &logger;
      const string name = StringFormat("CBEA_%I64u_%s_exits.csv",m_set.magic,m_set.symbol_name);
      const bool   fresh = !FileIsExist(name);
      m_handle = FileOpen(name,FILE_CSV|FILE_READ|FILE_WRITE|FILE_ANSI|FILE_SHARE_READ,';');
      if(m_handle==INVALID_HANDLE)
        {
         m_log.Error(StringFormat("Exit journal unavailable | %s",name));
         return;
        }
      if(fresh)
         WriteHeader();
      FileSeek(m_handle,0,SEEK_END);
      m_log.Info(StringFormat("Exit journal opened | %s",name));
     }

   void                Deinit(void)
     {
      if(m_handle!=INVALID_HANDLE)
        {
         FileClose(m_handle);
         m_handle = INVALID_HANDLE;
        }
     }

   //--- book one closed trade
   void                Record(const SExitRecord &rec)
     {
      const int idx = (int)rec.reason;
      if(idx>=0 && idx<EXIT_REASON_COUNT)
         m_counts[idx]++;

      if(m_handle==INVALID_HANDLE)
         return;
      const int digits = (int)SymbolInfoInteger(m_set.symbol_name,SYMBOL_DIGITS);
      FileWrite(m_handle,
                IntegerToString(rec.ticket),
                TimeToString(rec.open_time,TIME_DATE|TIME_MINUTES),
                TimeToString(rec.close_time,TIME_DATE|TIME_MINUTES),
                (rec.side==POSITION_TYPE_BUY ? "BUY" : "SELL"),
                DoubleToString(rec.lots,2),
                DoubleToString(rec.profit,2),
                ExitReasonToString(rec.reason),
                DoubleToString(rec.snap.max_profit_points,1),
                DoubleToString(rec.snap.max_loss_points,1),
                DoubleToString(rec.snap.profit_locked,1),
                IntegerToString(rec.snap.carry_used),
                DoubleToString(rec.snap.momentum,1),
                DoubleToString(rec.entry_price,digits),
                DoubleToString(rec.exit_price,digits),
                (rec.break_even_used ? "1" : "0"),
                (rec.reason==EXIT_MOMENTUM ? "1" : "0"));
      FileFlush(m_handle);
     }

   int                 Count(const ENUM_EXIT_REASON reason) const
     {
      const int idx = (int)reason;
      return((idx>=0 && idx<EXIT_REASON_COUNT) ? m_counts[idx] : 0);
     }

   //--- one compact line for the dashboard
   string              SummaryLine(void) const
     {
      return(StringFormat("H1:%d BE:%d PL:%d MO:%d CR:%d MN:%d ER:%d",
                          Count(EXIT_H1),Count(EXIT_BREAK_EVEN),
                          Count(EXIT_PROFIT_LOCK),Count(EXIT_MOMENTUM),
                          Count(EXIT_CARRY),Count(EXIT_MANUAL),Count(EXIT_ERROR)));
     }
  };

#endif // __EA_EXIT_STATS_MQH__
//+------------------------------------------------------------------+
