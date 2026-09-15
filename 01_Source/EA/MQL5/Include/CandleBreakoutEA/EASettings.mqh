//+------------------------------------------------------------------+
//|                                                   EASettings.mqh |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Shared enumerations and settings payload  |
//+------------------------------------------------------------------+
#ifndef __EA_SETTINGS_MQH__
#define __EA_SETTINGS_MQH__

//+------------------------------------------------------------------+
//| Position sizing mode                                             |
//+------------------------------------------------------------------+
enum ENUM_LOT_MODE
  {
   LOT_FIXED          = 0,  // Fixed Lot
   LOT_RISK_PERCENT   = 1,  // Risk % of Balance
   LOT_SOFT_MARTINGALE= 2,  // Soft Martingale (capped steps)
   LOT_HARD_MARTINGALE= 3   // Hard Martingale (reset after max steps)
  };

//+------------------------------------------------------------------+
//| Every closed trade is booked under exactly one of these reasons  |
//+------------------------------------------------------------------+
enum ENUM_EXIT_REASON
  {
   EXIT_H1          = 0, // mandatory flatten at the candle close
   EXIT_BREAK_EVEN  = 1, // stopped out by the M5 swing break even
   EXIT_PROFIT_LOCK = 2, // floating profit drawdown hit the lock level
   EXIT_MOMENTUM    = 3, // momentum weakened, early exit
   EXIT_CARRY       = 4, // carried position closed at the extra candle close
   EXIT_MANUAL      = 5, // closed outside of the EA (terminal, broker)
   EXIT_ERROR       = 6  // close failed or could not be classified
  };

//+------------------------------------------------------------------+
string ExitReasonToString(const ENUM_EXIT_REASON reason)
  {
   switch(reason)
     {
      case EXIT_H1:          return("H1 Close");
      case EXIT_BREAK_EVEN:  return("BreakEven");
      case EXIT_PROFIT_LOCK: return("Profit Lock");
      case EXIT_MOMENTUM:    return("Momentum Exit");
      case EXIT_CARRY:       return("Carry Expired");
      case EXIT_MANUAL:      return("Manual");
      case EXIT_ERROR:       return("Error");
     }
   return("Error");
  }

//+------------------------------------------------------------------+
//| Why a candle cycle was not armed                                 |
//+------------------------------------------------------------------+
enum ENUM_TRADE_BLOCK
  {
   BLOCK_NONE       = 0, // Trading allowed
   BLOCK_HOURS      = 1, // Outside the allowed hours
   BLOCK_DAILY_PNL  = 2  // Daily profit or loss limit reached
  };

//+------------------------------------------------------------------+
//| Verbosity of the Experts log                                     |
//+------------------------------------------------------------------+
enum ENUM_LOG_LEVEL
  {
   LOG_ERRORS   = 0, // Errors only
   LOG_WARNINGS = 1, // Errors + Warnings
   LOG_INFO     = 2, // Errors + Warnings + Info
   LOG_DEBUG    = 3  // Everything
  };

//+------------------------------------------------------------------+
//| Configuration snapshot built from the EA inputs.                 |
//| Every manager keeps a pointer to the single instance owned by    |
//| the trade manager. Declared as a class because MQL5 does not     |
//| allow pointers to plain structures.                              |
//+------------------------------------------------------------------+
class CEASettings
  {
public:
   string              symbol_name;
   ENUM_TIMEFRAMES     main_timeframe;
   ENUM_TIMEFRAMES     break_even_timeframe;
   ulong               magic;
   string              trade_comment;
   bool                reentry_same_candle;
   //--- sizing
   ENUM_LOT_MODE       lot_mode;
   double              fixed_lot;
   double              risk_percent;
   double              martingale_multiplier;
   int                 martingale_max_steps;
   double              risk_stop_points;   // lot sizing ONLY, never a stop order
   //--- break even
   bool                break_even_enabled;
   int                 swing_bars;
   int                 break_even_every_bars;
   double              break_even_buffer_points;
   //--- filters
   bool                use_daily_limits;
   double              daily_profit_limit;
   double              daily_loss_limit;
   bool                use_hours_filter;
   long                hours_mask;
   //--- exit intelligence engine
   bool                profit_lock_enabled;
   double              profit_lock_trigger_points;
   double              profit_lock_percent;
   bool                momentum_exit_enabled;
   double              momentum_sensitivity;
   bool                carry_enabled;
   int                 carry_max_candles;
   double              carry_min_trend_strength;
   bool                dashboard_enabled;
   bool                ai_reserved;          // Future AI group placeholder (no effect)
   //--- interface
   ENUM_LOG_LEVEL      log_level;
   bool                visual_enabled;

   void                Reset(void)
     {
      symbol_name           = _Symbol;
      main_timeframe        = PERIOD_H1;
      break_even_timeframe  = PERIOD_M5;
      magic                 = 20260909;
      trade_comment         = "CandleBreakout";
      reentry_same_candle   = false;
      lot_mode              = LOT_FIXED;
      fixed_lot             = 0.10;
      risk_percent          = 1.0;
      martingale_multiplier = 1.5;
      martingale_max_steps  = 5;
      risk_stop_points      = 500.0;
      break_even_enabled    = true;
      swing_bars            = 2;
      break_even_every_bars = 2;
      break_even_buffer_points = 0.0;
      use_daily_limits      = true;
      daily_profit_limit    = 0.0;
      daily_loss_limit      = 0.0;
      use_hours_filter      = false;
      hours_mask            = 0xFFFFFF;
      profit_lock_enabled      = true;
      profit_lock_trigger_points = 300.0;
      profit_lock_percent      = 50.0;
      momentum_exit_enabled    = true;
      momentum_sensitivity     = 40.0;
      carry_enabled            = false;
      carry_max_candles        = 1;
      carry_min_trend_strength = 70.0;
      dashboard_enabled        = true;
      ai_reserved              = false;
      log_level             = LOG_INFO;
      visual_enabled        = true;
     }
  };

//+------------------------------------------------------------------+
//| Human readable name of a sizing mode                             |
//+------------------------------------------------------------------+
string LotModeToString(const ENUM_LOT_MODE mode)
  {
   switch(mode)
     {
      case LOT_FIXED:           return("Fixed Lot");
      case LOT_RISK_PERCENT:    return("Risk % of Balance");
      case LOT_SOFT_MARTINGALE: return("Soft Martingale");
      case LOT_HARD_MARTINGALE: return("Hard Martingale");
     }
   return("Unknown");
  }

//+------------------------------------------------------------------+
//| Expand the 24 bit hour mask into "0,1,2,...,23"                  |
//+------------------------------------------------------------------+
string HoursMaskToString(const long mask)
  {
   string text = "";
   for(int hour=0; hour<24; hour++)
     {
      if((mask & (1L<<hour))==0)
         continue;
      if(StringLen(text)>0)
         text += ",";
      text += IntegerToString(hour);
     }
   if(StringLen(text)==0)
      return("(none)");
   return(text);
  }

#endif // __EA_SETTINGS_MQH__
//+------------------------------------------------------------------+
