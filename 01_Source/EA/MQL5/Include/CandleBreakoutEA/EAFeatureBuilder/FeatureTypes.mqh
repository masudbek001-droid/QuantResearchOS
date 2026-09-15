//+------------------------------------------------------------------+
//|                          EAFeatureBuilder/FeatureTypes.mqh       |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Feature Builder: shared types             |
//+------------------------------------------------------------------+
#ifndef __EA_FB_TYPES_MQH__
#define __EA_FB_TYPES_MQH__

//+------------------------------------------------------------------+
//| Observation windows and session borders (server clock).          |
//| Analysis constants, not user inputs.                             |
//+------------------------------------------------------------------+
const int    FB_ATR_PERIOD      = 14;   // completed bars averaged for ATR
const int    FB_TREND_PERIOD    = 10;   // completed bars behind the trend read
const int    FB_ASIA_END_HOUR   = 8;    // 00:00-07:59
const int    FB_LONDON_END_HOUR = 15;   // 08:00-14:59
const int    FB_MIN_BARS        = 2*FB_ATR_PERIOD+2; // series depth required

enum ENUM_FB_SESSION
  {
   FB_SESSION_ASIA    = 0,
   FB_SESSION_LONDON  = 1,
   FB_SESSION_NEWYORK = 2
  };

enum ENUM_FB_TREND
  {
   FB_TREND_DOWN = -1,
   FB_TREND_FLAT =  0,
   FB_TREND_UP   =  1
  };

//+------------------------------------------------------------------+
//| Result of the last Update/Validate pass                          |
//+------------------------------------------------------------------+
enum ENUM_FB_STATUS
  {
   FB_OK                  = 0, // snapshot is valid
   FB_ERR_MISSING_RATES   = 1, // not enough bars on the symbol/timeframe
   FB_ERR_INVALID_CANDLE  = 2, // last completed bar is inconsistent
   FB_ERR_NEGATIVE_ATR    = 3,
   FB_ERR_NEGATIVE_SPREAD = 4,
   FB_ERR_NON_FINITE      = 5  // NaN or Infinity in a derived feature
  };

//+------------------------------------------------------------------+
string FbStatusToString(const ENUM_FB_STATUS status)
  {
   switch(status)
     {
      case FB_OK:                  return("OK");
      case FB_ERR_MISSING_RATES:   return("missing rates");
      case FB_ERR_INVALID_CANDLE:  return("invalid candle");
      case FB_ERR_NEGATIVE_ATR:    return("negative ATR");
      case FB_ERR_NEGATIVE_SPREAD: return("negative spread");
      case FB_ERR_NON_FINITE:      return("non-finite value");
     }
   return("unknown");
  }

#endif // __EA_FB_TYPES_MQH__
//+------------------------------------------------------------------+
