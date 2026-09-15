//+------------------------------------------------------------------+
//|                         EAContext/EAContextAIShadowInference.mqh |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Shadow-only ONNX inference adapter        |
//+------------------------------------------------------------------+
#ifndef __EA_CTX_AI_SHADOW_INFERENCE_MQH__
#define __EA_CTX_AI_SHADOW_INFERENCE_MQH__

#include <CandleBreakoutEA\EAReplay\ReplayTypes.mqh>
#include <CandleBreakoutEA\EAContext\EAContextAI.mqh>

//+------------------------------------------------------------------+
//| Shadow-only adapter: may load an ONNX model and write prediction |
//| values into CAIContext. It never places, blocks, modifies, or     |
//| closes trades.                                                   |
//+------------------------------------------------------------------+
class CAIShadowInference
  {
private:
   long                m_handle;
   string              m_model_file;
   string              m_model_version;
   bool                m_ready;

public:
                       CAIShadowInference(void) : m_handle(INVALID_HANDLE),
                          m_model_file(""), m_model_version(""), m_ready(false) {}

   bool                Load(const string model_file,const string model_version)
     {
      Release();
      m_model_file    = model_file;
      m_model_version = model_version;
      m_handle        = OnnxCreate(model_file,ONNX_DEFAULT);
      if(m_handle==INVALID_HANDLE)
         return(false);

      const long input_shape[] = {1,22};
      const long label_shape[] = {1};
      const long proba_shape[] = {1,4};
      if(!OnnxSetInputShape(m_handle,0,input_shape) ||
         !OnnxSetOutputShape(m_handle,0,label_shape) ||
         !OnnxSetOutputShape(m_handle,1,proba_shape))
        {
         Release();
         return(false);
        }
      m_ready = true;
      return(true);
     }

   void                Release(void)
     {
      if(m_handle!=INVALID_HANDLE)
         OnnxRelease(m_handle);
      m_handle = INVALID_HANDLE;
      m_ready  = false;
     }

   bool                IsReady(void) const { return(m_ready && m_handle!=INVALID_HANDLE); }

   bool                Predict(const SReplaySnapshot &bar,CAIContext &context)
     {
      if(!IsReady())
         return(false);

      matrixf inputs(1,22);
      inputs[0][0]  = (float)bar.spread;
      inputs[0][1]  = (float)bar.atr;
      inputs[0][2]  = (float)bar.atr_ratio;
      inputs[0][3]  = (float)bar.range;
      inputs[0][4]  = (float)bar.range;
      inputs[0][5]  = (float)bar.body_size;
      inputs[0][6]  = (float)bar.body_percent;
      inputs[0][7]  = (float)bar.upper_shadow;
      inputs[0][8]  = (float)bar.lower_shadow;
      inputs[0][9]  = (bar.range>0.0 ? (float)(bar.upper_shadow/bar.range) : 0.0f);
      inputs[0][10] = (bar.range>0.0 ? (float)(bar.lower_shadow/bar.range) : 0.0f);
      inputs[0][11] = (bar.close>bar.open ? 1.0f : 0.0f);
      inputs[0][12] = (bar.close<bar.open ? 1.0f : 0.0f);
      inputs[0][13] = (float)bar.volatility;
      inputs[0][14] = (float)bar.trend_direction;
      inputs[0][15] = (float)bar.trend_strength;
      inputs[0][16] = (float)bar.hour;
      inputs[0][17] = (float)bar.weekday;
      inputs[0][18] = (float)bar.month;
      inputs[0][19] = (float)bar.quarter;
      inputs[0][20] = (float)bar.session;
      inputs[0][21] = (float)bar.broker_offset;

      vectorf labels(1);
      matrixf probabilities(1,4);
      const ulong started = GetMicrosecondCount();
      if(!OnnxRun(m_handle,ONNX_DEFAULT,inputs,labels,probabilities))
         return(false);
      const double elapsed_ms = (double)(GetMicrosecondCount()-started)/1000.0;

      context.SetPrediction(m_model_version,(int)labels[0],
                            probabilities[0][0],probabilities[0][1],
                            probabilities[0][2],probabilities[0][3],
                            elapsed_ms);
      return(context.Validate());
     }
  };

#endif // __EA_CTX_AI_SHADOW_INFERENCE_MQH__
//+------------------------------------------------------------------+
