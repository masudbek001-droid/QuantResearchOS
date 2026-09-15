//+------------------------------------------------------------------+
//|                                              EAPositionManager.mqh|
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Position inspection and closing           |
//+------------------------------------------------------------------+
#ifndef __EA_POSITION_MANAGER_MQH__
#define __EA_POSITION_MANAGER_MQH__

#include <Trade\Trade.mqh>
#include <CandleBreakoutEA\EAUtils.mqh>
#include <CandleBreakoutEA\EALogger.mqh>

//+------------------------------------------------------------------+
//| Thin wrapper around the positions of this EA (magic + symbol).   |
//+------------------------------------------------------------------+
class CPositionManager
  {
private:
   const CEASettings  *m_set;
   CLogger            *m_log;
   CTrade              m_trade;

   //--- index of the first position belonging to this EA, -1 when none
   int                 FindIndex(void) const
     {
      const int total = PositionsTotal();
      for(int i=0; i<total; i++)
        {
         const ulong ticket = PositionGetTicket(i);
         if(ticket==0)
            continue;
         if(PositionGetInteger(POSITION_MAGIC)!=(long)m_set.magic)
            continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_set.symbol_name)
            continue;
         return(i);
        }
      return(-1);
     }

public:
                       CPositionManager(void) : m_set(NULL), m_log(NULL) {}

   void                Init(const CEASettings &settings,CLogger &logger)
     {
      m_set = &settings;
      m_log = &logger;
      m_trade.SetExpertMagicNumber(m_set.magic);
      m_trade.SetDeviationInPoints(30);
      m_trade.SetTypeFilling(CEAUtils::FillingMode(m_set.symbol_name));
     }

   bool                HasPosition(void) const
     {
      return(FindIndex()>=0);
     }

   ulong               Ticket(void) const
     {
      const int index = FindIndex();
      return((index>=0) ? PositionGetTicket(index) : 0);
     }

   bool                Select(const ulong ticket) const
     {
      if(ticket==0)
         return(false);
      return(PositionSelectByTicket(ticket));
     }

   ENUM_POSITION_TYPE  Type(void) const
     {
      return((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE));
     }
   double              Lots(void) const
     {
      return(PositionGetDouble(POSITION_VOLUME));
     }
   double              EntryPrice(void) const
     {
      return(PositionGetDouble(POSITION_PRICE_OPEN));
     }
   double              StopLoss(void) const
     {
      return(PositionGetDouble(POSITION_SL));
     }
   double              TakeProfit(void) const
     {
      return(PositionGetDouble(POSITION_TP));
     }
   datetime            OpenTime(void) const
     {
      return((datetime)PositionGetInteger(POSITION_TIME));
     }
   double              CurrentProfit(void) const
     {
      return(PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP));
     }

   //--- close every position of this EA, returns the number closed
   int                 CloseAll(const string reason)
     {
      int closed = 0;
      int guard  = 0;
      while(HasPosition() && guard<10)
        {
         guard++;
         const ulong ticket = Ticket();
         if(ticket==0)
            break;
         if(!Select(ticket))
            break;

         const ENUM_POSITION_TYPE type  = Type();
         const double             lots  = Lots();
         const double             entry = EntryPrice();
         const double             sl    = StopLoss();
         const double             profit= CurrentProfit();

            if(!m_trade.PositionClose(ticket))
           {
            m_log.Error(StringFormat("Failed to close position #%I64u (%s)",ticket,m_trade.ResultRetcodeDescription()));
            break;
           }

         m_log.Exit(StringFormat("Trade Closed | #%I64u %s %.2f lots | entry %s | SL %s | profit %.2f | reason: %s",
                                  ticket,
                                  (type==POSITION_TYPE_BUY ? "BUY" : "SELL"),
                                  lots,
                                  CEAUtils::DoubleToStr(entry,(int)SymbolInfoInteger(m_set.symbol_name,SYMBOL_DIGITS)),
                                  (sl>0.0 ? CEAUtils::DoubleToStr(sl,(int)SymbolInfoInteger(m_set.symbol_name,SYMBOL_DIGITS)) : "none"),
                                  profit,
                                  reason));
         closed++;
        }
      return(closed);
     }
  };

#endif // __EA_POSITION_MANAGER_MQH__
//+------------------------------------------------------------------+
