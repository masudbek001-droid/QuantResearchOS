//+------------------------------------------------------------------+
//|                    EAContext/EAContextAICouncil.mqh              |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        AI Council — advisory only (ADR-0019)     |
//+------------------------------------------------------------------+
#ifndef __EA_CTX_AICOUNCIL_MQH__
#define __EA_CTX_AICOUNCIL_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAContext\EAContextAI.mqh>
#include <CandleBreakoutEA\EAContext\EAContextRiskAdvisory.mqh>
#include <CandleBreakoutEA\EAContext\EAContextResearchAdvisory.mqh>
#include <CandleBreakoutEA\EAContext\EAContextDecisionBus.mqh>

enum ENUM_COUNCIL_VOTE { COUNCIL_VOTE_NORMAL=0, COUNCIL_VOTE_REDUCED=1, COUNCIL_VOTE_CAUTION=2, COUNCIL_VOTE_ELEVATED=3 };

string CouncilVoteToString(const ENUM_COUNCIL_VOTE v)
  {
   switch(v)
     {
      case COUNCIL_VOTE_NORMAL:   return("NORMAL");
      case COUNCIL_VOTE_REDUCED:  return("REDUCED");
      case COUNCIL_VOTE_CAUTION:  return("CAUTION");
      case COUNCIL_VOTE_ELEVATED: return("ELEVATED");
     }
   return("UNKNOWN");
  }

struct SCouncilAdvisory
  {
   double               council_multiplier; // 0.50..1.50
   double               council_confidence; // 0..1
   ENUM_COUNCIL_VOTE    council_vote;
   string               consensus_reason;
   void Reset(void)
     {
      council_multiplier  = 1.0;
      council_confidence  = 0.55;
      council_vote        = COUNCIL_VOTE_NORMAL;
      consensus_reason    = "neutral";
     }
  };

class CAIAICouncil
  {
private:
   bool                m_enabled;
   SCouncilAdvisory    m_last;
   CLogger            *m_log;

public:
                       CAIAICouncil(void) : m_enabled(false), m_log(NULL) { m_last.Reset(); }
   void                Init(const bool e,CLogger &logger){ m_enabled=e; m_log=&logger; m_last.Reset(); }
   bool                IsEnabled(void) const{ return(m_enabled); }
   void                SetEnabled(const bool e){ m_enabled=e; if(!e) Reset(); }
   void                Reset(void){ m_last.Reset(); }
   SCouncilAdvisory    Last(void) const{ return(m_last); }
   bool                Validate(void) const{ return(m_last.council_multiplier>=0.50 && m_last.council_multiplier<=1.50 && m_last.council_confidence>=0.0 && m_last.council_confidence<=1.0); }
   string              ToString(void) const
     {
      return(StringFormat("council: mult %.2f | conf %.2f | vote %s | %s",
                          m_last.council_multiplier, m_last.council_confidence,
                          CouncilVoteToString(m_last.council_vote), m_last.consensus_reason));
     }

   SCouncilAdvisory    Convene(const SRiskAdvisory &risk,const SResearchAdvisory &research,
                               const SBusAdvisory &bus,const CAIContext &ai)
     {
      if(!m_enabled)
        {
         m_last.Reset(); m_last.consensus_reason="disabled"; return(m_last);
        }

      // weighted council: Risk 0.35, Research 0.25, Shadow 0.25, Bus 0.15
      double risk_w = 0.35 * risk.risk_multiplier;
      double res_w  = 0.25 * (research.confidence>0 ? 0.50 + research.confidence*0.50 : 1.0);
      double bus_w  = 0.15 * bus.bus_multiplier;
      double shadow_w = 0.25 * (ai.PredictionAvailable ? (ai.PredictionConfidence>0.35 ? 1.0 : 0.80) : 0.90);
      double raw = risk_w + res_w + bus_w + shadow_w;
      // normalize to 0.50..1.50 around 1.0
      double mult = 0.50 + raw; // rough; raw ~0.35+0.25+0.15+0.25=1.0 => mult~1.5; clamp
      if(mult<0.50) mult=0.50; if(mult>1.50) mult=1.50;
      // adjust to realistic: average risk 0.85, bus 0.90, research 0.65 => ~0.87
      mult = MathMin(1.50, MathMax(0.50, 0.50 + (risk.risk_multiplier*0.35 + bus.bus_multiplier*0.15 + (research.confidence*0.25 + 0.75*0.25))));

      double conf = (risk.risk_multiplier*0.20 + research.confidence*0.30 + bus.bus_multiplier*0.20/1.50 + (ai.PredictionAvailable?ai.PredictionConfidence:0.5)*0.30);
      if(conf>1.0) conf=1.0; if(conf<0.0) conf=0.0;

      ENUM_COUNCIL_VOTE vote = COUNCIL_VOTE_NORMAL;
      string reason="weighted Risk0.35/Research0.25/Shadow0.25/Bus0.15";
      if(risk.risk_flag==RISK_ADVISORY_ELEVATED || bus.bus_flag==BUS_FLAG_ELEVATED) { vote=COUNCIL_VOTE_ELEVATED; reason="Risk or Bus ELEVATED"; }
      else if(risk.risk_flag==RISK_ADVISORY_CAUTION || bus.bus_flag==BUS_FLAG_CAUTION) { vote=COUNCIL_VOTE_CAUTION; reason="Risk/ Bus CAUTION"; }
      else if(mult<0.90) { vote=COUNCIL_VOTE_REDUCED; reason="mult <0.90 reduced"; }

      m_last.council_multiplier = mult;
      m_last.council_confidence = conf;
      m_last.council_vote       = vote;
      m_last.consensus_reason   = reason;
      if(!Validate()){ if(m_log!=NULL) m_log.Warn("Council validation failed"); Reset(); }
      return(m_last);
     }
  };

#endif // __EA_CTX_AICOUNCIL_MQH__
//+------------------------------------------------------------------+
