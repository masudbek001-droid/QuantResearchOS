//+------------------------------------------------------------------+
//|                                                      EAUtils.mqh |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Static helpers shared by all managers     |
//+------------------------------------------------------------------+
#ifndef __EA_UTILS_MQH__
#define __EA_UTILS_MQH__

#include <CandleBreakoutEA\EASettings.mqh>

//+------------------------------------------------------------------+
//| Stateless utility functions. Everything is symbol aware and      |
//| every price/lot value returned here is already normalized.       |
//+------------------------------------------------------------------+
class CEAUtils
  {
public:
   //--- price / volume normalization
   static double         PriceStep(const string symbol);
   static double         NormalizePrice(const string symbol,const double price);
   static double         VolumeStep(const string symbol);
   static double         NormalizeVolume(const string symbol,const double volume);
   static double         ClampVolume(const string symbol,const double volume);
   //--- market data
   static double         Ask(const string symbol);
   static double         Bid(const string symbol);
   static double         SpreadPoints(const string symbol);
   static long           StopsLevelPoints(const string symbol);
   static long           FreezeLevelPoints(const string symbol);
   static double         MinStopsDistance(const string symbol);
   static double         PointValue(const string symbol);
   static double         TickValuePerLot(const string symbol);
   //--- time helpers
   static datetime       BarCloseTime(const string symbol,const ENUM_TIMEFRAMES timeframe,const int shift);
   static datetime       DayStart(const datetime moment);
   //--- order sanity checks
   static bool           IsValidPendingPrice(const string symbol,const ENUM_ORDER_TYPE type,const double price);
   static ENUM_ORDER_TYPE_FILLING FillingMode(const string symbol);
   static bool           ExpirationSupported(const string symbol);
   static datetime       EffectiveExpiration(const string symbol,const datetime candle_close);
   //--- formatting
   static string         DoubleToStr(const double value,const int digits);
  };

//+------------------------------------------------------------------+
double CEAUtils::PriceStep(const string symbol)
  {
   const double step = SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   return((step>0.0) ? step : SymbolInfoDouble(symbol,SYMBOL_POINT));
  }
//+------------------------------------------------------------------+
double CEAUtils::NormalizePrice(const string symbol,const double price)
  {
   const double step = PriceStep(symbol);
   if(step<=0.0)
      return(NormalizeDouble(price,(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS)));
   const double rounded = MathRound(price/step)*step;
   return(NormalizeDouble(rounded,(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS)));
  }
//+------------------------------------------------------------------+
double CEAUtils::VolumeStep(const string symbol)
  {
   const double step = SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   return((step>0.0) ? step : 0.01);
  }
//+------------------------------------------------------------------+
double CEAUtils::NormalizeVolume(const string symbol,const double volume)
  {
   const double step = VolumeStep(symbol);
   return(NormalizeDouble(MathFloor(volume/step+0.5)*step,2));
  }
//+------------------------------------------------------------------+
//| Round to the lot step and clamp into the broker min/max range    |
//+------------------------------------------------------------------+
double CEAUtils::ClampVolume(const string symbol,const double volume)
  {
   double result = NormalizeVolume(symbol,volume);
   const double min_lot = SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   const double max_lot = SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   if(min_lot>0.0 && result<min_lot)
      result = min_lot;
   if(max_lot>0.0 && result>max_lot)
      result = max_lot;
   return(NormalizeVolume(symbol,result));
  }
//+------------------------------------------------------------------+
double CEAUtils::Ask(const string symbol)
  {
   double price = SymbolInfoDouble(symbol,SYMBOL_ASK);
   if(price<=0.0)
     {
      MqlTick tick;
      if(SymbolInfoTick(symbol,tick))
         price = tick.ask;
     }
   return(price);
  }
//+------------------------------------------------------------------+
double CEAUtils::Bid(const string symbol)
  {
   double price = SymbolInfoDouble(symbol,SYMBOL_BID);
   if(price<=0.0)
     {
      MqlTick tick;
      if(SymbolInfoTick(symbol,tick))
         price = tick.bid;
     }
   return(price);
  }
//+------------------------------------------------------------------+
double CEAUtils::SpreadPoints(const string symbol)
  {
   const double point = SymbolInfoDouble(symbol,SYMBOL_POINT);
   if(point<=0.0)
      return(0.0);
   return((SymbolInfoDouble(symbol,SYMBOL_ASK)-SymbolInfoDouble(symbol,SYMBOL_BID))/point);
  }
//+------------------------------------------------------------------+
long CEAUtils::StopsLevelPoints(const string symbol)
  {
   return(SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL));
  }
//+------------------------------------------------------------------+
long CEAUtils::FreezeLevelPoints(const string symbol)
  {
   return(SymbolInfoInteger(symbol,SYMBOL_TRADE_FREEZE_LEVEL));
  }
//+------------------------------------------------------------------+
//| Broker minimum distance (in price units) for stops and pendings  |
//+------------------------------------------------------------------+
double CEAUtils::MinStopsDistance(const string symbol)
  {
   const double point = SymbolInfoDouble(symbol,SYMBOL_POINT);
   long stops = StopsLevelPoints(symbol);
   if(stops<=0)
      stops = 1;                       // never work with a zero distance
   return((double)stops*point);
  }
//+------------------------------------------------------------------+
double CEAUtils::PointValue(const string symbol)
  {
   return(SymbolInfoDouble(symbol,SYMBOL_POINT));
  }
//+------------------------------------------------------------------+
//| Money lost per 1.00 lot for a 1 point adverse move               |
//+------------------------------------------------------------------+
double CEAUtils::TickValuePerLot(const string symbol)
  {
   const double tick_value = SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE);
   const double tick_size  = SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   const double point      = SymbolInfoDouble(symbol,SYMBOL_POINT);
   if(tick_value<=0.0 || tick_size<=0.0 || point<=0.0)
      return(0.0);
   return(tick_value*point/tick_size);
  }
//+------------------------------------------------------------------+
//| Closing moment of the bar that currently has index "shift"       |
//+------------------------------------------------------------------+
datetime CEAUtils::BarCloseTime(const string symbol,const ENUM_TIMEFRAMES timeframe,const int shift)
  {
   const datetime open_time = iTime(symbol,timeframe,shift);
   if(open_time<=0)
      return(0);
   return(open_time+PeriodSeconds(timeframe));
  }
//+------------------------------------------------------------------+
datetime CEAUtils::DayStart(const datetime moment)
  {
   MqlDateTime stamp;
   TimeToStruct(moment,stamp);
   stamp.hour = 0;
   stamp.min  = 0;
   stamp.sec  = 0;
   return(StructToTime(stamp));
  }
//+------------------------------------------------------------------+
//| Pending order price must respect the broker stops level          |
//+------------------------------------------------------------------+
bool CEAUtils::IsValidPendingPrice(const string symbol,const ENUM_ORDER_TYPE type,const double price)
  {
   const double distance = MinStopsDistance(symbol);
   switch(type)
     {
      case ORDER_TYPE_BUY_STOP:
         return(price >= Ask(symbol)+distance);
      case ORDER_TYPE_SELL_STOP:
         return(price <= Bid(symbol)-distance);
      case ORDER_TYPE_BUY_LIMIT:
         return(price <= Bid(symbol)-distance);
      case ORDER_TYPE_SELL_LIMIT:
         return(price >= Ask(symbol)+distance);
      default:
         break;
     }
   return(false);
  }
//+------------------------------------------------------------------+
//| Pick the first filling policy the symbol actually supports       |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING CEAUtils::FillingMode(const string symbol)
  {
   const long filling = SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK)
      return(ORDER_FILLING_FOK);
   if((filling & SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC)
      return(ORDER_FILLING_IOC);
   return(ORDER_FILLING_RETURN);
  }
//+------------------------------------------------------------------+
bool CEAUtils::ExpirationSupported(const string symbol)
  {
   const long expiration = SymbolInfoInteger(symbol,SYMBOL_EXPIRATION_MODE);
   return(((expiration & SYMBOL_EXPIRATION_TIME)==SYMBOL_EXPIRATION_TIME) ||
          ((expiration & SYMBOL_EXPIRATION_DAY)==SYMBOL_EXPIRATION_DAY));
  }
//+------------------------------------------------------------------+
//| Broker supported expiration, or 0 when the EA deletes manually   |
//+------------------------------------------------------------------+
datetime CEAUtils::EffectiveExpiration(const string symbol,const datetime candle_close)
  {
   if(candle_close<=0 || !ExpirationSupported(symbol))
      return(0);
   //--- brokers reject expirations that are only seconds away
   if(candle_close-TimeCurrent()<120)
      return(0);
   return(candle_close);
  }
//+------------------------------------------------------------------+
string CEAUtils::DoubleToStr(const double value,const int digits)
  {
   return(DoubleToString(value,digits));
  }
#endif // __EA_UTILS_MQH__
//+------------------------------------------------------------------+
