//+------------------------------------------------------------------+
//|                        EAFeatureBuilder/FeatureValidation.mqh    |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Feature Builder: validation rules         |
//+------------------------------------------------------------------+
#ifndef __EA_FB_VALIDATION_MQH__
#define __EA_FB_VALIDATION_MQH__

#include <CandleBreakoutEA\EAFeatureBuilder\FeatureTypes.mqh>
#include <CandleBreakoutEA\EAFeatureBuilder\FeatureSnapshot.mqh>

//+------------------------------------------------------------------+
//| Stateless rule set. Rejects NaN, Infinity, negative ATR/spread,  |
//| inconsistent candles and missing series. No business logic.      |
//+------------------------------------------------------------------+
class CFeatureValidation
  {
public:
   static bool         IsFinite(const double value)
     {
      return(MathIsValidNumber(value));
     }

   //--- the last completed candle must be internally consistent
   static bool         IsValidCandle(const double open,const double high,
                                     const double low,const double close)
     {
      if(!IsFinite(open) || !IsFinite(high) || !IsFinite(low) || !IsFinite(close))
         return(false);
      if(high<low)
         return(false);
      if(open<low || open>high || close<low || close>high)
         return(false);
      return(high-low>0.0);
     }

   //--- first failing rule wins; FB_OK when everything holds
   static ENUM_FB_STATUS Validate(const SFeatureSnapshot &snap)
     {
      if(snap.Timestamp<=0 || StringLen(snap.Symbol)==0)
         return(FB_ERR_MISSING_RATES);
      if(!IsFinite(snap.Spread) || snap.Spread<0.0)
         return(FB_ERR_NEGATIVE_SPREAD);
      if(!IsFinite(snap.ATR) || snap.ATR<0.0)
         return(FB_ERR_NEGATIVE_ATR);
      if(!IsFinite(snap.CurrentRange) || snap.CurrentRange<=0.0)
         return(FB_ERR_INVALID_CANDLE);
      if(!IsFinite(snap.ATRRatio) || !IsFinite(snap.BodyPercent) ||
         !IsFinite(snap.UpperShadowRatio) || !IsFinite(snap.LowerShadowRatio) ||
         !IsFinite(snap.Volatility) || !IsFinite(snap.TrendStrength))
         return(FB_ERR_NON_FINITE);
      if(snap.BodyPercent<0.0 || snap.BodyPercent>100.0)
         return(FB_ERR_INVALID_CANDLE);
      if(snap.UpperShadow<0.0 || snap.LowerShadow<0.0 || snap.BodySize<0.0)
         return(FB_ERR_INVALID_CANDLE);
      if(snap.TrendStrength<0.0 || snap.TrendStrength>100.0)
         return(FB_ERR_NON_FINITE);
      return(FB_OK);
     }
  };

#endif // __EA_FB_VALIDATION_MQH__
//+------------------------------------------------------------------+
