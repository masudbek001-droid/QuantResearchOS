//+------------------------------------------------------------------+
//|                    EAContext/EAContextRiskAdvisory.mqh           |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Chief Risk AI — advisory only (ADR-0016)  |
//+------------------------------------------------------------------+
#ifndef __EA_CTX_RISK_ADVISORY_MQH__
#define __EA_CTX_RISK_ADVISORY_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAContext\EAContextAI.mqh>
#include <CandleBreakoutEA\EAContext\EAContextMarket.mqh>

//+------------------------------------------------------------------+
//| Advisory risk flag — observable only, never gates trading        |
//+------------------------------------------------------------------+
enum ENUM_RISK_ADVISORY_FLAG
  {
   RISK_ADVISORY_NORMAL   = 0, // no caution
   RISK_ADVISORY_REDUCED  = 1, // suggested 0.85 regime
   RISK_ADVISORY_CAUTION  = 2, // high-vol or fake breakout 0.50
   RISK_ADVISORY_ELEVATED = 3  // daily limit proximity 80%
  };

string RiskAdvisoryFlagToString(const ENUM_RISK_ADVISORY_FLAG flag)
  {
   switch(flag)
     {
      case RISK_ADVISORY_NORMAL:   return("NORMAL");
      case RISK_ADVISORY_REDUCED:  return("REDUCED");
      case RISK_ADVISORY_CAUTION:  return("CAUTION");
      case RISK_ADVISORY_ELEVATED: return("ELEVATED");
     }
   return("UNKNOWN");
  }

//+------------------------------------------------------------------+
//| Advisory snapshot — never written to orders, positions, or DB    |
//+------------------------------------------------------------------+
struct SRiskAdvisory
  {
   double                   risk_multiplier;      // 0.50 .. 1.50 advisory only
   ENUM_RISK_ADVISORY_FLAG  risk_flag;
   bool                     daily_tightening_advisory; // true when near limit
   bool                     carry_advisory;      // true when carry discouraged
   bool                     confidence_calibrated;
   string                   reason;              // human-readable cause chain
   void Reset(void)
     {
      risk_multiplier            = 1.0;
      risk_flag                  = RISK_ADVISORY_NORMAL;
      daily_tightening_advisory  = false;
      carry_advisory             = true;
      confidence_calibrated      = true;
      reason                     = "neutral";
     }
  };

//+------------------------------------------------------------------+
//| Chief Risk AI — advisory only, dormant, explicit Update          |
//| Reads market + AI contexts + account state, writes SRiskAdvisory |
//| Never places, blocks, modifies, or closes trades.                |
//+------------------------------------------------------------------+
class CAIRiskAdvisory
  {
private:
   bool                m_enabled;
   SRiskAdvisory       m_last;
   CLogger            *m_log;

   //--- volatility regime from statistical baseline volv3 strat
   double              VolatilityMultiplier(const double atr_ratio) const
     {
      if(atr_ratio<=0.0)
         return(1.0);
      if(atr_ratio<=0.75) // Low compression: WR 58.87% — neutral 1.00
         return(1.00);
      if(atr_ratio<=1.50) // Normal — slight reduction 0.85
         return(0.85);
      // High expansion: WR 49.79% random — caution 0.50
      return(0.50);
     }

   //--- hourly regime from baseline top/worst hours
   double              HourlyMultiplier(const int hour) const
     {
      if(hour<0 || hour>23)
         return(1.0);
      // Top expectancy hours: 12 (63.31%), 01 (63.72%), 13,05 — keep 1.00
      if(hour==12 || hour==1 || hour==13 || hour==5 || hour==14)
         return(1.00);
      // Worst hour 21 (49.37%) and 4 (50.94%) — caution 0.70
      if(hour==21 || hour==4)
         return(0.70);
      // London/NewYork mixed (08-20) slight discount 0.85, Asia 0.90
      if(hour>=8 && hour<=20)
         return(0.85);
      return(0.90);
     }

   //--- model confidence calibration vs walk-forward avg_accuracy 0.39-0.418
   double              ConfidenceMultiplier(const CAIContext &ai,string &cause) const
     {
      cause = "";
      if(!ai.PredictionAvailable)
         return(1.0);
      // Fake breakout with high p>0.50 — strong whipsaw signal → 0.50
      if(ai.PredictionLabel==3 && ai.ProbabilityFakeBreakout>0.50)
        {
         cause = "FAKE_BREAKOUT p>0.50";
         return(0.50);
        }
      // Low confidence <0.35 below walk-forward avg → 0.80
      if(ai.PredictionConfidence<0.35)
        {
         cause = "low_conf<0.35";
         return(0.80);
        }
      // High confidence but low-accuracy model (logistic 0.39) → keep neutral
      return(1.0);
     }

public:
                       CAIRiskAdvisory(void) : m_enabled(false), m_log(NULL) { m_last.Reset(); }

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
      return(m_last.risk_multiplier>=0.50 && m_last.risk_multiplier<=1.50 &&
             m_last.risk_multiplier==m_last.risk_multiplier && // not NaN
             m_last.risk_flag>=RISK_ADVISORY_NORMAL && m_last.risk_flag<=RISK_ADVISORY_ELEVATED);
     }

   SRiskAdvisory       Last(void) const { return(m_last); }

   string              ToString(void) const
     {
      return(StringFormat("risk: mult %.2f | flag %s | daily_tight %d | carry %d | cal %d | %s",
                          m_last.risk_multiplier, RiskAdvisoryFlagToString(m_last.risk_flag),
                          m_last.daily_tightening_advisory ? 1 : 0,
                          m_last.carry_advisory ? 1 : 0,
                          m_last.confidence_calibrated ? 1 : 0,
                          m_last.reason));
     }

   //--- explicit advisory update — never gates trading, never writes orders
   SRiskAdvisory       Update(const CMarketContext &market,const CAIContext &ai,
                              const double daily_pnl,const double daily_profit_limit,
                              const double daily_loss_limit)
     {
      if(!m_enabled)
        {
         m_last.Reset();
         m_last.reason = "disabled";
         return(m_last);
        }
      double atr_ratio = 1.0;
      if(market.CurrentATR>0.0 && market.CurrentRange>0.0)
         atr_ratio = market.CurrentRange/market.CurrentATR;
      int hour = market.CurrentHour;
      double trend = market.TrendStrength;
      return(UpdateDetailed(atr_ratio,hour,ai,daily_pnl,daily_profit_limit,daily_loss_limit,trend));
     }

   //--- detailed update with explicit regime inputs — testable, still advisory only
   SRiskAdvisory       UpdateDetailed(const double atr_ratio,const int hour,
                                      const CAIContext &ai,
                                      const double daily_pnl,const double daily_profit_limit,
                                      const double daily_loss_limit,
                                      const double trend_strength)
     {
      if(!m_enabled)
        {
         m_last.Reset();
         m_last.reason = "disabled";
         return(m_last);
        }

      double vol_mult   = VolatilityMultiplier(atr_ratio);
      double hour_mult  = HourlyMultiplier(hour);
      string conf_cause = "";
      double conf_mult  = ConfidenceMultiplier(ai, conf_cause);

      double mult = vol_mult * hour_mult * conf_mult;
      // Clamp to advisory range 0.50..1.50 (never <0.5, never >1.5)
      if(mult<0.50) mult = 0.50;
      if(mult>1.50) mult = 1.50;

      // Flag determination — highest severity wins
      ENUM_RISK_ADVISORY_FLAG flag = RISK_ADVISORY_NORMAL;
      string flag_reason = "normal";
      if(vol_mult==0.50 || (ai.PredictionAvailable && ai.PredictionLabel==3 && ai.ProbabilityFakeBreakout>0.50))
        {
         flag = RISK_ADVISORY_CAUTION;
         flag_reason = "high_vol_or_fake";
        }
      else if(hour_mult==0.70 || conf_mult==0.80)
        {
         flag = RISK_ADVISORY_REDUCED;
         flag_reason = (hour_mult==0.70 ? "worst_hour" : conf_cause);
        }

      // Daily tightening advisory (does NOT block; only observable)
      bool daily_tight = false;
      if(daily_profit_limit>0.0 && daily_pnl>=0.80*daily_profit_limit)
         daily_tight = true;
      if(daily_loss_limit>0.0 && daily_pnl<=-0.80*MathAbs(daily_loss_limit))
         daily_tight = true;
      if(daily_tight)
        {
         flag = RISK_ADVISORY_ELEVATED;
         flag_reason = "daily_80pct";
        }

      // Carry advisory — discourage carry on caution/elevated or trend weak <70
      bool carry_ok = true;
      if(flag==RISK_ADVISORY_CAUTION || flag==RISK_ADVISORY_ELEVATED)
         carry_ok = false;
      else if(trend_strength>=0.0 && trend_strength<70.0 && vol_mult!=1.00)
         carry_ok = false;

      bool calibrated = !(ai.PredictionAvailable && ai.PredictionConfidence<0.35);

      m_last.risk_multiplier           = mult;
      m_last.risk_flag                 = flag;
      m_last.daily_tightening_advisory = daily_tight;
      m_last.carry_advisory            = carry_ok;
      m_last.confidence_calibrated     = calibrated;
      m_last.reason                    = StringFormat("vol%.2fx hour%.2fx conf%.2fx => %.2f [%s] %s",
                                                      vol_mult, hour_mult, conf_mult, mult,
                                                      RiskAdvisoryFlagToString(flag), flag_reason);
      if(StringLen(conf_cause)>0)
         m_last.reason += " | " + conf_cause;

      if(!Validate())
        {
         if(m_log!=NULL) m_log.Warn("RiskAdvisory validation failed, resetting");
         Reset();
        }
      return(m_last);
     }
  };

#endif // __EA_CTX_RISK_ADVISORY_MQH__
//+------------------------------------------------------------------+
