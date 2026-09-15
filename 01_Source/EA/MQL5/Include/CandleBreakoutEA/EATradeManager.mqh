//+------------------------------------------------------------------+
//|                                                 EATradeManager.mqh|
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Candle cycle state machine                |
//+------------------------------------------------------------------+
#ifndef __EA_TRADE_MANAGER_MQH__
#define __EA_TRADE_MANAGER_MQH__

#include <CandleBreakoutEA\EAUtils.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EATradeHistory.mqh>
#include <CandleBreakoutEA\EARiskManager.mqh>
#include <CandleBreakoutEA\EAOrderManager.mqh>
#include <CandleBreakoutEA\EAPositionManager.mqh>
#include <CandleBreakoutEA\EABreakEvenManager.mqh>
#include <CandleBreakoutEA\EAExitEngine.mqh>
#include <CandleBreakoutEA\EATradeContext.mqh>
#include <CandleBreakoutEA\EAContext\EAContextLayer.mqh>
#include <CandleBreakoutEA\EAFeatureBuilder\EAFeatureBuilder.mqh>
#include <CandleBreakoutEA\EAData\DatabaseManager.mqh>
#include <CandleBreakoutEA\EAData\MarketSnapshotWriter.mqh>
#include <CandleBreakoutEA\EAData\TradeWriter.mqh>
#include <CandleBreakoutEA\EAData\ObservationWriter.mqh>
#include <CandleBreakoutEA\EAData\LabelGenerator.mqh>
#include <CandleBreakoutEA\EAData\DatasetBuilder.mqh>
#include <CandleBreakoutEA\EAData\DataQualityAnalyzer.mqh>
#include <CandleBreakoutEA\EAData\FeatureRegistry.mqh>
#include <CandleBreakoutEA\EAReplay\ReplayController.mqh>
#include <CandleBreakoutEA\EAResearch\ExperimentEngine.mqh>
#include <CandleBreakoutEA\EAResearch\BenchmarkEngine.mqh>
#include <CandleBreakoutEA\EAResearch\WalkForwardEngine.mqh>
#include <CandleBreakoutEA\EAHistory\HistoryPlatform.mqh>
#include <CandleBreakoutEA\EAExitStats.mqh>
#include <CandleBreakoutEA\EADashboard.mqh>
#include <CandleBreakoutEA\EAVisualManager.mqh>

//--- a close at the broker within this distance of the last stop is
//--- classified as a break even stop, not a manual close
const double EXIT_SL_TOLERANCE_POINTS = 20.0;

//+------------------------------------------------------------------+
//| Per candle lifecycle:                                            |
//|   candle opens -> read previous high/low -> arm two stop orders  |
//|   one order fills -> the opposite order is deleted               |
//|   candle closes  -> everything is flattened, next candle starts  |
//+------------------------------------------------------------------+
class CTradeManager
  {
private:
   CEASettings         m_set;
   CLogger             m_log;
   CTradeHistory       m_history;
   CRiskManager        m_risk;
   COrderManager       m_orders;
   CPositionManager    m_positions;
   CBreakEvenManager   m_break_even;
   CExitEngine         m_exit;             // exit intelligence engine
   CExitStats          m_stats;            // exit statistics + CSV journal
   CDashboard          m_dash;             // on-chart exit HUD
   CContextLayer       m_contexts;         // Context Layer (read-only runtime state)
   CFeatureBuilder     m_features;         // centralized market features (read-only)
   CDatabaseManager    m_database;         // DAL foundation (metadata only, Task 0005)
   CMarketSnapshotWriter m_market_writer;  // market observations -> schema v2 (Task 0006)
   CTradeWriter        m_trade_writer;     // trade metadata -> schema v3 (Task 0007)
   CObservationWriter  m_observations;     // market recorder -> schema v4 (Task 0008)
   CLabelGenerator     m_labels;           // ground-truth labels -> schema v5 (Task 0009)
   CDatasetBuilder     m_datasets;         // research datasets -> schema v6 (Task 0010)
   CDataQualityAnalyzer m_quality;         // quality gate -> schema v7 (Task 0011)
   CFeatureRegistry    m_registry;         // feature catalogue -> schema v8 (Task 0012)
   CReplayController   m_replay;           // replay foundation -> schema v9 (Sprint 4)
   CExperimentEngine   m_experiments;      // research platform -> schema v10 (Sprint 5)
   CBenchmarkEngine    m_benchmarks;       // deterministic benchmarks (Sprint 5)
   CWalkForwardEngine  m_walk_forward;     // walk-forward windows (Sprint 5)
   CHistoryPlatform    m_hist_platform;    // historical data platform (Sprint 6A)
   CVisualManager      m_visual;
   double              m_risk_multiplier;  // multiplier of the last armed candle

   datetime            m_candle_time;      // open time of the candle being traded
   datetime            m_candle_close;     // closing moment of that candle
   bool                m_armed;            // pending orders are on the market
   bool                m_traded_this_candle;
   bool                m_ea_position_open; // we are tracking a live position
   ulong               m_position_ticket;
   bool                m_position_is_buy;  // direction of the tracked position
   datetime            m_position_open_time;   // for the CSV journal
   double              m_position_lots;        // for the CSV journal
   double              m_position_entry;       // for the CSV journal
   datetime            m_position_candle;      // candle that armed the entry
   bool                m_self_close;           // the EA itself sent the close
   ENUM_EXIT_REASON    m_close_reason;         // reason chosen by the EA
   ulong               m_last_recorded_ticket; // blocks a double CSV entry
   int                 m_candle_index;

   //--- current open time of the main timeframe bar
   datetime            CurrentBarTime(void) const
     {
      return(iTime(m_set.symbol_name,m_set.main_timeframe,0));
     }

   //--- adopt a position that was already running when the EA was attached
   void                SyncWithChart(void)
     {
      if(!m_positions.HasPosition())
         return;
      const ulong ticket = m_positions.Ticket();
      if(ticket==0 || !m_positions.Select(ticket))
         return;
      m_ea_position_open  = true;
      m_traded_this_candle= true;
      m_position_ticket   = ticket;
      m_position_open_time= m_positions.OpenTime();
      m_position_lots     = m_positions.Lots();
      m_position_entry    = m_positions.EntryPrice();
      m_position_candle   = CurrentBarTime();
      m_break_even.Start(ticket,m_positions.OpenTime());
      m_exit.Start(ticket,m_positions.Type(),m_positions.EntryPrice());
      m_trade_writer.InsertTrade(ticket,m_positions.Type()==POSITION_TYPE_BUY,m_position_lots,
                                 m_position_open_time,m_position_entry,m_position_candle);
      m_log.Warn(StringFormat("Existing position #%I64u adopted on attach and will be managed",ticket));
     }

   //--- everything that must happen the moment a new candle opens
   void                StartNewCandle(const datetime bar_time)
     {
      //--- Carry Mode first: a strong profitable position may survive
      //--- ONE extra candle. No new pendings while a position is carried.
      if(m_candle_time>0 && m_positions.HasPosition() && m_exit.TryCarry())
        {
         m_candle_time        = bar_time;
         m_candle_close       = CEAUtils::BarCloseTime(m_set.symbol_name,m_set.main_timeframe,0);
         m_armed              = false;
         m_traded_this_candle = true;
         m_candle_index++;
         m_risk.ReportDailyState();
         if(m_orders.CountOrders()>0)
            m_orders.DeleteAll("carry mode | new entries paused for one candle");
         m_log.Info(StringFormat("New Candle | #%d | carried position #%I64u | no new pendings | close %s",
                                  m_candle_index,m_position_ticket,
                                  TimeToString(m_candle_close,TIME_DATE|TIME_MINUTES)));
         return;
        }

      //--- the candle that just finished is the one we were trading
      if(m_candle_time>0)
         CloseCandle();

      m_candle_time        = bar_time;
      m_candle_close       = CEAUtils::BarCloseTime(m_set.symbol_name,m_set.main_timeframe,0);
      m_armed              = false;
      m_traded_this_candle = false;
      m_candle_index++;
      m_break_even.Reset();
      m_risk.ReportDailyState();

      m_log.Info(StringFormat("New Candle | #%d | %s | %s | close %s",
                               m_candle_index,
                               EnumToString(m_set.main_timeframe),
                               TimeToString(m_candle_time,TIME_DATE|TIME_MINUTES),
                               TimeToString(m_candle_close,TIME_DATE|TIME_MINUTES)));

      ArmCandle();
     }

   //--- flatten the book at the candle close: position first (with its
   //--- exit reason), then any leftover pending order
   void                CloseCandle(void)
     {
      //--- the reason must be read BEFORE the engine state is reset
      const ENUM_EXIT_REASON reason = m_exit.CandleCloseReason();
      if(m_positions.HasPosition())
         ClosePositionForReason(reason);

      m_ea_position_open = false;
      m_position_ticket  = 0;
      m_break_even.Reset();
      m_exit.Reset();
      m_visual.DrawStopLevel(0.0);

      if(m_orders.CountOrders()>0)
         m_orders.DeleteAll(StringFormat("candle %s closed",
                                         TimeToString(m_candle_time,TIME_DATE|TIME_MINUTES)));
     }

   //--- the EA closes the position itself and books it under one reason
   void                ClosePositionForReason(const ENUM_EXIT_REASON reason)
     {
      if(!m_positions.HasPosition())
         return;
      const ulong ticket = m_positions.Ticket();
      if(ticket==0 || !m_positions.Select(ticket))
         return;

      const double close_price = (m_positions.Type()==POSITION_TYPE_BUY
                                  ? CEAUtils::Bid(m_set.symbol_name)
                                  : CEAUtils::Ask(m_set.symbol_name));

      m_self_close   = true;
      m_close_reason = reason;
      m_positions.CloseAll(ExitReasonToString(reason));

      RecordExitOnce(ticket,reason,close_price,TimeCurrent());
      m_exit.Reset();
     }

   //--- one CSV/statistics entry per ticket, however the position left
   void                RecordExitOnce(const ulong ticket,const ENUM_EXIT_REASON reason,
                                      const double close_price,const datetime moment)
     {
      if(ticket==0 || ticket==m_last_recorded_ticket)
         return;
      m_last_recorded_ticket = ticket;

      //--- realized result from the history; fallback: price difference
      double profit = m_history.DealProfitOfPosition(ticket);
      if(profit==0.0 && m_position_lots>0.0 && m_position_entry>0.0)
        {
         const double diff = (m_position_is_buy ? close_price-m_position_entry
                                                : m_position_entry-close_price);
         profit = CEAUtils::TickValuePerLot(m_set.symbol_name)*diff*m_position_lots;
        }

      SExitRecord rec;
      rec.ticket        = ticket;
      rec.open_time       = m_position_open_time;
      rec.close_time      = (moment>0 ? moment : TimeCurrent());
      rec.side            = (m_position_is_buy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL);
      rec.lots            = m_position_lots;
      rec.profit          = profit;
      rec.reason          = reason;
      rec.entry_price     = m_position_entry;
      rec.exit_price      = close_price;
      rec.break_even_used = m_break_even.HadStop();
      m_exit.Snapshot(rec.snap);
      m_stats.Record(rec);

      //--- trade intelligence: realized components + snapshot linkage (Task 0007)
      double gross = 0.0, swap = 0.0, comm = 0.0;
      m_history.DealCostsOfPosition(ticket,gross,swap,comm);
      if(gross==0.0 && swap==0.0 && comm==0.0)
         gross = profit;   // history not booked yet: keep the price-difference result
      m_trade_writer.UpdateTradeExit(ticket,m_position_open_time,m_position_candle,
                                     rec.close_time,close_price,gross,swap,comm,
                                     (int)reason,rec.break_even_used,
                                     rec.snap.carry_used>0,reason==EXIT_MOMENTUM,
                                     reason==EXIT_PROFIT_LOCK);

      m_log.Exit(StringFormat("Exit recorded | #%I64u | %s | profit %.2f | peak %.0f pts | momentum %.0f",
                               ticket,ExitReasonToString(reason),profit,
                               rec.snap.max_profit_points,rec.snap.momentum));
     }

   //--- assemble the shared read-only view of the live trade
   void                BuildContext(STradeContext &ctx) const
     {
      ctx.Reset();
      ctx.break_even_enabled = m_set.break_even_enabled;

      const ulong ticket = m_positions.Ticket();
      if(!m_ea_position_open || ticket==0 || !m_positions.Select(ticket))
         return;

      ctx.ticket              = ticket;
      ctx.direction           = m_positions.Type();
      ctx.entry_time          = m_position_open_time;
      ctx.entry_candle        = m_position_candle;
      ctx.entry_price         = m_position_entry;
      ctx.lots                = m_positions.Lots();
      ctx.current_profit      = m_positions.CurrentProfit();
      ctx.current_points      = m_exit.LastFloating();
      ctx.max_floating_profit = m_exit.Peak();
      ctx.max_floating_loss   = m_exit.Worst();
      ctx.break_even_active   = (m_set.break_even_enabled && m_positions.StopLoss()>0.0);
      ctx.profit_lock_active  = m_exit.LockArmed();
      ctx.profit_lock_level   = m_exit.LockLevel();
      ctx.carry_active        = (m_exit.CarryUsed()>0);
      ctx.momentum_score      = m_exit.LastScore();
      ctx.exit_reason         = m_exit.CandleCloseReason();
     }

   //--- human readable cycle state, shared by dashboard and context layer
   string              StrategyStateText(const STradeContext &ctx) const
     {
      return(ctx.ticket!=0 ? (ctx.carry_active ? "CARRY" : "IN TRADE")
             : (m_armed ? "ARMED" : "IDLE"));
     }

   //--- refresh the Context Layer always; the panel only when enabled
   void                UpdateDashboard(void)
     {
      STradeContext ctx;
      BuildContext(ctx);
      const string state = StrategyStateText(ctx);
      m_features.Update();
      m_market_writer.Update();
      m_observations.Update();
      m_labels.UpdatePendingLabels();
      m_datasets.Update();
      m_quality.Update();
      m_registry.Update(1);   // DATASET_VERSION = 1 in this phase
      m_contexts.Update(ctx,m_armed,m_risk_multiplier,state);
      if(!m_set.dashboard_enabled)
         return;
      m_dash.Update(ctx,m_stats,state);
     }

   //--- read the previous candle and place the two stop orders
   void                ArmCandle(void)
     {
      //--- a carried position is still open: never stack a second trade
      if(m_positions.HasPosition())
        {
         m_log.Trade("Arming skipped | carried position still open");
         return;
        }

      const string symbol = m_set.symbol_name;
      const int    digits = (int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);

      const double prev_high = iHigh(symbol,m_set.main_timeframe,1);
      const double prev_low  = iLow(symbol,m_set.main_timeframe,1);
      if(prev_high<=0.0 || prev_low<=0.0 || prev_high<=prev_low)
        {
         m_log.Warn("Pending Orders skipped | previous candle could not be read");
         return;
        }

      string reason = "";
      if(m_risk.Check(reason)!=BLOCK_NONE)
         return;                              // the manager logged the exact reason

      m_risk_multiplier = CurrentRiskMultiplier();
      const double lots = CalculateLotSize();
      if(lots<=0.0)
        {
         m_log.Error("Pending Orders skipped | calculated lot size is zero");
         return;
        }

      const datetime expiration = CEAUtils::EffectiveExpiration(symbol,m_candle_close);
      if(expiration==0)
         m_log.Debug("Pending orders are placed without expiration | the EA deletes them at the candle close");

      ulong buy_ticket  = 0;
      ulong sell_ticket = 0;
      string errors     = "";

      //--- pure breakout orders: NO stop loss, NO take profit
      const bool buy_ok = m_orders.PlaceBuyStop(prev_high,lots,expiration,buy_ticket);
      if(!buy_ok)
         errors += "buy stop failed; ";

      const bool sell_ok = m_orders.PlaceSellStop(prev_low,lots,expiration,sell_ticket);
      if(!sell_ok)
         errors += "sell stop failed; ";

      if(!buy_ok && !sell_ok)
        {
         m_log.Error(StringFormat("Pending Orders not created | %s",errors));
         return;
        }

      m_armed = true;
      m_visual.DrawBreakoutLevels(prev_high,prev_low);
      m_visual.DrawPendingLevels(buy_ok ? prev_high : 0.0,sell_ok ? prev_low : 0.0,
                                 (expiration>0 ? expiration : m_candle_close));

      m_log.Trade(StringFormat("Pending Orders Created | BuyStop %s | SellStop %s | no SL | no TP | lots %.2f%s",
                               CEAUtils::DoubleToStr(prev_high,digits),
                               CEAUtils::DoubleToStr(prev_low,digits),
                               lots,
                               (StringLen(errors)>0 ? StringFormat(" | partial: %s",errors) : "")));
     }

   //--- Fixed / Risk% / Soft / Hard Martingale
   double              CalculateLotSize(void)
     {
      double base_lot = m_set.fixed_lot;
      if(m_set.lot_mode!=LOT_FIXED)
         base_lot = RiskLotSize();

      double multiplier = 1.0;
      if(m_set.lot_mode==LOT_SOFT_MARTINGALE || m_set.lot_mode==LOT_HARD_MARTINGALE)
         multiplier = MartingaleMultiplier();

      return(CEAUtils::ClampVolume(m_set.symbol_name,base_lot*multiplier));
     }

   //--- risk based lot: money at risk / money lost per lot over the configured distance.
   //--- the distance is a pure INPUT: the EA never derives a stop from candles and
   //--- never turns it into an order stop. It only scales the lot.
   double              RiskLotSize(void)
     {
      const string symbol = m_set.symbol_name;
      if(m_set.risk_percent<=0.0)
        {
         m_log.Warn("Risk lot = 0 | risk percent is not positive");
         return(0.0);
        }
      const double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      if(balance<=0.0)
        {
         m_log.Warn("Risk lot = 0 | account balance is not available");
         return(0.0);
        }
      const double money_at_risk = balance*m_set.risk_percent/100.0;
      const double distance = m_set.risk_stop_points*CEAUtils::PointValue(symbol);
      if(distance<=0.0)
        {
         m_log.Warn("Risk lot = 0 | Risk Stop Distance input is not positive");
         return(0.0);
        }
      const double loss_per_lot = CEAUtils::TickValuePerLot(symbol)*distance;
      if(loss_per_lot<=0.0)
        {
         m_log.Warn("Risk lot = 0 | tick value is not available for this symbol");
         return(0.0);
        }
      return(money_at_risk/loss_per_lot);
     }

   //--- Soft: capped progression. Hard: uncapped, reset after the max steps.
   double              MartingaleMultiplier(void)
     {
      const double multiplier = CurrentRiskMultiplier();
      m_log.Debug(StringFormat("Martingale | consecutive losses %d | multiplier %.4f",
                               m_history.ConsecutiveLosses(),multiplier));
      return(multiplier);
     }

   //--- the same progression without logging, for the Context Layer
   double              CurrentRiskMultiplier(void) const
     {
      if(m_set.lot_mode!=LOT_SOFT_MARTINGALE && m_set.lot_mode!=LOT_HARD_MARTINGALE)
         return(1.0);
      const int    max_steps = (m_set.martingale_max_steps>0 ? m_set.martingale_max_steps : 1);
      const double base      = (m_set.martingale_multiplier>1.0 ? m_set.martingale_multiplier : 1.0);
      const int    streak    = m_history.ConsecutiveLosses();
      const int    steps     = (m_set.lot_mode==LOT_SOFT_MARTINGALE
                                ? MathMin(streak,max_steps) : streak % max_steps);
      return(MathPow(base,steps));
     }

   //--- a pending order turned into a position
   void                HandlePositionOpened(const ulong ticket)
     {
      if(ticket==0)
         return;
      if(m_ea_position_open && m_position_ticket==ticket)
         return;
      if(!m_positions.Select(ticket))
         return;

      const bool   is_buy = (m_positions.Type()==POSITION_TYPE_BUY);
      const double entry  = m_positions.EntryPrice();
      const double lots   = m_positions.Lots();
      const int    digits = (int)SymbolInfoInteger(m_set.symbol_name,SYMBOL_DIGITS);

      m_ea_position_open   = true;
      m_position_ticket    = ticket;
      m_position_is_buy    = is_buy;
      m_position_open_time = m_positions.OpenTime();
      m_position_lots      = lots;
      m_position_entry     = entry;
      m_position_candle    = m_candle_time;
      m_last_recorded_ticket = 0;
      m_traded_this_candle = true;
      m_armed              = false;
      m_self_close         = false;

      //--- only one trade per candle: the opposite pending order goes away
      const ENUM_ORDER_TYPE opposite = (is_buy ? ORDER_TYPE_SELL_STOP : ORDER_TYPE_BUY_STOP);
      m_orders.DeleteByType(opposite,StringFormat("%s triggered",is_buy ? "Buy" : "Sell"));

      m_break_even.Start(ticket,m_positions.OpenTime());
      m_exit.Start(ticket,m_positions.Type(),entry);
      m_visual.DrawEntry(is_buy,entry,m_positions.OpenTime());
      m_trade_writer.InsertTrade(ticket,is_buy,lots,
                                 m_position_open_time,entry,m_position_candle);

      m_log.Trade(StringFormat("%s Triggered | #%I64u | entry %s | lots %.2f | no SL | no TP | candle %s",
                               (is_buy ? "Buy" : "Sell"),ticket,
                               CEAUtils::DoubleToStr(entry,digits),lots,
                               TimeToString(m_candle_time,TIME_DATE|TIME_MINUTES)));
     }

   //--- a tracked position disappeared from the market
   void                HandlePositionClosed(const ulong ticket,const double price,const datetime moment)
     {
      if(!m_ea_position_open)
         return;
      if(ticket!=0 && m_position_ticket!=0 && ticket!=m_position_ticket)
         return;

      //--- a position is closed at the side opposite to its direction
      const double close_price = (price>0.0 ? price :
                                  (m_position_is_buy ? CEAUtils::Bid(m_set.symbol_name)
                                                     : CEAUtils::Ask(m_set.symbol_name)));

      //--- classify how the position left: our own close, a break even
      //--- stop filled by the broker, or a manual/terminal close
      ENUM_EXIT_REASON reason = m_close_reason;
      if(!m_self_close)
        {
         const double sl         = m_exit.LastStop();
         const double tolerance  = EXIT_SL_TOLERANCE_POINTS*CEAUtils::PointValue(m_set.symbol_name);
         reason = (sl>0.0 && MathAbs(close_price-sl)<=tolerance) ? EXIT_BREAK_EVEN : EXIT_MANUAL;
        }
      RecordExitOnce(m_position_ticket,reason,close_price,(moment>0 ? moment : TimeCurrent()));

      m_self_close         = false;
      m_ea_position_open   = false;
      m_position_ticket    = 0;
      m_traded_this_candle = true;
      m_armed              = false;
      m_break_even.Reset();
      m_exit.Reset();
      m_visual.DrawStopLevel(0.0);
      m_visual.DrawExit(m_position_is_buy,close_price,(moment>0 ? moment : TimeCurrent()));

      //--- no re-entry inside the same candle unless the user allows it
      if(!m_set.reentry_same_candle)
         m_orders.DeleteAll("one trade per candle, position already closed");
      m_log.Exit(StringFormat("Position closed | #%I64u | re-entry this candle: %s",
                               ticket,(m_set.reentry_same_candle ? "allowed" : "blocked")));
     }

   //--- watch the pending orders for a fill
   void                PollPendingOrders(void)
     {
      if(!m_armed)
         return;
      const ulong filled = m_positions.Ticket();
      if(filled>0)
        {
         HandlePositionOpened(filled);
         return;
        }
      //--- both orders gone without a fill: the candle produced nothing
      if(m_orders.CountOrders()==0)
        {
         m_armed = false;
         m_log.Trade(StringFormat("Pending Orders expired untouched | candle %s",
                                  TimeToString(m_candle_time,TIME_DATE|TIME_MINUTES)));
        }
     }

   //--- optional: re-arm the opposite side of the same candle
   void                PollReEntry(void)
     {
      if(!m_set.reentry_same_candle)
         return;
      if(m_traded_this_candle && !m_positions.HasPosition() && !m_armed && m_orders.CountOrders()==0)
        {
         m_log.Info("Re-entry allowed by settings | re-arming the breakout for this candle");
         ArmCandle();
        }
     }

public:
                       CTradeManager(void) : m_candle_time(0), m_candle_close(0), m_armed(false),
                                             m_traded_this_candle(false), m_ea_position_open(false),
                                             m_position_ticket(0), m_position_open_time(0),
                                             m_position_lots(0.0), m_position_entry(0.0),
                                             m_self_close(false), m_close_reason(EXIT_H1),
                                             m_last_recorded_ticket(0), m_position_candle(0), m_risk_multiplier(1.0),
                                             m_candle_index(0) {}

   //--- build the settings snapshot and wire every manager
   bool                Init(const CEASettings &settings,CLogger &logger)
     {
      m_set = settings;
      if(StringLen(m_set.symbol_name)==0)
         m_set.symbol_name = _Symbol;

      m_log = logger;
      m_log.Init(m_set.magic,m_set.symbol_name,m_set.log_level);

      m_history.Init(m_set.magic,m_set.symbol_name);
      m_risk.Init(m_set,m_log,m_history);
      m_orders.Init(m_set,m_log);
      m_positions.Init(m_set,m_log);
      m_break_even.Init(m_set,m_log);
      m_exit.Init(m_set,m_log);
      m_stats.Init(m_set,m_log);
      m_dash.Init(m_set);
      m_contexts.Init(m_set,m_log);
      m_features.Initialize(m_set,m_log);
      m_database.Initialize(m_set,m_log);
      m_database.Open();
      m_market_writer.Initialize(m_set,m_log,m_database,m_features,m_contexts);
      m_trade_writer.Initialize(m_set,m_log,m_database,m_market_writer);
      m_observations.Initialize(m_set,m_log,m_database,m_features,m_market_writer);
      m_labels.Initialize(m_set,m_log,m_database);
      m_datasets.Initialize(m_set,m_log,m_database);
      m_quality.Initialize(m_set,m_log,m_database);
      m_datasets.AttachQuality(m_quality);
      m_registry.Initialize(m_set,m_log,m_database);
      m_replay.Initialize(m_set,m_log,m_database);   // dormant: started only via explicit API
      m_experiments.Initialize(m_set,m_log,m_database);
      m_benchmarks.Initialize(m_set,m_log,m_database,m_experiments);
      m_walk_forward.Initialize(m_set,m_log,m_database,m_experiments);
      m_hist_platform.Initialize(m_set,m_log,m_database); // dormant: exports via explicit API only
      m_visual.Init(m_set,m_log);

      SyncWithChart();
      m_log.Info(StringFormat("Initialized | %s | %s | lot mode %s | break even %s | hours %s",
                               m_set.symbol_name,EnumToString(m_set.main_timeframe),
                               LotModeToString(m_set.lot_mode),
                               (m_set.break_even_enabled ? EnumToString(m_set.break_even_timeframe) : "off"),
                               HoursMaskToString(m_set.hours_mask)));
      m_log.Info(StringFormat("Exit Engine | profit lock %s | momentum exit %s | carry %s | dashboard %s",
                               (m_set.profit_lock_enabled ? "on" : "off"),
                               (m_set.momentum_exit_enabled ? "on" : "off"),
                               (m_set.carry_enabled ? "on" : "off"),
                               (m_set.dashboard_enabled ? "on" : "off")));
      return(true);
     }

   //--- first tick only records the bar; trading starts with the next candle
   void                SetBaseline(void)
     {
      m_candle_time = CurrentBarTime();
      m_candle_close= CEAUtils::BarCloseTime(m_set.symbol_name,m_set.main_timeframe,0);
      m_log.Info(StringFormat("Baseline candle %s | first cycle starts at the next %s bar",
                              TimeToString(m_candle_time,TIME_DATE|TIME_MINUTES),
                              EnumToString(m_set.main_timeframe)));
     }

   //--- main entry point, called from OnTick
   void                OnTick(void)
     {
      const datetime bar_time = CurrentBarTime();
      if(bar_time<=0)
         return;
      if(bar_time!=m_candle_time)
         StartNewCandle(bar_time);

      //--- one position scan per tick; the exit engine then evaluates
      //--- priorities #2/#3 and returns AT MOST one close request
      const ulong ticket = m_positions.Ticket();
      if(ticket>0)
        {
         if(m_positions.Select(ticket))
           {
            if(!m_ea_position_open)
               HandlePositionOpened(ticket);
            //--- priority #1: break even keeps its original behaviour
            m_break_even.OnTick(ticket,m_positions.Type(),m_positions.OpenTime(),
                                m_positions.EntryPrice(),m_positions.StopLoss(),m_positions.TakeProfit());
            //--- priority #2 + #3: profit lock and momentum run after break even
            ENUM_EXIT_REASON exit_reason;
            if(m_exit.OnTick(m_positions.StopLoss(),exit_reason))
               ClosePositionForReason(exit_reason);
            else
               m_visual.DrawStopLevel(m_positions.StopLoss());
           }
         UpdateDashboard();
         return;
        }

      if(m_ea_position_open)
        {
         HandlePositionClosed(m_position_ticket,0.0,TimeCurrent());
         UpdateDashboard();
         return;
        }

      PollPendingOrders();
      PollReEntry();
      UpdateDashboard();
     }

   //--- fast reaction to broker events, complements the tick polling
   void                OnTradeTransaction(const MqlTradeTransaction &trans)
     {
      if(trans.symbol!=m_set.symbol_name)
         return;

      switch(trans.type)
        {
         case TRADE_TRANSACTION_DEAL_ADD:
           {
            if(!HistoryDealSelect(trans.deal))
               return;
            if(HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=(long)m_set.magic)
               return;
            const ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
            if(entry==DEAL_ENTRY_IN)
               HandlePositionOpened((ulong)HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID));
            else
               if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY)
                  HandlePositionClosed((ulong)HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID),
                                       HistoryDealGetDouble(trans.deal,DEAL_PRICE),
                                       (datetime)HistoryDealGetInteger(trans.deal,DEAL_TIME));
            break;
           }
         case TRADE_TRANSACTION_ORDER_DELETE:
            if(m_armed && m_orders.CountOrders()==0 && !m_positions.HasPosition())
               PollPendingOrders();
            break;
         default:
            break;
        }
     }

   //--- diagnostics for OnInit
   string              Describe(void) const
     {
      return(StringFormat("symbol=%s timeframe=%s magic=%I64u lots=%s",
                          m_set.symbol_name,EnumToString(m_set.main_timeframe),
                          m_set.magic,LotModeToString(m_set.lot_mode)));
     }

   void                Deinit(void)
     {
      m_dash.Hide();
      m_visual.Cleanup();
      m_stats.Deinit();
      m_hist_platform.Shutdown();
      m_database.Close();
      m_log.Info("Expert removed from the chart");
     }
  };

#endif // __EA_TRADE_MANAGER_MQH__
//+------------------------------------------------------------------+
