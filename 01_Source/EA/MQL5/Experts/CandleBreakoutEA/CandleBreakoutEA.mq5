//+------------------------------------------------------------------+
//|                                              CandleBreakoutEA.mq5|
//|                        Candle Breakout Expert Advisor for MT5    |
//|                                                                  |
//|  Strategy                                                        |
//|    On every new main timeframe candle the previous candle high   |
//|    and low are armed with a Buy Stop and a Sell Stop. The first  |
//|    fill removes the opposite order. When the candle closes the   |
//|    book is flattened, nothing is ever carried over.              |
//|                                                                  |
//|  Modules (MQL5/Include)                                          |
//|    EASettings.mqh        shared enums + configuration payload    |
//|    EAUtils.mqh           normalization, broker limits, helpers   |
//|    EALogger.mqh          Experts log                             |
//|    EATradeHistory.mqh    daily P/L and losing streak             |
//|    EARiskManager.mqh     daily limits + trading hours filter     |
//|    EAOrderManager.mqh    pending orders                          |
//|    EAPositionManager.mqh positions                               |
//|    EABreakEvenManager.mqh M5 swing trailing                      |
//|    EAMomentum.mqh        momentum strength measurement           |
//|    EATradeContext.mqh      unified read-only trade snapshot        |
//|    EAContext/*.mqh         Context Layer: trade/market/strategy/AI   |
//|    EAFeatureBuilder/*.mqh  centralized market feature calculation    |
//|    EAData/*.mqh            Data Access Layer (SQLite behind IDataProvider) |
//|    EAExitEngine.mqh      exit intelligence engine                |
//|    EAExitStats.mqh       exit statistics + CSV journal           |
//|    EADashboard.mqh       on-chart EXIT ENGINE panel              |
//|    EAVisualManager.mqh   chart objects                           |
//|    EATradeManager.mqh    candle cycle state machine              |
//+------------------------------------------------------------------+
#property copyright   "Candle Breakout EA"
#property link        ""
#property version     "1.00"
#property description "H1 previous candle breakout with M5 swing break even."
#property strict

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EATradeManager.mqh>

//+------------------------------------------------------------------+
//| General                                                          |
//+------------------------------------------------------------------+
input group "=== Trading ==="
input ENUM_TIMEFRAMES      InpMainTimeframe         = PERIOD_H1;             // Main Timeframe
input ulong               InpMagicNumber           = 20260909;              // Magic Number
input string              InpTradeComment          = "CandleBreakout";      // Order Comment
input bool                InpReentrySameCandle     = false;                 // Allow Re-Entry After Close In Same Candle

//+------------------------------------------------------------------+
//| Risk                                                             |
//+------------------------------------------------------------------+
input group "=== Risk ==="
input ENUM_LOT_MODE       InpLotMode               = LOT_FIXED;             // Lot Mode
input double              InpFixedLot              = 0.10;                  // Fixed Lot
input double              InpRiskPercent           = 1.0;                   // Risk % Of Balance
input double              InpMartingaleMultiplier  = 1.5;                   // Martingale Multiplier
input int                 InpMartingaleMaxSteps    = 5;                     // Maximum Martingale Steps
input double              InpRiskStopPoints        = 500;                   // Risk Stop Distance (points, lot sizing ONLY)
input bool                InpUseDailyLimits        = true;                  // Enable Daily Limits
input double              InpDailyProfit           = 0;                     // Daily Profit Limit (0 = off)
input double              InpDailyLoss             = 0;                     // Daily Loss Limit (0 = off)

//+------------------------------------------------------------------+
//| Break even                                                       |
//+------------------------------------------------------------------+
input group "=== Break Even ==="
input bool                InpEnableBreakEven       = false;                 // Enable BreakEven (optional M5 swing stop)
input ENUM_TIMEFRAMES      InpBreakEvenTimeframe    = PERIOD_M5;             // BreakEven Timeframe
input int                 InpSwingBars             = 2;                     // Swing Bars (bars left and right)
input int                 InpBreakEvenEveryBars    = 2;                     // Update Every N Completed Bars
input double              InpBreakEvenBufferPoints = 0;                     // BreakEven Buffer (points)

//+------------------------------------------------------------------+
//| Exit Intelligence Engine                                         |
//+------------------------------------------------------------------+
input group "=== Exit Engine ==="
input bool                InpEnableProfitLock      = true;                  // Enable Profit Lock
input double              InpProfitLockTriggerPoints = 300;                 // Profit Lock Trigger (points of floating profit)
input double              InpProfitLockPercent     = 50;                    // Profit Lock Keep (%) of the peak
input bool                InpEnableMomentumExit    = true;                  // Enable Momentum Exit
input double              InpMomentumSensitivity   = 40;                    // Momentum Sensitivity (0..100, higher = earlier exit)
input bool                InpEnableCarryMode       = false;                 // Enable Carry Mode (one extra H1 candle)
input int                 InpMaximumCarryCandles   = 1;                     // Maximum Carry Candles (hard cap: 1)
input double              InpMinimumTrendStrength  = 70;                    // Minimum Trend Strength For Carry (0..100)

//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
input group "=== Dashboard ==="
input bool                InpEnableDashboard       = true;                  // Show Exit Dashboard Panel
input bool                InpEnableVisuals         = true;                  // Draw Chart Objects

//+------------------------------------------------------------------+
//| Logging                                                          |
//+------------------------------------------------------------------+
input group "=== Logging ==="
input bool                InpEnableLogging         = true;                  // Enable Logging
input ENUM_LOG_LEVEL      InpLogLevel              = LOG_INFO;              // Log Level

//+------------------------------------------------------------------+
//| Advanced                                                         |
//+------------------------------------------------------------------+
input group "=== Advanced ==="
input bool                InpUseHoursFilter        = false;                 // Enable Trading Hours Filter
input long                InpTradingHoursMask      = 16777215;              // Trading Hours Bitmask (bit0 = 00:00)

//+------------------------------------------------------------------+
//| Future AI (reserved, inactive)                                   |
//+------------------------------------------------------------------+
input group "=== Future AI ==="
input bool                InpAiReserved            = false;                 // Reserved for future AI modules (no effect)

//+------------------------------------------------------------------+
//| Global objects                                                   |
//+------------------------------------------------------------------+
CLogger      g_logger;
CTradeManager g_trade_manager;

//+------------------------------------------------------------------+
//| Copy the inputs into the settings snapshot                       |
//+------------------------------------------------------------------+
CEASettings BuildSettings(void)
  {
   CEASettings settings;
   settings.Reset();

   settings.symbol_name              = _Symbol;
   settings.main_timeframe           = InpMainTimeframe;
   settings.break_even_timeframe     = InpBreakEvenTimeframe;
   settings.magic                    = InpMagicNumber;
   settings.trade_comment            = InpTradeComment;
   settings.reentry_same_candle      = InpReentrySameCandle;

   settings.lot_mode                 = InpLotMode;
   settings.fixed_lot                = InpFixedLot;
   settings.risk_percent             = InpRiskPercent;
   settings.martingale_multiplier    = InpMartingaleMultiplier;
   settings.martingale_max_steps     = InpMartingaleMaxSteps;
   settings.risk_stop_points         = InpRiskStopPoints;

   settings.break_even_enabled       = InpEnableBreakEven;
   settings.swing_bars               = InpSwingBars;
   settings.break_even_every_bars    = InpBreakEvenEveryBars;
   settings.break_even_buffer_points = InpBreakEvenBufferPoints;

   settings.profit_lock_enabled        = InpEnableProfitLock;
   settings.profit_lock_trigger_points = InpProfitLockTriggerPoints;
   settings.profit_lock_percent        = InpProfitLockPercent;
   settings.momentum_exit_enabled      = InpEnableMomentumExit;
   settings.momentum_sensitivity       = InpMomentumSensitivity;
   settings.carry_enabled              = InpEnableCarryMode;
   settings.carry_max_candles          = InpMaximumCarryCandles;
   settings.carry_min_trend_strength   = InpMinimumTrendStrength;
   settings.dashboard_enabled          = InpEnableDashboard;
   settings.ai_reserved              = InpAiReserved;

   settings.use_daily_limits         = InpUseDailyLimits;
   settings.daily_profit_limit       = InpDailyProfit;
   settings.daily_loss_limit         = InpDailyLoss;
   settings.use_hours_filter         = InpUseHoursFilter;
   settings.hours_mask               = InpTradingHoursMask;

   settings.log_level                = InpLogLevel;
   settings.visual_enabled           = InpEnableVisuals;
   return(settings);
  }

//+------------------------------------------------------------------+
//| Validate the inputs before anything is allowed to run            |
//+------------------------------------------------------------------+
bool ValidateInputs(void)
  {
   if(InpMainTimeframe==PERIOD_CURRENT)
     {
      Print("[CBEA] Main Timeframe must be an explicit timeframe, not Current");
      return(false);
     }
   if(InpFixedLot<=0.0)
     {
      Print("[CBEA] Fixed Lot must be greater than zero");
      return(false);
     }
   if(InpRiskPercent<=0.0 && InpLotMode!=LOT_FIXED)
     {
      Print("[CBEA] Risk % must be greater than zero for this lot mode");
      return(false);
     }
   if(InpMartingaleMultiplier<1.0)
     {
      Print("[CBEA] Martingale Multiplier must be 1.0 or higher");
      return(false);
     }
   if(InpMartingaleMaxSteps<1)
     {
      Print("[CBEA] Maximum Martingale Steps must be at least 1");
      return(false);
     }
   if(InpSwingBars<1)
     {
      Print("[CBEA] Swing Bars must be at least 1");
      return(false);
     }
   if(InpBreakEvenEveryBars<1)
     {
      Print("[CBEA] Update Every N Completed Bars must be at least 1");
      return(false);
     }
   if(InpUseHoursFilter && InpTradingHoursMask==0)
     {
      Print("[CBEA] Trading Hours Filter is enabled but no hour is selected");
      return(false);
     }
   if(InpProfitLockTriggerPoints<=0.0)
     {
      Print("[CBEA] Profit Lock Trigger must be greater than zero");
      return(false);
     }
   if(InpProfitLockPercent<=0.0 || InpProfitLockPercent>100.0)
     {
      Print("[CBEA] Profit Lock Keep (%) must be between 1 and 100");
      return(false);
     }
   if(InpMomentumSensitivity<0.0 || InpMomentumSensitivity>100.0)
     {
      Print("[CBEA] Momentum Sensitivity must be between 0 and 100");
      return(false);
     }
   if(InpMaximumCarryCandles!=1)
     {
      Print("[CBEA] Maximum Carry Candles must be exactly 1 (one extra candle is the hard cap)");
      return(false);
     }
   if(InpMinimumTrendStrength<0.0 || InpMinimumTrendStrength>100.0)
     {
      Print("[CBEA] Minimum Trend Strength For Carry must be between 0 and 100");
      return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(!ValidateInputs())
      return(INIT_PARAMETERS_INCORRECT);

   g_logger.Enable(InpEnableLogging);
   g_logger.Init(InpMagicNumber,_Symbol,InpLogLevel);

   const CEASettings settings = BuildSettings();
   if(!g_trade_manager.Init(settings,g_logger))
      return(INIT_FAILED);

   //--- the current candle is already running: start clean at the next one
   g_trade_manager.SetBaseline();

   g_logger.Info(StringFormat("Expert loaded | %s | trading hours %s",
                               g_trade_manager.Describe(),
                               HoursMaskToString(settings.hours_mask)));
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_trade_manager.Deinit();
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   g_trade_manager.OnTick();
  }

//+------------------------------------------------------------------+
//| Broker event handler: fills and closes without waiting for a tick|
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   g_trade_manager.OnTradeTransaction(trans);
  }
//+------------------------------------------------------------------+
