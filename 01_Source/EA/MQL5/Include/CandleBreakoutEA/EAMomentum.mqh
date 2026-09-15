//+------------------------------------------------------------------+
//|                                                    EAMomentum.mqh|
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Pure momentum measurement (no decisions)  |
//+------------------------------------------------------------------+
#ifndef __EA_MOMENTUM_MQH__
#define __EA_MOMENTUM_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EAUtils.mqh>

//+------------------------------------------------------------------+
//| Internal scoring weights (analysis constants, not user inputs)   |
//+------------------------------------------------------------------+
const int    MOMENTUM_LOOKBACK_BARS    = 3;     // completed M5 bars analysed
const double MOMENTUM_DIRECTION_WEIGHT = 100.0; // full body in trade direction
const double MOMENTUM_WICK_WEIGHT      = 100.0; // opposite wick penalty
const double MOMENTUM_OPPOSITE_PENALTY = 30.0;  // two opposite candles
const double MOMENTUM_SMALLBODY_PENALTY= 15.0;  // last candle is a doji
const double MOMENTUM_SHRINK_PENALTY   = 15.0;  // three shrinking bodies
const double MOMENTUM_SMALLBODY_RATIO  = 0.25;  // body/range below this = small

//+------------------------------------------------------------------+
//| Measures how strong the current move still is, in the direction  |
//| of the open position. Returns 0..100, higher = stronger trend.   |
//| The class only measures; it never places or closes anything.     |
//+------------------------------------------------------------------+
class CMomentumAnalyzer
  {
private:
   const CEASettings  *m_set;

   //--- the score depends only on COMPLETED bars, so it is recomputed
   //--- once per break-even bar and served from cache on every tick
   datetime            m_cache_time;
   ENUM_POSITION_TYPE  m_cache_side;
   double              m_cache_score;

   double              Open(const int shift)  const { return(iOpen (m_set.symbol_name,m_set.break_even_timeframe,shift)); }
   double              High(const int shift)  const { return(iHigh (m_set.symbol_name,m_set.break_even_timeframe,shift)); }
   double              Low(const int shift)   const { return(iLow  (m_set.symbol_name,m_set.break_even_timeframe,shift)); }
   double              Close(const int shift) const { return(iClose(m_set.symbol_name,m_set.break_even_timeframe,shift)); }

   double              Body(const int shift) const
     {
      return(MathAbs(Close(shift)-Open(shift)));
     }

   double              Range(const int shift) const
     {
      const double range = High(shift)-Low(shift);
      return((range>0.0) ? range : CEAUtils::PointValue(m_set.symbol_name));
     }

   //--- one completed bar scored from the position's point of view
   double              CandleScore(const int shift,const ENUM_POSITION_TYPE side) const
     {
      const double o = Open(shift), c = Close(shift), h = High(shift), l = Low(shift);
      const double range = Range(shift);
      const double body  = MathAbs(c-o);
      const bool   bull  = (c>=o);
      const bool   match = (side==POSITION_TYPE_BUY ? bull : !bull);

      //--- the wick that points against the position
      const double opp_wick = (side==POSITION_TYPE_BUY ? h-MathMax(o,c)
                                                       : MathMin(o,c)-l);

      double score = (match ? 1.0 : -1.0)*MOMENTUM_DIRECTION_WEIGHT*(body/range);
      score -= MOMENTUM_WICK_WEIGHT*(opp_wick/range);
      return(score);   // -200 .. +100
     }

public:
                       CMomentumAnalyzer(void) : m_set(NULL), m_cache_time(0),
                                                 m_cache_side(POSITION_TYPE_BUY), m_cache_score(50.0) {}

   void                Init(const CEASettings &settings)
     {
      m_set = &settings;
     }

   //--- 0..100, higher = momentum in the trade direction is still alive
   double              Score(const ENUM_POSITION_TYPE side)
     {
      if(m_set==NULL)
         return(50.0);

      const datetime bar_time = iTime(m_set.symbol_name,m_set.break_even_timeframe,0);
      if(bar_time>0 && bar_time==m_cache_time && side==m_cache_side)
         return(m_cache_score);

      double total = 0.0;
      for(int i=1; i<=MOMENTUM_LOOKBACK_BARS; i++)
         total += CandleScore(i,side);
      //--- map -200..+100 onto 0..100
      double score = (total/MOMENTUM_LOOKBACK_BARS - (-2.0*MOMENTUM_DIRECTION_WEIGHT))
                     / (3.0*MOMENTUM_DIRECTION_WEIGHT)*100.0;

      //--- two consecutive candles against the trade
      const bool need_bull = (side==POSITION_TYPE_BUY);
      if((Close(1)>=Open(1))!=need_bull && (Close(2)>=Open(2))!=need_bull)
         score -= MOMENTUM_OPPOSITE_PENALTY;

      //--- the last completed bar is a small candle
      if(Body(1) < MOMENTUM_SMALLBODY_RATIO*Range(1))
         score -= MOMENTUM_SMALLBODY_PENALTY;

      //--- bodies shrinking for three bars
      if(Body(1)<Body(2) && Body(2)<Body(3))
         score -= MOMENTUM_SHRINK_PENALTY;

      if(score<0.0)
         score = 0.0;
      if(score>100.0)
         score = 100.0;

      m_cache_time  = bar_time;
      m_cache_side  = side;
      m_cache_score = score;
      return(score);
     }
  };

#endif // __EA_MOMENTUM_MQH__
//+------------------------------------------------------------------+
