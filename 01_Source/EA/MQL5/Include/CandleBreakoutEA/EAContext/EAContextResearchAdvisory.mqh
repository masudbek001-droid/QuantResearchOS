//+------------------------------------------------------------------+
//|                EAContext/EAContextResearchAdvisory.mqh           |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Chief Research AI — advisory only (ADR-0017)|
//+------------------------------------------------------------------+
#ifndef __EA_CTX_RESEARCH_ADVISORY_MQH__
#define __EA_CTX_RESEARCH_ADVISORY_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAContext\EAContextAI.mqh>
#include <CandleBreakoutEA\EAContext\EAContextRiskAdvisory.mqh>

//+------------------------------------------------------------------+
//| Research hint enums — observable only, never gates trading       |
//+------------------------------------------------------------------+
enum ENUM_RESEARCH_HINT
  {
   RESEARCH_HINT_NONE              = 0,
   RESEARCH_HINT_ABLATE_ATR        = 1,
   RESEARCH_HINT_ABLATE_HOUR       = 2,
   RESEARCH_HINT_TRY_GRADIENT_BOOST= 3,
   RESEARCH_HINT_EXPAND_WINDOW     = 4,
   RESEARCH_HINT_RERUN_QUALITY     = 5
  };

string ResearchHintToString(const ENUM_RESEARCH_HINT hint)
  {
   switch(hint)
     {
      case RESEARCH_HINT_NONE:               return("NONE");
      case RESEARCH_HINT_ABLATE_ATR:         return("ABLATE_ATR");
      case RESEARCH_HINT_ABLATE_HOUR:        return("ABLATE_HOUR");
      case RESEARCH_HINT_TRY_GRADIENT_BOOST: return("TRY_GRADIENT_BOOST");
      case RESEARCH_HINT_EXPAND_WINDOW:      return("EXPAND_WINDOW");
      case RESEARCH_HINT_RERUN_QUALITY:      return("RERUN_QUALITY");
     }
   return("UNKNOWN");
  }

struct SResearchAdvisory
  {
   ENUM_RESEARCH_HINT   next_experiment_hint;
   ENUM_RESEARCH_HINT   feature_hint;
   ENUM_RESEARCH_HINT   window_hint;
   double               confidence; // 0..1 heuristic from walk-forward variance
   string               reason;
   void Reset(void)
     {
      next_experiment_hint = RESEARCH_HINT_NONE;
      feature_hint         = RESEARCH_HINT_NONE;
      window_hint          = RESEARCH_HINT_NONE;
      confidence           = 0.0;
      reason               = "neutral";
     }
  };

//+------------------------------------------------------------------+
//| Chief Research AI — advisory only, dormant, explicit Update      |
//| Synthesis of risk advisory + AI context + market regime           |
//+------------------------------------------------------------------+
class CAIResearchAdvisory
  {
private:
   bool                m_enabled;
   SResearchAdvisory   m_last;
   CLogger            *m_log;

public:
                       CAIResearchAdvisory(void) : m_enabled(false), m_log(NULL) { m_last.Reset(); }

   void                Init(const bool enabled,CLogger &logger)
     {
      m_enabled = enabled;
      m_log     = &logger;
      m_last.Reset();
     }

   bool                IsEnabled(void) const { return(m_enabled); }
   void                SetEnabled(const bool enabled) { m_enabled = enabled; if(!enabled) Reset(); }
   void                Reset(void) { m_last.Reset(); }

   bool                Validate(void) const
     {
      return(m_last.confidence>=0.0 && m_last.confidence<=1.0 &&
             m_last.next_experiment_hint>=RESEARCH_HINT_NONE && m_last.next_experiment_hint<=RESEARCH_HINT_RERUN_QUALITY);
     }

   SResearchAdvisory   Last(void) const { return(m_last); }

   string              ToString(void) const
     {
      return(StringFormat("research: next %s | feat %s | win %s | conf %.2f | %s",
                          ResearchHintToString(m_last.next_experiment_hint),
                          ResearchHintToString(m_last.feature_hint),
                          ResearchHintToString(m_last.window_hint),
                          m_last.confidence, m_last.reason));
     }

   //--- explicit advisory update — never gates trading
   SResearchAdvisory   Update(const SRiskAdvisory &risk,const CAIContext &ai,
                              const double atr_ratio,const int hour)
     {
      if(!m_enabled)
        {
         m_last.Reset();
         m_last.reason = "disabled";
         return(m_last);
        }

      // Heuristic from walk-forward variance (logistic 0.390 low, rf 0.418 higher)
      // plus risk advisory confidence + hourly/vol regime
      ENUM_RESEARCH_HINT next = RESEARCH_HINT_NONE;
      ENUM_RESEARCH_HINT feat = RESEARCH_HINT_NONE;
      ENUM_RESEARCH_HINT win  = RESEARCH_HINT_NONE;
      double conf = 0.55;
      string reason = "";

      // Feature hint: high vol (>1.5) → ATR-driven, worst hour → Hour-driven
      if(atr_ratio>1.50)
        {
         feat = RESEARCH_HINT_ABLATE_ATR;
         reason = "high_vol ATR ablation";
         conf = 0.62;
        }
      else if(hour==21 || hour==4)
        {
         feat = RESEARCH_HINT_ABLATE_HOUR;
         reason = "worst_hour ablation";
         conf = 0.60;
        }
      else
        {
         feat = RESEARCH_HINT_NONE;
         reason = "no ablation";
        }

      // Window hint: walk-forward variance high (logistic std ~0.04) → expand window
      // Simulated: if ai confidence low <0.35 → expand, else none
      if(ai.PredictionAvailable && ai.PredictionConfidence<0.35)
        {
         win = RESEARCH_HINT_EXPAND_WINDOW;
         reason += " | low_conf expand";
         conf = MathMin(conf, 0.58);
        }

      // Next experiment: if risk caution → GradientBoosting try, else none
      if(risk.risk_flag==RISK_ADVISORY_CAUTION)
        {
         next = RESEARCH_HINT_TRY_GRADIENT_BOOST;
         reason += " | risk CAUTION try GB";
         conf = MathMax(conf, 0.65);
        }
      else if(!ai.PredictionAvailable)
        {
         next = RESEARCH_HINT_RERUN_QUALITY;
         reason += " | no pred rerun quality";
         conf = 0.50;
        }

      m_last.next_experiment_hint = next;
      m_last.feature_hint         = feat;
      m_last.window_hint          = win;
      m_last.confidence           = conf;
      m_last.reason               = reason;

      if(!Validate())
        {
         if(m_log!=NULL) m_log.Warn("ResearchAdvisory validation failed, resetting");
         Reset();
        }
      return(m_last);
     }
  };

#endif // __EA_CTX_RESEARCH_ADVISORY_MQH__
//+------------------------------------------------------------------+
