//+------------------------------------------------------------------+
//|                                         EAContext/EAContextMarket.mqh|
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Context Layer: market snapshot            |
//+------------------------------------------------------------------+
#ifndef __EA_CTX_MARKET_MQH__
#define __EA_CTX_MARKET_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EAUtils.mqh>

//--- observation windows and session borders (server clock)
const int    CTX_ATR_PERIOD     = 14;   // completed bars averaged for ATR
const int    CTX_TREND_PERIOD   = 10;   // completed bars behind the trend read
const int    CTX_ASIA_END_HOUR  = 8;    // 00:00-07:59 server time
const int    CTX_LONDON_END_HOUR= 15;   // 08:00-14:59 server time

enum ENUM_CTX_SESSION
  {
   CTX_SESSION_ASIA     = 0,
   CTX_SESSION_LONDON   = 1,
   CTX_SESSION_NEWYORK  = 2
  };

enum ENUM_CTX_TREND
  {
   CTX_TREND_DOWN = -1,
   CTX_TREND_FLAT =  0,
   CTX_TREND_UP   =  1
  };

//+------------------------------------------------------------------+
//| Read-only snapshot of the market on the main timeframe. All bar  |
//| values describe COMPLETED bars; the forming bar is never used.   |
//| Cached per main-TF bar: repeated Update calls inside the same    |
//| bar are free. No business logic.                                 |
//+------------------------------------------------------------------+
class CMarketContext
  {
private:
   const CEASettings  *m_set;
   datetime            m_cache_bar;

   double              BarHigh(const int i)  const { return(iHigh(m_set.symbol_name,m_set.main_timeframe,i)); }
   double              BarLow(const int i)   const { return(iLow (m_set.symbol_name,m_set.main_timeframe,i)); }
   double              BarClose(const int i) const { return(iClose(m_set.symbol_name,m_set.main_timeframe,i)); }
   double              BarOpen(const int i)  const { return(iOpen(m_set.symbol_name,m_set.main_timeframe,i)); }

   double              TrueRange(const int i) const
     {
      const double h  = BarHigh(i), l = BarLow(i), pc = BarClose(i+1);
      return(MathMax(h-l,MathMax(MathAbs(h-pc),MathAbs(l-pc))));
     }

public:
   double              CurrentSpread;    // points
   double              CurrentATR;       // price units, completed bars
   double              PreviousRange;    // bar[2] high-low
   double              CurrentRange;     // bar[1] high-low
   double              UpperShadow;      // bar[1]
   double              LowerShadow;      // bar[1]
   double              BodySize;         // bar[1] |close-open|
   double              BodyPercent;      // bar[1] body/range * 100
   double              Volatility;       // ATR expressed in points
   ENUM_CTX_TREND      TrendDirection;
   double              TrendStrength;    // 0..100 share of bars in trend direction
   ENUM_CTX_SESSION    CurrentSession;
   int                 CurrentHour;
   int                 Weekday;
   int                 Month;
   int                 Quarter;
   int                 BrokerOffset;     // hours, TimeCurrent - TimeGMT
   bool                DSTFlag;          // placeholder: needs a broker profile (ADR)
   bool                HolidayFlag;      // placeholder: needs an external calendar
   bool                NewsFlag;         // placeholder: needs an external feed

                       CMarketContext(void) : m_set(NULL), m_cache_bar(0) { Reset(); }

   void                Init(const CEASettings &settings)
     {
      m_set       = &settings;
      m_cache_bar = 0;
      Reset();
     }

   void                Reset(void)
     {
      CurrentSpread  = 0.0;
      CurrentATR     = 0.0;
      PreviousRange  = 0.0;
      CurrentRange   = 0.0;
      UpperShadow    = 0.0;
      LowerShadow    = 0.0;
      BodySize       = 0.0;
      BodyPercent    = 0.0;
      Volatility     = 0.0;
      TrendDirection = CTX_TREND_FLAT;
      TrendStrength  = 0.0;
      CurrentSession = CTX_SESSION_ASIA;
      CurrentHour    = 0;
      Weekday        = 0;
      Month          = 0;
      Quarter        = 0;
      BrokerOffset   = 0;
      DSTFlag        = false;
      HolidayFlag    = false;
      NewsFlag       = false;
     }

   //--- cheap inside a bar, one series pass per completed bar
   void                Update(void)
     {
      if(m_set==NULL)
         return;

      //--- clock fields are always fresh
      MqlDateTime stamp;
      TimeToStruct(TimeCurrent(),stamp);
      CurrentHour  = stamp.hour;
      Weekday      = stamp.day_of_week;
      Month        = stamp.mon;
      Quarter      = (stamp.mon-1)/3+1;
      CurrentSession = (CurrentHour<CTX_ASIA_END_HOUR ? CTX_SESSION_ASIA
                        : (CurrentHour<CTX_LONDON_END_HOUR ? CTX_SESSION_LONDON
                        : CTX_SESSION_NEWYORK));
      BrokerOffset = (int)MathRound((double)(TimeCurrent()-TimeGMT())/3600.0);

      CurrentSpread = CEAUtils::SpreadPoints(m_set.symbol_name);

      //--- bar derived fields, once per completed main-TF bar
      const datetime bar = iTime(m_set.symbol_name,m_set.main_timeframe,0);
      if(bar<=0 || bar==m_cache_bar)
         return;
      m_cache_bar = bar;

      if(Bars(m_set.symbol_name,m_set.main_timeframe)<CTX_ATR_PERIOD+2)
         return;

      double atr = 0.0;
      for(int i=1; i<=CTX_ATR_PERIOD; i++)
         atr += TrueRange(i);
      CurrentATR = atr/CTX_ATR_PERIOD;
      const double point = CEAUtils::PointValue(m_set.symbol_name);
      Volatility = (point>0.0 ? CurrentATR/point : 0.0);

      PreviousRange = BarHigh(2)-BarLow(2);
      CurrentRange  = BarHigh(1)-BarLow(1);
      UpperShadow   = BarHigh(1)-MathMax(BarOpen(1),BarClose(1));
      LowerShadow   = MathMin(BarOpen(1),BarClose(1))-BarLow(1);
      BodySize      = MathAbs(BarClose(1)-BarOpen(1));
      BodyPercent   = (CurrentRange>0.0 ? 100.0*BodySize/CurrentRange : 0.0);

      //--- trend read over the last completed bars
      int up = 0, down = 0;
      for(int i=1; i<=CTX_TREND_PERIOD; i++)
        {
         if(BarClose(i)>BarOpen(i))
            up++;
         else
            if(BarClose(i)<BarOpen(i))
               down++;
        }
      TrendDirection = (up>down ? CTX_TREND_UP : (down>up ? CTX_TREND_DOWN : CTX_TREND_FLAT));
      TrendStrength  = 100.0*(double)MathMax(up,down)/CTX_TREND_PERIOD;
     }

   bool                Validate(void) const
     {
      return(CurrentSpread>=0.0 && CurrentATR>=0.0 && BodyPercent>=0.0 &&
             BodyPercent<=100.0 && TrendStrength>=0.0 && TrendStrength<=100.0 &&
             CurrentHour>=0 && CurrentHour<=23);
     }

   string              ToString(void) const
     {
      return(StringFormat("market: spread %.0f pts | ATR %.5f | body %.0f%% | trend %d (%.0f) | %s h%02d",
                          CurrentSpread,CurrentATR,BodyPercent,(int)TrendDirection,
                          TrendStrength,EnumToString(CurrentSession),CurrentHour));
     }

   bool                Serialize(string &out) const
     {
      out = "";
      return(false);   // stub: persistence arrives with the database ADR
     }
  };

#endif // __EA_CTX_MARKET_MQH__
//+------------------------------------------------------------------+
