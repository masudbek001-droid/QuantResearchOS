//+------------------------------------------------------------------+
//|                                                  EAExitEngine.mqh|
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Exit Intelligence Engine                  |
//+------------------------------------------------------------------+
#ifndef __EA_EXIT_ENGINE_MQH__
#define __EA_EXIT_ENGINE_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EAUtils.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAMomentum.mqh>

//+------------------------------------------------------------------+
//| Minimum completed break-even bars before a momentum verdict is   |
//| allowed - a fresh entry needs a few bars of evidence.            |
//+------------------------------------------------------------------+
const int EXIT_MIN_EVIDENCE_BARS = 3;

//+------------------------------------------------------------------+
//| Everything the statistics, CSV and dashboard need per closed     |
//| trade. Filled by the engine right before the position leaves.    |
//+------------------------------------------------------------------+
struct SExitSnapshot
  {
   double              max_profit_points;  // best floating profit reached
   double              max_loss_points;    // worst floating profit reached (<=0)
   double              profit_locked;      // locked level in points (0 = never armed)
   int                 carry_used;         // extra candles the trade survived
   double              momentum;           // last momentum score 0..100
  };

//+------------------------------------------------------------------+
//| Decides WHEN an open position should leave before the mandatory  |
//| candle flatten, and whether a strong trade may be carried one    |
//| more candle. Entry logic never touches this class.               |
//|                                                                  |
//| Priority: #1 BreakEven (existing manager, runs first)            |
//|           #2 Profit Lock                                         |
//|           #3 Momentum Exit                                       |
//|           #4 mandatory candle close (trade manager)              |
//+------------------------------------------------------------------+
class CExitEngine
  {
private:
   const CEASettings  *m_set;
   CLogger            *m_log;
   CMomentumAnalyzer   m_momentum;

   ulong               m_ticket;
   ENUM_POSITION_TYPE  m_side;
   double              m_entry;
   datetime            m_last_be_bar;     // last seen break-even bar
   int                 m_be_bars;         // completed break-even bars in trade
   double              m_peak;            // best floating profit, points
   double              m_worst;           // worst floating profit, points
   double              m_last_sl;         // last seen stop, classifies broker closes
   double              m_last_score;
   double              m_last_floating;     // live floating result of the last tick
   double              m_point;             // cached symbol point
   int                 m_carry_used;
   bool                m_lock_armed;
   double              m_lock_level;

   //--- floating profit of the tracked position expressed in points
   double              FloatingPoints(void) const
     {
      const double point = m_point;
      if(point<=0.0 || m_entry<=0.0)
         return(0.0);
      const double price = (m_side==POSITION_TYPE_BUY ? CEAUtils::Bid(m_set.symbol_name)
                                                      : CEAUtils::Ask(m_set.symbol_name));
      return((m_side==POSITION_TYPE_BUY ? price-m_entry : m_entry-price)/point);
     }

public:
                       CExitEngine(void) : m_set(NULL), m_log(NULL), m_ticket(0),
                                           m_side(POSITION_TYPE_BUY), m_entry(0.0),
                                           m_last_be_bar(0), m_be_bars(0), m_peak(0.0),
                                           m_worst(0.0), m_last_sl(0.0), m_last_score(50.0), m_last_floating(0.0), m_point(0.0),
                                           m_carry_used(0), m_lock_armed(false), m_lock_level(0.0) {}

   void                Init(const CEASettings &settings,CLogger &logger)
     {
      m_set = &settings;
      m_log = &logger;
      m_point = CEAUtils::PointValue(settings.symbol_name);
      m_momentum.Init(settings);
     }

   //--- a fresh position appeared
   void                Start(const ulong ticket,const ENUM_POSITION_TYPE side,const double entry)
     {
      m_ticket      = ticket;
      m_side        = side;
      m_entry       = entry;
      m_last_be_bar = iTime(m_set.symbol_name,m_set.break_even_timeframe,0);
      m_be_bars     = 0;
      m_peak        = 0.0;
      m_worst       = 0.0;
      m_last_sl     = 0.0;
      m_last_score  = 50.0;
      m_last_floating = 0.0;
      m_carry_used  = 0;
      m_lock_armed  = false;
      m_lock_level  = 0.0;
     }

   void                Reset(void)
     {
      m_ticket     = 0;
      m_carry_used = 0;
      m_lock_armed = false;
      m_lock_level = 0.0;
     }

   double              LastFloating(void) const { return(m_last_floating); }
   int                 CarryUsed(void)  const { return(m_carry_used); }
   bool                LockArmed(void)  const { return(m_lock_armed); }
   double              LockLevel(void)  const { return(m_lock_level); }
   double              LastScore(void)  const { return(m_last_score); }
   double              Peak(void)       const { return(m_peak); }
   double              Worst(void)      const { return(m_worst); }
   double              LastStop(void)   const { return(m_last_sl); }

   //--- tick driver: tracks the floating curve, applies #2 and #3.
   //--- returns true when the caller must close the position now.
   bool                OnTick(const double current_sl,ENUM_EXIT_REASON &reason)
     {
      reason = EXIT_H1;
      if(m_ticket==0)
         return(false);

      const double cur = FloatingPoints();
      m_last_floating = cur;
      if(cur>m_peak)
         m_peak = cur;
      if(cur<m_worst)
         m_worst = cur;
      m_last_sl = current_sl;

      const datetime bar_time = iTime(m_set.symbol_name,m_set.break_even_timeframe,0);
      if(bar_time>0 && bar_time!=m_last_be_bar)
        {
         m_last_be_bar = bar_time;
         m_be_bars++;
        }
      m_last_score = m_momentum.Score(m_side);

      //--- priority #2: profit lock
      if(m_set.profit_lock_enabled)
        {
         if(!m_lock_armed && m_peak>=m_set.profit_lock_trigger_points)
           {
            m_lock_armed = true;
            m_lock_level = m_peak*m_set.profit_lock_percent/100.0;
            m_log.Exit(StringFormat("Profit Lock armed | peak %.0f pts | locked level %.0f pts",
                                      m_peak,m_lock_level));
           }
         if(m_lock_armed && cur<=m_lock_level)
           {
            m_log.Exit(StringFormat("Profit Lock hit | current %.0f pts <= locked %.0f pts (peak %.0f pts)",
                                      cur,m_lock_level,m_peak));
            reason = EXIT_PROFIT_LOCK;
            return(true);
           }
        }

      //--- priority #3: momentum exit, needs a few bars of evidence
      if(m_set.momentum_exit_enabled && m_be_bars>=EXIT_MIN_EVIDENCE_BARS &&
         m_last_score<m_set.momentum_sensitivity)
        {
         m_log.Momentum(StringFormat("Momentum Exit | score %.0f < sensitivity %.0f",
                                   m_last_score,m_set.momentum_sensitivity));
         reason = EXIT_MOMENTUM;
         return(true);
        }
      return(false);
     }

   //--- candle close: may the strong profitable trade survive one more candle?
   bool                TryCarry(void)
     {
      if(!m_set.carry_enabled || m_ticket==0)
         return(false);
      if(m_carry_used>=m_set.carry_max_candles)
         return(false);
      const double cur = FloatingPoints();
      m_last_score = m_momentum.Score(m_side);
      if(cur<=0.0 || m_last_score<m_set.carry_min_trend_strength)
         return(false);

      m_carry_used++;
      m_log.Exit(StringFormat("Carry Activated | profit %.0f pts | momentum %.0f >= %.0f | extra candle %d/%d",
                                cur,m_last_score,m_set.carry_min_trend_strength,
                                m_carry_used,m_set.carry_max_candles));
      return(true);
     }

   //--- reason of the mandatory flatten at the candle close
   ENUM_EXIT_REASON    CandleCloseReason(void) const
     {
      return((m_carry_used>0) ? EXIT_CARRY : EXIT_H1);
     }

   //--- data for CSV / statistics / dashboard
   void                Snapshot(SExitSnapshot &snap) const
     {
      snap.max_profit_points = m_peak;
      snap.max_loss_points   = m_worst;
      snap.profit_locked     = (m_lock_armed ? m_lock_level : 0.0);
      snap.carry_used        = m_carry_used;
      snap.momentum          = m_last_score;
     }
  };

#endif // __EA_EXIT_ENGINE_MQH__
//+------------------------------------------------------------------+
