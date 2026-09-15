//+------------------------------------------------------------------+
//|                                               EATradeContext.mqh |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Unified read-only view of the live trade     |
//+------------------------------------------------------------------+
#ifndef __EA_TRADE_CONTEXT_MQH__
#define __EA_TRADE_CONTEXT_MQH__

#include <CandleBreakoutEA\EASettings.mqh>

//+------------------------------------------------------------------+
//| One snapshot that describes everything the dashboard, the exit      |
//| journal and the statistics need about the current trade.         |
//| Produced by CTradeManager::BuildContext; consumers only read it. |
//| When no position is open the ticket is 0 and numeric fields are  |
//| zeroed, so consumers never touch the market or the managers.     |
//+------------------------------------------------------------------+
struct STradeContext
  {
   ulong               ticket;
   ENUM_POSITION_TYPE  direction;
   datetime            entry_time;
   datetime            entry_candle;      // main-TF candle that armed the entry
   double              entry_price;
   double              lots;
   double              current_profit;    // account money, live
   double              current_points;    // live floating result, points
   double              max_floating_profit;   // MFE in points
   double              max_floating_loss;     // MAE in points (<= 0)
   bool                break_even_enabled;
   bool                break_even_active; // a BE stop is currently in the market
   bool                profit_lock_active;
   double              profit_lock_level; // locked level in points (0 = not armed)
   bool                carry_active;
   double              momentum_score;    // 0..100
   ENUM_EXIT_REASON    exit_reason;       // exit planned if nothing changes

   void                Reset(void)
     {
      ticket              = 0;
      direction           = POSITION_TYPE_BUY;
      entry_time          = 0;
      entry_candle        = 0;
      entry_price         = 0.0;
      lots                = 0.0;
      current_profit      = 0.0;
      current_points      = 0.0;
      max_floating_profit = 0.0;
      max_floating_loss   = 0.0;
      break_even_enabled  = false;
      break_even_active   = false;
      profit_lock_active  = false;
      profit_lock_level   = 0.0;
      carry_active        = false;
      momentum_score      = 0.0;
      exit_reason         = EXIT_H1;
     }
  };

#endif // __EA_TRADE_CONTEXT_MQH__
//+------------------------------------------------------------------+
