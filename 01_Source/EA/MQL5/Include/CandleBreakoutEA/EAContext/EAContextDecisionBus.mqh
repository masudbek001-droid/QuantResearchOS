//+------------------------------------------------------------------+
//|                    EAContext/EAContextDecisionBus.mqh            |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Decision Bus — advisory only (ADR-0018)   |
//+------------------------------------------------------------------+
#ifndef __EA_CTX_DECISION_BUS_MQH__
#define __EA_CTX_DECISION_BUS_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAContext\EAContextAI.mqh>
#include <CandleBreakoutEA\EAContext\EAContextRiskAdvisory.mqh>
#include <CandleBreakoutEA\EAContext\EAContextResearchAdvisory.mqh>

enum ENUM_BUS_FLAG { BUS_FLAG_NORMAL=0, BUS_FLAG_REDUCED=1, BUS_FLAG_CAUTION=2, BUS_FLAG_ELEVATED=3 };
enum ENUM_BUS_HINT { BUS_HINT_NONE=0, BUS_HINT_RISK=1, BUS_HINT_RESEARCH=2, BUS_HINT_SHADOW=3 };

string BusFlagToString(const ENUM_BUS_FLAG f)
  {
   switch(f)
     {
      case BUS_FLAG_NORMAL:   return("NORMAL");
      case BUS_FLAG_REDUCED:  return("REDUCED");
      case BUS_FLAG_CAUTION:  return("CAUTION");
      case BUS_FLAG_ELEVATED: return("ELEVATED");
     }
   return("UNKNOWN");
  }
string BusHintToString(const ENUM_BUS_HINT h)
  {
   switch(h)
     {
      case BUS_HINT_NONE:     return("NONE");
      case BUS_HINT_RISK:     return("RISK");
      case BUS_HINT_RESEARCH: return("RESEARCH");
      case BUS_HINT_SHADOW:   return("SHADOW");
     }
   return("UNKNOWN");
  }

struct SBusAdvisory
  {
   double               bus_multiplier; // 0.50..1.50
   ENUM_BUS_FLAG        bus_flag;
   ENUM_BUS_HINT        bus_hint;
   string               consensus_reason;
   void Reset(void)
     {
      bus_multiplier    = 1.0;
      bus_flag          = BUS_FLAG_NORMAL;
      bus_hint          = BUS_HINT_NONE;
      consensus_reason  = "neutral";
     }
  };

//+------------------------------------------------------------------+
//| Decision Bus — advisory consensus, dormant, explicit Route       |
//+------------------------------------------------------------------+
class CAIDecisionBus
  {
private:
   bool                m_enabled;
   SBusAdvisory        m_last;
   CLogger            *m_log;

public:
                       CAIDecisionBus(void) : m_enabled(false), m_log(NULL) { m_last.Reset(); }

   void                Init(const bool enabled,CLogger &logger) { m_enabled=enabled; m_log=&logger; m_last.Reset(); }
   bool                IsEnabled(void) const { return(m_enabled); }
   void                SetEnabled(const bool e) { m_enabled=e; if(!e) Reset(); }
   void                Reset(void) { m_last.Reset(); }
   SBusAdvisory        Last(void) const { return(m_last); }
   bool                Validate(void) const
     {
      return(m_last.bus_multiplier>=0.50 && m_last.bus_multiplier<=1.50 &&
             m_last.bus_flag>=BUS_FLAG_NORMAL && m_last.bus_flag<=BUS_FLAG_ELEVATED);
     }
   string              ToString(void) const
     {
      return(StringFormat("bus: mult %.2f | flag %s | hint %s | %s",
                          m_last.bus_multiplier, BusFlagToString(m_last.bus_flag),
                          BusHintToString(m_last.bus_hint), m_last.consensus_reason));
     }

   SBusAdvisory        Route(const SRiskAdvisory &risk,const SResearchAdvisory &research,const CAIContext &ai)
     {
      if(!m_enabled)
        {
         m_last.Reset();
         m_last.consensus_reason="disabled";
         return(m_last);
        }

      double mult = risk.risk_multiplier;
      // research modulates: if research confidence <0.55, shave 0.85
      if(research.confidence>0 && research.confidence<0.55) mult *= 0.85;
      // shadow low confidence modulates
      if(ai.PredictionAvailable && ai.PredictionConfidence<0.35) mult *= 0.80;
      if(mult<0.50) mult=0.50;
      if(mult>1.50) mult=1.50;

      // flag priority: ELEVATED (risk daily) > CAUTION (risk CAUTION or research GB) > REDUCED > NORMAL
      ENUM_BUS_FLAG flag = BUS_FLAG_NORMAL;
      ENUM_BUS_HINT hint = BUS_HINT_NONE;
      string reason = "risk+research+shadow consensus";

      if(risk.risk_flag==RISK_ADVISORY_ELEVATED)
        {
         flag = BUS_FLAG_ELEVATED; hint = BUS_HINT_RISK; reason = "RISK ELEVATED dominates";
        }
      else if(risk.risk_flag==RISK_ADVISORY_CAUTION || research.next_experiment_hint==RESEARCH_HINT_TRY_GRADIENT_BOOST)
        {
         flag = BUS_FLAG_CAUTION; hint = BUS_HINT_RESEARCH; reason = "RISK CAUTION or research GB";
        }
      else if(mult<0.90)
        {
         flag = BUS_FLAG_REDUCED; hint = BUS_HINT_RISK; reason = "mult <0.90 reduced";
        }

      m_last.bus_multiplier   = mult;
      m_last.bus_flag         = flag;
      m_last.bus_hint         = hint;
      m_last.consensus_reason  = reason;

      if(!Validate())
        {
         if(m_log!=NULL) m_log.Warn("DecisionBus validation failed, resetting");
         Reset();
        }
      return(m_last);
     }
  };

#endif // __EA_CTX_DECISION_BUS_MQH__
//+------------------------------------------------------------------+
