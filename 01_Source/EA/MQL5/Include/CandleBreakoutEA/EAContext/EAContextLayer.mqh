//+------------------------------------------------------------------+
//|                                      EAContext/EAContextLayer.mqh|
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Context Layer facade                      |
//+------------------------------------------------------------------+
#ifndef __EA_CTX_LAYER_MQH__
#define __EA_CTX_LAYER_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EATradeContext.mqh>
#include <CandleBreakoutEA\EAContext\EAContextTrade.mqh>
#include <CandleBreakoutEA\EAContext\EAContextMarket.mqh>
#include <CandleBreakoutEA\EAContext\EAContextStrategy.mqh>
#include <CandleBreakoutEA\EAContext\EAContextAI.mqh>

//+------------------------------------------------------------------+
//| Single owner of the four runtime contexts. The trade manager is  |
//| the ONLY writer (through Update); every other module may only    |
//| read the public fields. All contexts are observation-only and    |
//| carry no business logic.                                         |
//+------------------------------------------------------------------+
class CContextLayer
  {
private:
   const CEASettings  *m_set;
   CLogger            *m_log;

public:
   CTradeContext       trade;
   CMarketContext      market;
   CStrategyContext    strategy;
   CAIContext          ai;

                       CContextLayer(void) : m_set(NULL), m_log(NULL) {}

   void                Init(const CEASettings &settings,CLogger &logger)
     {
      m_set = &settings;
      m_log = &logger;
      trade.Init(settings);
      market.Init(settings);
      strategy.Init(settings);
      ai.Init(settings.ai_reserved);
      if(!Validate())
         m_log.Warn("Context Layer validation failed at init");
     }

   //--- one funnel: snapshot in, four contexts refreshed
   void                Update(const STradeContext &src,const bool pendings,
                              const double risk_multiplier,const string state)
     {
      trade.Update(src);
      if(trade.TradeState==CTX_TRADE_FLAT && pendings)
         trade.TradeState = CTX_TRADE_ARMED;
      market.Update();
      strategy.Update(src.ticket!=0,pendings,risk_multiplier,state);
      ai.Update();
     }

   bool                Validate(void) const
     {
      return(trade.Validate() && market.Validate() && strategy.Validate() && ai.Validate());
     }

   void                Reset(void)
     {
      trade.Reset();
      market.Reset();
      strategy.Reset();
      ai.Reset();
     }

   string              ToString(void) const
     {
      return(trade.ToString()+" | "+market.ToString()+" | "+strategy.ToString()+" | "+ai.ToString());
     }

   //--- serialization stub for the future persistence layer
   bool                Serialize(string &out) const
     {
      out = "";
      return(false);
     }
  };

#endif // __EA_CTX_LAYER_MQH__
//+------------------------------------------------------------------+
