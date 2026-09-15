//+------------------------------------------------------------------+
//|                                                EATradeHistory.mqh|
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Account history aggregation               |
//+------------------------------------------------------------------+
#ifndef __EA_TRADE_HISTORY_MQH__
#define __EA_TRADE_HISTORY_MQH__

#include <CandleBreakoutEA\EAUtils.mqh>

//+------------------------------------------------------------------+
//| One closed position aggregated from its deals                    |
//+------------------------------------------------------------------+
struct SHistoryDealRow
  {
   ulong               deal_ticket;
   ulong               position_id;
   datetime            time;
   ENUM_DEAL_ENTRY     entry;
   double              profit;
  };

//+------------------------------------------------------------------+
//| Reads the terminal history only - no state, no caching.          |
//+------------------------------------------------------------------+
class CTradeHistory
  {
private:
   ulong               m_magic;
   string              m_symbol;

   //--- append one deal into the buffer when magic/symbol match
   void                CollectDeal(const int index,SHistoryDealRow &rows[]) const
     {
      const ulong ticket = HistoryDealGetTicket(index);
      if(ticket==0)
         return;
      if(HistoryDealGetInteger(ticket,DEAL_MAGIC)!=(long)m_magic)
         return;
      if(m_symbol!="" && HistoryDealGetString(ticket,DEAL_SYMBOL)!=m_symbol)
         return;

      SHistoryDealRow row;
      row.deal_ticket = ticket;
      row.position_id = (ulong)HistoryDealGetInteger(ticket,DEAL_POSITION_ID);
      row.time        = (datetime)HistoryDealGetInteger(ticket,DEAL_TIME);
      row.entry       = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket,DEAL_ENTRY);
      row.profit      = HistoryDealGetDouble(ticket,DEAL_PROFIT)
                        +HistoryDealGetDouble(ticket,DEAL_SWAP)
                        +HistoryDealGetDouble(ticket,DEAL_COMMISSION);

      const int size = ArraySize(rows);
      ArrayResize(rows,size+1);
      rows[size] = row;
     }

public:
                       CTradeHistory(void) : m_magic(0), m_symbol("") {}

   void                Init(const ulong magic,const string symbol)
     {
      m_magic  = magic;
      m_symbol = symbol;
     }

   //--- profit of the current server day (profit + swap + commission)
   double              DailyProfit(void) const
     {
      const datetime from = CEAUtils::DayStart(TimeCurrent());
      if(!HistorySelect(from,TimeCurrent()+60))
         return(0.0);
      double total = 0.0;
      const int total_deals = HistoryDealsTotal();
      for(int i=0; i<total_deals; i++)
        {
         const ulong ticket = HistoryDealGetTicket(i);
         if(ticket==0)
            continue;
         if(HistoryDealGetInteger(ticket,DEAL_MAGIC)!=(long)m_magic)
            continue;
         if(m_symbol!="" && HistoryDealGetString(ticket,DEAL_SYMBOL)!=m_symbol)
            continue;
         total += HistoryDealGetDouble(ticket,DEAL_PROFIT)
                  +HistoryDealGetDouble(ticket,DEAL_SWAP)
                  +HistoryDealGetDouble(ticket,DEAL_COMMISSION);
        }
      return(total);
     }

   //--- net result of every OUT deal of one position (profit + swap + commission).
   //--- used when the broker (break even stop, terminal) closed the position.
   double              DealProfitOfPosition(const ulong position_id) const
     {
      if(position_id==0)
         return(0.0);
      if(!HistorySelect(TimeCurrent()-60*86400,TimeCurrent()+60))
         return(0.0);
      double total = 0.0;
      const int total_deals = HistoryDealsTotal();
      for(int i=0; i<total_deals; i++)
        {
         const ulong ticket = HistoryDealGetTicket(i);
         if(ticket==0)
            continue;
         if(HistoryDealGetInteger(ticket,DEAL_MAGIC)!=(long)m_magic)
            continue;
         if((ulong)HistoryDealGetInteger(ticket,DEAL_POSITION_ID)!=position_id)
            continue;
         const ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket,DEAL_ENTRY);
         if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY)
            continue;
         total += HistoryDealGetDouble(ticket,DEAL_PROFIT)
                + HistoryDealGetDouble(ticket,DEAL_SWAP)
                + HistoryDealGetDouble(ticket,DEAL_COMMISSION);
        }
      return(total);
     }

   //--- realized components of a closed position (gross profit, swap, commission)
   void                DealCostsOfPosition(const ulong position_id,double &profit,
                                           double &swap,double &commission) const
     {
      profit = 0.0; swap = 0.0; commission = 0.0;
      if(position_id==0)
         return;
      if(!HistorySelect(TimeCurrent()-60*86400,TimeCurrent()+60))
         return;
      const int total_deals = HistoryDealsTotal();
      for(int i=0; i<total_deals; i++)
        {
         const ulong ticket = HistoryDealGetTicket(i);
         if(ticket==0)
            continue;
         if(HistoryDealGetInteger(ticket,DEAL_MAGIC)!=(long)m_magic)
            continue;
         if((ulong)HistoryDealGetInteger(ticket,DEAL_POSITION_ID)!=position_id)
            continue;
         const ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket,DEAL_ENTRY);
         if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY)
            continue;
         profit     += HistoryDealGetDouble(ticket,DEAL_PROFIT);
         swap       += HistoryDealGetDouble(ticket,DEAL_SWAP);
         commission += HistoryDealGetDouble(ticket,DEAL_COMMISSION);
        }
     }

   //--- number of losing deals inside a window
   int                 LossesSince(const datetime from) const
     {
      SHistoryDealRow rows[];
      LoadDeals(from,rows);
      int losses = 0;
      for(int i=0; i<ArraySize(rows); i++)
         if(rows[i].profit<0.0)
            losses++;
      return(losses);
     }

   //--- losing streak measured on closed positions, newest first
   int                 ConsecutiveLosses(void) const
     {
      SHistoryDealRow rows[];
      LoadDeals(TimeCurrent()-60*86400,rows);   // 60 days back
      if(ArraySize(rows)==0)
         return(0);
      SortByTimeDescending(rows);

      int   streak        = 0;
      ulong last_position = 0;
      for(int i=0; i<ArraySize(rows); i++)
        {
         //--- only closing deals decide the outcome of a position
         if(rows[i].entry!=DEAL_ENTRY_OUT && rows[i].entry!=DEAL_ENTRY_OUT_BY)
            continue;
         //--- one evaluation per position id
         if(rows[i].position_id==last_position)
            continue;
         last_position = rows[i].position_id;

         if(rows[i].profit<0.0)
            streak++;
         else
            break;
        }
      return(streak);
     }

   //--- raw loader, exposed for diagnostics
   void                LoadDeals(const datetime from,SHistoryDealRow &rows[]) const
     {
      ArrayResize(rows,0);
      if(!HistorySelect(from,TimeCurrent()+60))
         return;
      const int total_deals = HistoryDealsTotal();
      for(int i=0; i<total_deals; i++)
         CollectDeal(i,rows);
     }

private:
   //--- simple insertion sort, histories are short
   void                SortByTimeDescending(SHistoryDealRow &rows[]) const
     {
      const int total = ArraySize(rows);
      for(int i=1; i<total; i++)
        {
         const SHistoryDealRow key = rows[i];
         int j = i-1;
         while(j>=0 && rows[j].time<key.time)
           {
            rows[j+1] = rows[j];
            j--;
           }
         rows[j+1] = key;
        }
     }
  };

#endif // __EA_TRADE_HISTORY_MQH__
//+------------------------------------------------------------------+
