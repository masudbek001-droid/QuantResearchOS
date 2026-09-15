//+------------------------------------------------------------------+
//|                                            EAContext/EAContextAI.mqh|
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Context Layer: AI placeholder             |
//+------------------------------------------------------------------+
#ifndef __EA_CTX_AI_MQH__
#define __EA_CTX_AI_MQH__

//+------------------------------------------------------------------+
//| Placeholder only. No inference, no models, no autonomous         |
//| behaviour. Every field defaults to "nothing available" and the   |
//| reserved slots exist so future ADRs can fill them without        |
//| breaking consumers.                                              |
//+------------------------------------------------------------------+
class CAIContext
  {
public:
   string              ModelVersion;
   bool                PredictionAvailable;
   int                 PredictionLabel;       // 0 range, 1 up, 2 down, 3 fake breakout
   double              PredictionConfidence;  // 0..1 when available
   double              ProbabilityRange;
   double              ProbabilityUp;
   double              ProbabilityDown;
   double              ProbabilityFakeBreakout;
   double              InferenceTime;         // ms of the last inference
   bool                Enabled;               // tied to the reserved input
   double              Reserved1;
   double              Reserved2;
   long                Reserved3;

                       CAIContext(void) { Reset(); }

   void                Init(const bool enabled)
     {
      Enabled = enabled;
      Reset();
     }

   void                Reset(void)
     {
      ModelVersion         = "none";
      PredictionAvailable  = false;
      PredictionLabel      = -1;
      PredictionConfidence = 0.0;
      ProbabilityRange     = 0.0;
      ProbabilityUp        = 0.0;
      ProbabilityDown      = 0.0;
      ProbabilityFakeBreakout = 0.0;
      InferenceTime        = 0.0;
      Reserved1            = 0.0;
      Reserved2            = 0.0;
      Reserved3            = 0;
     }

   void                Update(void)
     {
      //--- placeholder: nothing to observe yet
     }

   bool                Validate(void) const
     {
      const double sum = ProbabilityRange+ProbabilityUp+ProbabilityDown+ProbabilityFakeBreakout;
      return(PredictionConfidence>=0.0 && PredictionConfidence<=1.0 &&
             (!PredictionAvailable || StringLen(ModelVersion)>0) &&
             (!PredictionAvailable || (PredictionLabel>=0 && PredictionLabel<=3)) &&
             (!PredictionAvailable || (sum>=0.99 && sum<=1.01)));
     }

   string              ToString(void) const
     {
      return(StringFormat("ai: model %s | available %d | label %d | conf %.2f",
                          ModelVersion,(PredictionAvailable ? 1 : 0),PredictionLabel,PredictionConfidence));
     }

   void                SetPrediction(const string model_version,const int label,
                                     const double p_range,const double p_up,
                                     const double p_down,const double p_fake,
                                     const double inference_ms)
     {
      ModelVersion              = model_version;
      PredictionLabel           = label;
      ProbabilityRange          = p_range;
      ProbabilityUp             = p_up;
      ProbabilityDown           = p_down;
      ProbabilityFakeBreakout   = p_fake;
      PredictionConfidence      = MathMax(MathMax(p_range,p_up),MathMax(p_down,p_fake));
      InferenceTime             = inference_ms;
      PredictionAvailable       = Validate();
      if(!PredictionAvailable)
         Reset();
     }

   bool                Serialize(string &out) const
     {
      out = "";
      return(false);   // stub: persistence arrives with the database ADR
     }
  };

#endif // __EA_CTX_AI_MQH__
//+------------------------------------------------------------------+
