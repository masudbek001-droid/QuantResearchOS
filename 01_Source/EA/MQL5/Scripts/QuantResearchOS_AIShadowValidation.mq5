//+------------------------------------------------------------------+
//|                    QuantResearchOS_AIShadowValidation.mq5        |
//|                    Stage 13: shadow-only AI context validation   |
//+------------------------------------------------------------------+
#property script_show_inputs
#property strict

#include <CandleBreakoutEA\EAContext\EAContextAI.mqh>
#include <CandleBreakoutEA\EAContext\EAContextAIShadowInference.mqh>

void BuildSnapshot(SReplaySnapshot &snap)
  {
   snap.Reset();
   snap.snapshot_id = 1;
   snap.bar_time = D'2026.01.05 12:00';
   snap.spread = 40.0;
   snap.atr = 3.0;
   snap.atr_ratio = 1.0;
   snap.open = 2000.0;
   snap.high = 2003.0;
   snap.low = 1998.0;
   snap.close = 2001.0;
   snap.body_size = 1.0;
   snap.body_percent = 20.0;
   snap.upper_shadow = 2.0;
   snap.lower_shadow = 2.0;
   snap.range = 5.0;
   snap.volatility = 3.0;
   snap.trend_direction = 1;
   snap.trend_strength = 60.0;
   snap.session = 1;
   snap.hour = 12;
   snap.weekday = 1;
   snap.month = 1;
   snap.quarter = 1;
   snap.broker_offset = 0;
  }

bool ValidateOne(const string file,const string version)
  {
   CAIContext context;
   context.Init(true);
   if(context.PredictionAvailable)
     {
      Print("[QROS_STAGE13] FAIL | context reset");
      return(false);
     }

   CAIShadowInference shadow;
   if(!shadow.Load(file,version))
     {
      Print("[QROS_STAGE13] FAIL | load | file=",file," | err=",GetLastError());
      return(false);
     }

   SReplaySnapshot snap;
   BuildSnapshot(snap);
   const bool ok = shadow.Predict(snap,context);
   shadow.Release();

   if(!ok || !context.PredictionAvailable || !context.Validate())
     {
      Print("[QROS_STAGE13] FAIL | prediction | file=",file," | err=",GetLastError());
      return(false);
     }

   Print("[QROS_STAGE13] SHADOW=PASS | model=",version,
         " | label=",context.PredictionLabel,
         " | confidence=",DoubleToString(context.PredictionConfidence,6),
         " | inference_ms=",DoubleToString(context.InferenceTime,3));
   return(true);
  }

void OnStart()
  {
   const bool logistic = ValidateOne("CBEA\\Models\\QROS_LogisticRegression_Baseline_v1.onnx",
                                     "QROS_LogisticRegression_Baseline_v1");
   const bool forest = ValidateOne("CBEA\\Models\\QROS_RandomForest_Baseline_v1.onnx",
                                   "QROS_RandomForest_Baseline_v1");
   if(logistic && forest)
      Print("[QROS_STAGE13] STATUS=PASS | shadow_models=2 | context=PASS | trading_effect=NONE");
   else
      Print("[QROS_STAGE13] STATUS=FAIL | logistic=",logistic," | random_forest=",forest);
  }
//+------------------------------------------------------------------+
