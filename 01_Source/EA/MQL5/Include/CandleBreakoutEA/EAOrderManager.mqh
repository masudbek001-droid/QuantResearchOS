//+------------------------------------------------------------------+
//|                                                 EAOrderManager.mqh|
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Pending order placement and removal       |
//+------------------------------------------------------------------+
#ifndef __EA_ORDER_MANAGER_MQH__
#define __EA_ORDER_MANAGER_MQH__

#include <Trade\Trade.mqh>
#include <CandleBreakoutEA\EAUtils.mqh>
#include <CandleBreakoutEA\EALogger.mqh>

//+------------------------------------------------------------------+
//| Owns every pending order of this EA: create, find, modify, kill. |
//+------------------------------------------------------------------+
class COrderManager
  {
private:
   const CEASettings  *m_set;
   CLogger            *m_log;
   CTrade              m_trade;

   //--- single funnel for pending order creation
   bool                PlaceStopOrder(const ENUM_ORDER_TYPE type,const double price,
                                      const double volume,const datetime expiration,
                                      ulong &ticket)
     {
      //--- the strategy trades WITHOUT stop loss and take profit:
      //--- the only exit is the main timeframe candle close
      ticket = 0;
      const string symbol = m_set.symbol_name;
      const int    digits = (int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
      const string name   = (type==ORDER_TYPE_BUY_STOP ? "Buy Stop" : "Sell Stop");

      const double entry_price = CEAUtils::NormalizePrice(symbol,price);
      const double lot_volume  = CEAUtils::ClampVolume(symbol,volume);

      if(!CEAUtils::IsValidPendingPrice(symbol,type,entry_price))
        {
         m_log.Warn(StringFormat("%s skipped | price %s too close to the market (stops level %d points)",
                                 name,CEAUtils::DoubleToStr(entry_price,digits),(int)CEAUtils::StopsLevelPoints(symbol)));
         return(false);
        }
      const bool is_buy = (type==ORDER_TYPE_BUY_STOP);
      const ENUM_ORDER_TYPE_TIME lifetime = (expiration>0 ? ORDER_TIME_SPECIFIED : ORDER_TIME_GTC);
      bool sent = false;
      if(is_buy)
         sent = m_trade.BuyStop(lot_volume,entry_price,symbol,0.0,0.0,lifetime,expiration,m_set.trade_comment);
      else
         sent = m_trade.SellStop(lot_volume,entry_price,symbol,0.0,0.0,lifetime,expiration,m_set.trade_comment);

      if(!sent)
        {
         m_log.Error(StringFormat("%s send failed | %s (code %u)",
                                  name,m_trade.ResultRetcodeDescription(),m_trade.ResultRetcode()));
         return(false);
        }

      ticket = m_trade.ResultOrder();
      m_log.Debug(StringFormat("%s sent | ticket #%I64u | price %s | no SL | no TP | lots %.2f",
                               name,ticket,
                               CEAUtils::DoubleToStr(entry_price,digits),
                               lot_volume));
      return(true);
     }

public:
                       COrderManager(void) : m_set(NULL), m_log(NULL) {}

   void                Init(const CEASettings &settings,CLogger &logger)
     {
      m_set = &settings;
      m_log = &logger;
      m_trade.SetExpertMagicNumber(m_set.magic);
      m_trade.SetDeviationInPoints(30);
      m_trade.SetTypeFilling(CEAUtils::FillingMode(m_set.symbol_name));
     }

   //--- create a Buy Stop that expires together with the candle
   bool                PlaceBuyStop(const double price,const double volume,
                                    const datetime expiration,ulong &ticket)
     {
      return(PlaceStopOrder(ORDER_TYPE_BUY_STOP,price,volume,expiration,ticket));
     }

   //--- create a Sell Stop that expires together with the candle
   bool                PlaceSellStop(const double price,const double volume,
                                     const datetime expiration,ulong &ticket)
     {
      return(PlaceStopOrder(ORDER_TYPE_SELL_STOP,price,volume,expiration,ticket));
     }

   //--- ticket of the pending order of the given type, 0 when absent
   ulong               FindOrder(const ENUM_ORDER_TYPE type) const
     {
      const int total = OrdersTotal();
      for(int i=0; i<total; i++)
        {
         const ulong ticket = OrderGetTicket(i);
         if(ticket==0)
            continue;
         if(OrderGetInteger(ORDER_MAGIC)!=(long)m_set.magic)
            continue;
         if(OrderGetString(ORDER_SYMBOL)!=m_set.symbol_name)
            continue;
         if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE)!=type)
            continue;
         return(ticket);
        }
      return(0);
     }

   bool                HasOrder(const ENUM_ORDER_TYPE type) const
     {
      return(FindOrder(type)!=0);
     }

   int                 CountOrders(void) const
     {
      int count = 0;
      const int total = OrdersTotal();
      for(int i=0; i<total; i++)
        {
         const ulong ticket = OrderGetTicket(i);
         if(ticket==0)
            continue;
         if(OrderGetInteger(ORDER_MAGIC)!=(long)m_set.magic)
            continue;
         if(OrderGetString(ORDER_SYMBOL)!=m_set.symbol_name)
            continue;
         count++;
        }
      return(count);
     }

   //--- remove one pending order
   bool                DeleteOrder(const ulong ticket,const string reason)
     {
      if(ticket==0)
         return(false);
      if(!OrderSelect(ticket))
         return(false);
      if(!m_trade.OrderDelete(ticket))
        {
         m_log.Error(StringFormat("Pending Deleted failed | #%I64u | %s",ticket,m_trade.ResultRetcodeDescription()));
         return(false);
        }
      m_log.Trade(StringFormat("Pending Deleted | #%I64u | reason: %s",ticket,reason));
      return(true);
     }

   //--- remove the pending order of one type
   bool                DeleteByType(const ENUM_ORDER_TYPE type,const string reason)
     {
      return(DeleteOrder(FindOrder(type),reason));
     }

   //--- remove every pending order of this EA
   int                 DeleteAll(const string reason)
     {
      int removed = 0;
      int guard   = 0;
      while(CountOrders()>0 && guard<10)
        {
         guard++;
         const ulong ticket = FindOrder(ORDER_TYPE_BUY_STOP);
         const ulong any    = (ticket!=0 ? ticket : FindOrder(ORDER_TYPE_SELL_STOP));
         if(any==0)
            break;
         if(DeleteOrder(any,reason))
            removed++;
         else
            break;
        }
      return(removed);
     }
  };

#endif // __EA_ORDER_MANAGER_MQH__
//+------------------------------------------------------------------+
