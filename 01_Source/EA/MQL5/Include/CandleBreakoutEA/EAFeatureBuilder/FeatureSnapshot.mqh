//+------------------------------------------------------------------+
//|                         EAFeatureBuilder/FeatureSnapshot.mqh     |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Feature Builder: immutable snapshot       |
//+------------------------------------------------------------------+
#ifndef __EA_FB_SNAPSHOT_MQH__
#define __EA_FB_SNAPSHOT_MQH__

#include <CandleBreakoutEA\EAFeatureBuilder\FeatureTypes.mqh>

//+------------------------------------------------------------------+
//| One immutable market-feature snapshot. Only CFeatureBuilder fills |
//| it; consumers receive copies through GetSnapshot() and must treat |
//| the fields as read-only. All bar-derived values describe the last |
//| COMPLETED main-TF candle.                                         |
//+------------------------------------------------------------------+
struct SFeatureSnapshot
  {
   datetime            Timestamp;
   string              Symbol;
   ENUM_TIMEFRAMES     Timeframe;
   double              Spread;            // points
   double              ATR;               // price units
   double              ATRRatio;          // last completed range / ATR
   double              PreviousRange;     // bar[2] high-low
   double              CurrentRange;      // bar[1] high-low
   double              BodySize;          // bar[1] |close-open|
   double              BodyPercent;       // bar[1] body/range * 100
   double              UpperShadow;       // bar[1]
   double              LowerShadow;       // bar[1]
   double              UpperShadowRatio;  // upper shadow / range
   double              LowerShadowRatio;  // lower shadow / range
   bool                Bullish;           // bar[1] close > open
   bool                Bearish;           // bar[1] close < open
   double              Volatility;        // ATR in points
   ENUM_FB_TREND       TrendDirection;
   double              TrendStrength;     // 0..100 share of directional bars
   int                 CurrentHour;
   int                 Weekday;
   int                 Month;
   int                 Quarter;
   ENUM_FB_SESSION     Session;
   int                 BrokerOffset;      // hours, TimeCurrent - TimeGMT
   double              Reserved1;         // future features (ADR)
   double              Reserved2;
   double              Reserved3;
   long                Reserved4;

   void                Reset(void)
     {
      Timestamp         = 0;
      Symbol            = "";
      Timeframe         = PERIOD_CURRENT;
      Spread            = 0.0;
      ATR               = 0.0;
      ATRRatio          = 0.0;
      PreviousRange     = 0.0;
      CurrentRange      = 0.0;
      BodySize          = 0.0;
      BodyPercent       = 0.0;
      UpperShadow       = 0.0;
      LowerShadow       = 0.0;
      UpperShadowRatio  = 0.0;
      LowerShadowRatio  = 0.0;
      Bullish           = false;
      Bearish           = false;
      Volatility        = 0.0;
      TrendDirection    = FB_TREND_FLAT;
      TrendStrength     = 0.0;
      CurrentHour       = 0;
      Weekday           = 0;
      Month             = 0;
      Quarter           = 0;
      Session           = FB_SESSION_ASIA;
      BrokerOffset      = 0;
      Reserved1         = 0.0;
      Reserved2         = 0.0;
      Reserved3         = 0.0;
      Reserved4         = 0;
     }
  };

#endif // __EA_FB_SNAPSHOT_MQH__
//+------------------------------------------------------------------+
