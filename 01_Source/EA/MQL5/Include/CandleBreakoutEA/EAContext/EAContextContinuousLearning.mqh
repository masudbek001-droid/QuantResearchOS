//+------------------------------------------------------------------+
//|            EAContext/EAContextContinuousLearning.mqh             |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Continuous Learning — advisory only (ADR-0020)|
//+------------------------------------------------------------------+
#ifndef __EA_CTX_CONTINUOUS_LEARNING_MQH__
#define __EA_CTX_CONTINUOUS_LEARNING_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAContext\EAContextAI.mqh>
#include <CandleBreakoutEA\EAContext\EAContextRiskAdvisory.mqh>
#include <CandleBreakoutEA\EAContext\EAContextAICouncil.mqh>

enum ENUM_RETRAIN_HINT { RETRAIN_NONE=0, RETRAIN_SCHEDULED=1, RETRAIN_URGENT=2 };

string RetrainHintToString(const ENUM_RETRAIN_HINT h)
  {
   switch(h)
     {
      case RETRAIN_NONE:      return("NONE");
      case RETRAIN_SCHEDULED: return("SCHEDULED");
      case RETRAIN_URGENT:    return("URGENT");
     }
   return("UNKNOWN");
  }

struct SLearningAdvisory
  {
   double               drift_score; // 0..1
   ENUM_RETRAIN_HINT    retrain_hint;
   string               reason;
   void Reset(void){ drift_score=0.0; retrain_hint=RETRAIN_NONE; reason="stable"; }
  };

class CAIContinuousLearning
  {
private:
   bool                m_enabled;
   SLearningAdvisory   m_last;
   CLogger            *m_log;
public:
                       CAIContinuousLearning(void): m_enabled(false), m_log(NULL){ m_last.Reset(); }
   void                Init(const bool e,CLogger &logger){ m_enabled=e; m_log=&logger; m_last.Reset(); }
   bool                IsEnabled(void) const{ return(m_enabled); }
   void                SetEnabled(const bool e){ m_enabled=e; if(!e) Reset(); }
   void                Reset(void){ m_last.Reset(); }
   SLearningAdvisory   Last(void) const{ return(m_last); }
   bool                Validate(void) const{ return(m_last.drift_score>=0.0 && m_last.drift_score<=1.0); }
   string              ToString(void) const
     {
      return(StringFormat("learning: drift %.2f | hint %s | %s",
                          m_last.drift_score, RetrainHintToString(m_last.retrain_hint), m_last.reason));
     }
   SLearningAdvisory   CheckDrift(const SRiskAdvisory &risk,const SCouncilAdvisory &council,const CAIContext &ai)
     {
      if(!m_enabled){ m_last.Reset(); m_last.reason="disabled"; return(m_last); }
      double drift = 0.25;
      string reason="";
      if(risk.risk_flag==RISK_ADVISORY_CAUTION){ drift+=0.25; reason+="risk CAUTION "; }
      if(risk.risk_flag==RISK_ADVISORY_ELEVATED){ drift+=0.35; reason+="risk ELEVATED "; }
      if(council.council_vote==COUNCIL_VOTE_CAUTION){ drift+=0.20; reason+="council CAUTION "; }
      if(ai.PredictionAvailable && ai.PredictionConfidence<0.35){ drift+=0.20; reason+="low conf "; }
      if(drift>1.0) drift=1.0;
      ENUM_RETRAIN_HINT hint=RETRAIN_NONE;
      if(drift>=0.70) hint=RETRAIN_URGENT;
      else if(drift>=0.45) hint=RETRAIN_SCHEDULED;
      if(reason=="") reason="stable baseline";
      m_last.drift_score=drift;
      m_last.retrain_hint=hint;
      m_last.reason=reason;
      if(!Validate()){ if(m_log!=NULL) m_log.Warn("Learning validation failed"); Reset(); }
      return(m_last);
     }
  };

#endif // __EA_CTX_CONTINUOUS_LEARNING_MQH__
//+------------------------------------------------------------------+
