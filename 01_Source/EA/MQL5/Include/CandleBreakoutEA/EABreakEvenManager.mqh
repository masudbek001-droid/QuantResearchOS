//+------------------------------------------------------------------+
//|                                             EABreakEvenManager.mqh|
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        M5 swing based stop trailing              |
//+------------------------------------------------------------------+
#ifndef __EA_BREAK_EVEN_MANAGER_MQH__
#define __EA_BREAK_EVEN_MANAGER_MQH__

#include <Trade\Trade.mqh>
#include <CandleBreakoutEA\EAUtils.mqh>
#include <CandleBreakoutEA\EALogger.mqh>

//+------------------------------------------------------------------+
//| After the position is open the EA switches to the M5 timeframe.  |
//| Every N completed M5 bars the stop is moved behind the latest    |
//| confirmed swing. Nothing else is done here.                      |
//+------------------------------------------------------------------+
class CBreakEvenManager
  {
private:
   const CEASettings  *m_set;
   CLogger            *m_log;
   CTrade              m_trade;

   datetime            m_last_bar_time;   // last M5 bar already processed
   datetime            m_entry_time;      // open time of the running position
   int                 m_bars_since_open; // completed M5 bars while in trade
   double              m_last_stop;       // last SL we pushed, avoids spam
   ulong               m_ticket;

   //--- open time of the bar at "shift" on the break even timeframe
   datetime            BeBarTime(const int shift) const
     {
      return(iTime(m_set.symbol_name,m_set.break_even_timeframe,shift));
     }

   //--- newest confirmed swing low that formed after "since"
   bool                LatestSwingLow(const datetime since,double &price) const
     {
      const int span = m_set.swing_bars;
      const int bars = Bars(m_set.symbol_name,m_set.break_even_timeframe);
      const int last = bars-span-2;
      for(int i=span; i<=last; i++)
        {
         const datetime swing_time = BeBarTime(i);
         if(swing_time<=0 || swing_time<=since)
            break;                       // bars are scanned newest first

         const double candidate = iLow(m_set.symbol_name,m_set.break_even_timeframe,i);
         bool is_swing = true;
         for(int k=1; k<=span && is_swing; k++)
           {
            if(candidate > iLow(m_set.symbol_name,m_set.break_even_timeframe,i-k) ||
               candidate > iLow(m_set.symbol_name,m_set.break_even_timeframe,i+k))
               is_swing = false;
           }
         if(is_swing)
           {
            price = candidate;
            return(true);
           }
        }
      return(false);
     }

   //--- newest confirmed swing high that formed after "since"
   bool                LatestSwingHigh(const datetime since,double &price) const
     {
      const int span = m_set.swing_bars;
      const int bars = Bars(m_set.symbol_name,m_set.break_even_timeframe);
      const int last = bars-span-2;
      for(int i=span; i<=last; i++)
        {
         const datetime swing_time = BeBarTime(i);
         if(swing_time<=0 || swing_time<=since)
            break;

         const double candidate = iHigh(m_set.symbol_name,m_set.break_even_timeframe,i);
         bool is_swing = true;
         for(int k=1; k<=span && is_swing; k++)
           {
            if(candidate < iHigh(m_set.symbol_name,m_set.break_even_timeframe,i-k) ||
               candidate < iHigh(m_set.symbol_name,m_set.break_even_timeframe,i+k))
               is_swing = false;
           }
         if(is_swing)
           {
            price = candidate;
            return(true);
           }
        }
      return(false);
     }

public:
                       CBreakEvenManager(void) : m_set(NULL), m_log(NULL), m_last_bar_time(0),
                                                 m_entry_time(0), m_bars_since_open(0),
                                                 m_last_stop(0.0), m_ticket(0) {}

   void                Init(const CEASettings &settings,CLogger &logger)
     {
      m_set = &settings;
      m_log = &logger;
      m_trade.SetExpertMagicNumber(m_set.magic);
      m_trade.SetDeviationInPoints(30);
      m_trade.SetTypeFilling(CEAUtils::FillingMode(m_set.symbol_name));
     }

   //--- called when a fresh position appears
   void                Start(const ulong ticket,const datetime position_time)
     {
      m_ticket          = ticket;
      m_last_bar_time   = BeBarTime(0);           // the M5 bar that is forming now
      m_entry_time      = (position_time>0 ? position_time : TimeCurrent());
      m_bars_since_open = 0;
      m_last_stop       = 0.0;
      m_log.Debug(StringFormat("BreakEven armed | position #%I64u | opened %s | M5 baseline %s",
                               ticket,
                               TimeToString(m_entry_time,TIME_DATE|TIME_MINUTES),
                               TimeToString(m_last_bar_time,TIME_DATE|TIME_MINUTES)));
     }

   void                Reset(void)
     {
      m_ticket          = 0;
      m_last_bar_time   = 0;
      m_entry_time      = 0;
      m_bars_since_open = 0;
      m_last_stop       = 0.0;
     }

   bool                IsActive(void) const
     {
      return(m_ticket!=0);
     }

   //--- true once the trail has actually placed a stop in the market
   bool                HadStop(void) const
     {
      return(m_last_stop>0.0);
     }

   //--- tick driver: counts completed M5 bars and applies the rule
   void                OnTick(const ulong ticket,const ENUM_POSITION_TYPE type,
                              const datetime position_time,const double entry_price,
                              const double current_sl,const double current_tp)
     {
      if(!m_set.break_even_enabled || ticket==0)
         return;

      if(ticket!=m_ticket)
         Start(ticket,position_time);

      const datetime bar_time = BeBarTime(0);
      if(bar_time<=0)
         return;
      if(bar_time==m_last_bar_time)
         return;                          // no new M5 bar completed yet

      m_last_bar_time = bar_time;
      m_bars_since_open++;

      const int step = (m_set.break_even_every_bars>0 ? m_set.break_even_every_bars : 2);
      if(m_bars_since_open % step!=0)
        {
         m_log.Debug(StringFormat("BreakEven waiting | completed M5 bars = %d (update every %d)",
                                  m_bars_since_open,step));
         return;
        }
      Update(ticket,type,entry_price,current_sl,current_tp);
     }

   //--- the actual stop move, small and explicit
   void                Update(const ulong ticket,const ENUM_POSITION_TYPE type,
                              const double entry_price,const double current_sl,const double current_tp)
     {
      const string symbol = m_set.symbol_name;
      const int    digits = (int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
      const double point   = CEAUtils::PointValue(symbol);
      const double buffer  = m_set.break_even_buffer_points*point;
      const double spread  = CEAUtils::SpreadPoints(symbol)*point;

      double swing_price = 0.0;
      double new_stop    = 0.0;
      bool   found       = false;

      if(type==POSITION_TYPE_BUY)
        {
         found    = LatestSwingLow(m_entry_time,swing_price);
         new_stop = swing_price-buffer;
         //--- only a stop that already locks profit is allowed
         if(!found || new_stop <= entry_price+spread+buffer)
           {
            m_log.Debug("BreakEven skipped | no profitable swing low confirmed yet");
            return;
           }
        }
      else
        {
         found    = LatestSwingHigh(m_entry_time,swing_price);
         new_stop = swing_price+buffer;
         if(!found || new_stop >= entry_price-spread-buffer)
           {
            m_log.Debug("BreakEven skipped | no profitable swing high confirmed yet");
            return;
           }
        }

      new_stop = CEAUtils::NormalizePrice(symbol,new_stop);

      //--- the stop may only move forward, never back against the trade
      if(current_sl>0.0)
        {
         const bool backwards = (type==POSITION_TYPE_BUY ? (new_stop<=current_sl) : (new_stop>=current_sl));
         if(backwards)
           {
            m_log.Debug(StringFormat("BreakEven kept | %s is better than %s",
                                     CEAUtils::DoubleToStr(current_sl,digits),
                                     CEAUtils::DoubleToStr(new_stop,digits)));
            return;
           }
        }

      //--- never place a stop closer than the broker minimum distance
      const double market  = (type==POSITION_TYPE_BUY ? CEAUtils::Bid(symbol) : CEAUtils::Ask(symbol));
      const double minimum = CEAUtils::MinStopsDistance(symbol);
      const bool too_close = (type==POSITION_TYPE_BUY ? (market-new_stop<minimum) : (new_stop-market<minimum));
      if(too_close)
        {
         m_log.Debug("BreakEven skipped | swing is inside the broker stops level");
         return;
      }

      if(MathAbs(new_stop-m_last_stop)<point*0.5)
         return;                          // nothing meaningfully changed

      if(!m_trade.PositionModify(ticket,new_stop,current_tp))
        {
         m_log.Error(StringFormat("BreakEven modify failed | #%I64u | %s",ticket,m_trade.ResultRetcodeDescription()));
         return;
        }

      m_last_stop = new_stop;
      m_log.BreakEven(StringFormat("BreakEven Updated | #%I64u | SL %s -> %s | swing %s | M5 bars %d",
                               ticket,
                               (current_sl>0.0 ? CEAUtils::DoubleToStr(current_sl,digits) : "none"),
                               CEAUtils::DoubleToStr(new_stop,digits),
                               CEAUtils::DoubleToStr(swing_price,digits),
                               m_bars_since_open));
     }
  };

#endif // __EA_BREAK_EVEN_MANAGER_MQH__
//+------------------------------------------------------------------+
