//+------------------------------------------------------------------+
//|                                          EAContext/EAContextTrade.mqh|
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Context Layer: runtime trade state        |
//+------------------------------------------------------------------+
#ifndef __EA_CTX_TRADE_MQH__
#define __EA_CTX_TRADE_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EATradeContext.mqh>

//+------------------------------------------------------------------+
//| Lifecycle states of the trade book (observation only)            |
//+------------------------------------------------------------------+
enum ENUM_CTX_TRADE_STATE
  {
   CTX_TRADE_FLAT     = 0, // no position, no pendings
   CTX_TRADE_ARMED    = 1, // pending orders are on the market
   CTX_TRADE_IN_TRADE = 2, // a position is open
   CTX_TRADE_CARRY    = 3  // a carried position is open
  };

//+------------------------------------------------------------------+
//| Read-only runtime view of the live trade. Written only by the    |
//| Context Layer facade; consumed by future modules (features,      |
//| replay, persistence). Contains NO business logic: Update only    |
//| copies and derives ages, Validate only checks consistency.       |
//+------------------------------------------------------------------+
class CTradeContext
  {
private:
   const CEASettings  *m_set;

public:
   ulong               Ticket;
   ENUM_POSITION_TYPE  Direction;
   string              Symbol;
   ulong               Magic;
   double              Lots;
   double              EntryPrice;
   datetime            EntryTime;
   datetime            EntryBarTime;
   double              CurrentProfit;
   double              FloatingProfitMax;   // MFE, points
   double              FloatingLossMax;     // MAE, points (<= 0)
   int                 TradeAgeBars;        // completed main-TF bars since entry
   int                 TradeAgeMinutes;
   bool                BreakEvenActive;
   bool                CarryActive;
   bool                MomentumActive;
   bool                ProfitLockActive;
   ENUM_EXIT_REASON    ExitReason;          // planned exit if nothing changes
   ENUM_CTX_TRADE_STATE TradeState;

                       CTradeContext(void) : m_set(NULL) { Reset(); }

   void                Init(const CEASettings &settings)
     {
      m_set = &settings;
      Reset();
     }

   void                Reset(void)
     {
      Ticket             = 0;
      Direction          = POSITION_TYPE_BUY;
      Symbol             = (m_set!=NULL ? m_set.symbol_name : "");
      Magic              = (m_set!=NULL ? m_set.magic : 0);
      Lots               = 0.0;
      EntryPrice         = 0.0;
      EntryTime          = 0;
      EntryBarTime       = 0;
      CurrentProfit      = 0.0;
      FloatingProfitMax  = 0.0;
      FloatingLossMax    = 0.0;
      TradeAgeBars       = 0;
      TradeAgeMinutes    = 0;
      BreakEvenActive    = false;
      CarryActive        = false;
      MomentumActive     = false;
      ProfitLockActive   = false;
      ExitReason         = EXIT_H1;
      TradeState         = CTX_TRADE_FLAT;
     }

   //--- copy the shared snapshot and derive the age fields
   void                Update(const STradeContext &src)
     {
      Ticket             = src.ticket;
      Direction          = src.direction;
      Symbol             = m_set.symbol_name;
      Magic              = m_set.magic;
      Lots               = src.lots;
      EntryPrice         = src.entry_price;
      EntryTime          = src.entry_time;
      EntryBarTime       = src.entry_candle;
      CurrentProfit      = src.current_profit;
      FloatingProfitMax  = src.max_floating_profit;
      FloatingLossMax    = src.max_floating_loss;
      BreakEvenActive    = src.break_even_active;
      CarryActive        = src.carry_active;
      MomentumActive     = (m_set.momentum_exit_enabled && src.ticket!=0);
      ProfitLockActive   = src.profit_lock_active;
      ExitReason         = src.exit_reason;
      TradeState         = (src.ticket==0 ? CTX_TRADE_FLAT
                            : (src.carry_active ? CTX_TRADE_CARRY : CTX_TRADE_IN_TRADE));

      TradeAgeBars    = 0;
      TradeAgeMinutes = 0;
      if(src.ticket!=0)
        {
         const datetime bar = iTime(m_set.symbol_name,m_set.main_timeframe,0);
         if(bar>0 && src.entry_candle>0 && bar>src.entry_candle)
            TradeAgeBars = (int)((bar-src.entry_candle)/PeriodSeconds(m_set.main_timeframe));
         if(src.entry_time>0 && TimeCurrent()>src.entry_time)
            TradeAgeMinutes = (int)((TimeCurrent()-src.entry_time)/60);
        }
     }

   //--- consistency only, no business rules
   bool                Validate(void) const
     {
      if(StringLen(Symbol)==0)
         return(false);
      if(Ticket!=0)
         return(Lots>0.0 && EntryPrice>0.0 && EntryTime>0);
      return(true);
     }

   string              ToString(void) const
     {
      if(Ticket==0)
         return(StringFormat("trade: flat (%s magic %I64u)",Symbol,Magic));
      return(StringFormat("trade: #%I64u %s %.2f @ %.5f | age %db/%dm | MFE %.0f MAE %.0f | state %d",
                          Ticket,(Direction==POSITION_TYPE_BUY ? "BUY" : "SELL"),Lots,
                          EntryPrice,TradeAgeBars,TradeAgeMinutes,
                          FloatingProfitMax,FloatingLossMax,(int)TradeState));
     }

   //--- serialization stub: persistence arrives with the database ADR
   bool                Serialize(string &out) const
     {
      out = "";
      return(false);
     }
  };

#endif // __EA_CTX_TRADE_MQH__
//+------------------------------------------------------------------+
