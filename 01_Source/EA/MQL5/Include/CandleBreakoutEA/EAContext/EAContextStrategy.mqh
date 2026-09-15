//+------------------------------------------------------------------+
//|                                       EAContext/EAContextStrategy.mqh|
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Context Layer: strategy runtime state     |
//+------------------------------------------------------------------+
#ifndef __EA_CTX_STRATEGY_MQH__
#define __EA_CTX_STRATEGY_MQH__

#include <CandleBreakoutEA\EASettings.mqh>

//+------------------------------------------------------------------+
//| Read-only view of the candle-cycle state and the enabled exit    |
//| stack. Values are pushed by the Context Layer facade; the class  |
//| itself holds no logic beyond consistency checks.                 |
//+------------------------------------------------------------------+
class CStrategyContext
  {
private:
   const CEASettings  *m_set;

public:
   bool                TradeOpened;
   bool                PendingOrdersPlaced;
   bool                BreakEvenEnabled;
   bool                CarryEnabled;
   bool                MomentumEnabled;
   bool                ProfitLockEnabled;
   bool                MandatoryHourClose;   // strategy constant: always true
   string              CurrentStrategyState; // IDLE / ARMED / IN TRADE / CARRY
   double              RiskMultiplier;       // martingale multiplier of the armed candle
   double              ConfidenceScore;      // placeholder: reserved for future AI

                       CStrategyContext(void) : m_set(NULL) { Reset(); }

   void                Init(const CEASettings &settings)
     {
      m_set = &settings;
      Reset();
     }

   void                Reset(void)
     {
      TradeOpened         = false;
      PendingOrdersPlaced = false;
      BreakEvenEnabled    = (m_set!=NULL ? m_set.break_even_enabled : false);
      CarryEnabled        = (m_set!=NULL ? m_set.carry_enabled : false);
      MomentumEnabled     = (m_set!=NULL ? m_set.momentum_exit_enabled : false);
      ProfitLockEnabled   = (m_set!=NULL ? m_set.profit_lock_enabled : false);
      MandatoryHourClose  = true;
      CurrentStrategyState= "IDLE";
      RiskMultiplier      = 1.0;
      ConfidenceScore     = 0.0;
     }

   void                Update(const bool trade_opened,const bool pendings,
                              const double risk_multiplier,const string state)
     {
      TradeOpened         = trade_opened;
      PendingOrdersPlaced = pendings;
      BreakEvenEnabled    = m_set.break_even_enabled;
      CarryEnabled        = m_set.carry_enabled;
      MomentumEnabled     = m_set.momentum_exit_enabled;
      ProfitLockEnabled   = m_set.profit_lock_enabled;
      MandatoryHourClose  = true;
      CurrentStrategyState= state;
      RiskMultiplier      = (risk_multiplier>=1.0 ? risk_multiplier : 1.0);
     }

   bool                Validate(void) const
     {
      return(RiskMultiplier>=1.0 && ConfidenceScore>=0.0 && ConfidenceScore<=1.0 &&
             StringLen(CurrentStrategyState)>0);
     }

   string              ToString(void) const
     {
      return(StringFormat("strategy: %s | opened %d | pendings %d | BE %d PL %d MO %d CR %d | x%.2f",
                          CurrentStrategyState,(TradeOpened ? 1 : 0),(PendingOrdersPlaced ? 1 : 0),
                          (BreakEvenEnabled ? 1 : 0),(ProfitLockEnabled ? 1 : 0),
                          (MomentumEnabled ? 1 : 0),(CarryEnabled ? 1 : 0),RiskMultiplier));
     }

   bool                Serialize(string &out) const
     {
      out = "";
      return(false);   // stub: persistence arrives with the database ADR
     }
  };

#endif // __EA_CTX_STRATEGY_MQH__
//+------------------------------------------------------------------+
