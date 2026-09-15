//+------------------------------------------------------------------+
//|                    QuantResearchOS_OnnxValidation.mq5            |
//|                    Stage 10: MT5 ONNX contract validation        |
//+------------------------------------------------------------------+
#property script_show_inputs
#property strict

input string InpModelFile = "CBEA\\Models\\QROS_LogisticRegression_Baseline_v1.onnx";

bool ValidateModel(const string model_file)
  {
   const long handle = OnnxCreate(model_file,ONNX_DEFAULT);
   if(handle==INVALID_HANDLE)
     {
      Print("[QROS_STAGE10] FAIL | OnnxCreate | file=",model_file," | err=",GetLastError());
      return(false);
     }

   const long input_shape[] = {1,22};
   const long label_shape[] = {1};
   const long proba_shape[] = {1,4};

   bool ok = true;
   ok = ok && OnnxSetInputShape(handle,0,input_shape);
   ok = ok && OnnxSetOutputShape(handle,0,label_shape);
   ok = ok && OnnxSetOutputShape(handle,1,proba_shape);

   matrixf inputs(1,22);
   inputs[0][0]  = 40.0f;   // Spread
   inputs[0][1]  = 3.0f;    // ATR
   inputs[0][2]  = 1.0f;    // ATRRatio
   inputs[0][3]  = 6.0f;    // PreviousRange
   inputs[0][4]  = 5.0f;    // CurrentRange
   inputs[0][5]  = 2.0f;    // BodySize
   inputs[0][6]  = 40.0f;   // BodyPercent
   inputs[0][7]  = 1.5f;    // UpperShadow
   inputs[0][8]  = 1.5f;    // LowerShadow
   inputs[0][9]  = 0.3f;    // UpperShadowRatio
   inputs[0][10] = 0.3f;    // LowerShadowRatio
   inputs[0][11] = 1.0f;    // Bullish
   inputs[0][12] = 0.0f;    // Bearish
   inputs[0][13] = 3.0f;    // Volatility
   inputs[0][14] = 1.0f;    // TrendDirection
   inputs[0][15] = 60.0f;   // TrendStrength
   inputs[0][16] = 12.0f;   // CurrentHour
   inputs[0][17] = 2.0f;    // Weekday
   inputs[0][18] = 1.0f;    // Month
   inputs[0][19] = 1.0f;    // Quarter
   inputs[0][20] = 1.0f;    // Session
   inputs[0][21] = 0.0f;    // BrokerOffset

   vectorf labels(1);
   matrixf probabilities(1,4);

   if(ok)
      ok = OnnxRun(handle,ONNX_DEFAULT,inputs,labels,probabilities);

   if(!ok)
     {
      Print("[QROS_STAGE10] FAIL | OnnxRun | file=",model_file," | err=",GetLastError());
      OnnxRelease(handle);
      return(false);
     }

   float sum = 0.0f;
   for(int i=0;i<4;i++)
      sum += probabilities[0][i];

   const int label = (int)labels[0];
   if(label<0 || label>3 || sum<0.99f || sum>1.01f)
     {
      Print("[QROS_STAGE10] FAIL | invalid output | label=",label," | probability_sum=",DoubleToString(sum,6));
      OnnxRelease(handle);
      return(false);
     }

   Print("[QROS_STAGE10] MODEL=PASS | file=",model_file,
         " | label=",label,
         " | p0=",DoubleToString(probabilities[0][0],6),
         " | p1=",DoubleToString(probabilities[0][1],6),
         " | p2=",DoubleToString(probabilities[0][2],6),
         " | p3=",DoubleToString(probabilities[0][3],6));

   OnnxRelease(handle);
   return(true);
  }

void OnStart()
  {
   const bool logistic_ok = ValidateModel(InpModelFile);
   const bool rf_ok = ValidateModel("CBEA\\Models\\QROS_RandomForest_Baseline_v1.onnx");
   if(logistic_ok && rf_ok)
      Print("[QROS_STAGE10] STATUS=PASS | onnx_models=2 | input_dim=22 | output_dim=4");
   else
      Print("[QROS_STAGE10] STATUS=FAIL | logistic=",logistic_ok," | random_forest=",rf_ok);
  }
//+------------------------------------------------------------------+
