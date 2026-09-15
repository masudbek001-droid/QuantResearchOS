//+------------------------------------------------------------------+
//|              QuantResearchOS_ReplayOnnxValidation.mq5            |
//|              Stage 11: Replay + ONNX inference validation        |
//+------------------------------------------------------------------+
#property script_show_inputs
#property strict

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAData\DatabaseManager.mqh>
#include <CandleBreakoutEA\EAData\DatabaseTypes.mqh>
#include <CandleBreakoutEA\EAReplay\ReplayController.mqh>

input int InpDatasetVersion = 911001;
input int InpBars           = 5;

bool Exec(CDatabaseManager &db,const string sql,const string label)
  {
   if(db.Execute(sql))
      return(true);
   Print("[QROS_STAGE11] FAIL | ",label);
   return(false);
  }

bool SeedReplayData(CDatabaseManager &db,const string symbol,const int bars,
                    int &symbol_id,int &timeframe_id,datetime &start_time,
                    datetime &end_time)
  {
   symbol_id = 1;
   timeframe_id = (int)PERIOD_H1;
   start_time = D'2026.01.05 00:00';
   end_time = start_time+(datetime)((bars-1)*PeriodSeconds(PERIOD_H1));
   const string stamp = TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES);

   if(!Exec(db,"DELETE FROM "+string(DB_TABLE_REPLAY),"clear replay")) return(false);
   if(!Exec(db,"DELETE FROM "+string(DB_TABLE_DATASETS),"clear datasets")) return(false);
   if(!Exec(db,"DELETE FROM "+string(DB_TABLE_QUALITY),"clear quality")) return(false);
   if(!Exec(db,"DELETE FROM "+string(DB_TABLE_LABELS),"clear labels")) return(false);
   if(!Exec(db,"DELETE FROM "+string(DB_TABLE_OBSERVATIONS),"clear observations")) return(false);
   if(!Exec(db,"DELETE FROM "+string(DB_TABLE_TRADES),"clear trades")) return(false);
   if(!Exec(db,"DELETE FROM "+string(DB_TABLE_SNAPSHOTS),"clear snapshots")) return(false);
   if(!Exec(db,"DELETE FROM "+string(DB_TABLE_TIMEFRAMES),"clear timeframes")) return(false);
   if(!Exec(db,"DELETE FROM "+string(DB_TABLE_SYMBOLS),"clear symbols")) return(false);

   string sql = StringFormat(
      "INSERT INTO %s (SymbolID,Symbol,Digits,Point,TickSize,TickValue,ContractSize,CreatedAt) "
      "VALUES (%d,'%s',3,0.001,0.001,0.1,100,'%s')",
      DB_TABLE_SYMBOLS,symbol_id,symbol,stamp);
   if(!Exec(db,sql,"seed symbol")) return(false);

   sql = StringFormat("INSERT INTO %s (TimeframeID,Name,Minutes) VALUES (%d,'%s',60)",
                      DB_TABLE_TIMEFRAMES,timeframe_id,EnumToString(PERIOD_H1));
   if(!Exec(db,sql,"seed timeframe")) return(false);

   for(int i=0; i<bars; i++)
     {
      const datetime t = start_time+(datetime)(i*PeriodSeconds(PERIOD_H1));
      const double open = 2000.0+i*2.0;
      const double high = open+3.0;
      const double low = open-2.0;
      const double close = open+1.0;
      const double range = high-low;
      const int hour = (int)((t/3600)%24);

      sql = StringFormat(
         "INSERT INTO %s (SnapshotID,SymbolID,TimeframeID,SnapshotTime,Spread,ATR,ATRRatio,"
         "Open,High,Low,Close,BodySize,BodyPercent,UpperShadow,LowerShadow,\"Range\","
         "Volatility,TrendDirection,TrendStrength,CurrentSession,CurrentHour,Weekday,Month,"
         "Quarter,BrokerOffset,CreatedAt) "
         "VALUES (%d,%d,%d,%d,40,3.0,1.0,%s,%s,%s,%s,1.0,20.0,2.0,2.0,%s,"
         "3.0,1,60.0,1,%d,1,1,1,0,'%s')",
         DB_TABLE_SNAPSHOTS,i+1,symbol_id,timeframe_id,(int)t,
         DoubleToString(open,8),DoubleToString(high,8),DoubleToString(low,8),
         DoubleToString(close,8),DoubleToString(range,8),hour,stamp);
      if(!Exec(db,sql,"seed snapshot")) return(false);

      sql = StringFormat(
         "INSERT INTO %s (ObservationID,SymbolID,TimeframeID,ObservationTime,BarTime,"
         "ObservationType,FeatureSnapshotID,TradeID,Session,Hour,Weekday,Month,CreatedAt) "
         "VALUES (%d,%d,%d,%d,%d,0,%d,NULL,1,%d,1,1,'%s')",
         DB_TABLE_OBSERVATIONS,i+1,symbol_id,timeframe_id,(int)t,(int)t,
         i+1,hour,stamp);
      if(!Exec(db,sql,"seed observation")) return(false);

      sql = StringFormat(
         "INSERT INTO %s (LabelID,ObservationID,LabelVersion,LookaheadBars,FutureHigh,FutureLow,"
         "FutureClose,MaxFavorableExcursion,MaxAdverseExcursion,DirectionLabel,BreakoutSuccess,"
         "LabelQuality,GeneratedAt) "
         "VALUES (%d,%d,1,1,%s,%s,%s,3.0,2.0,1,1,1,'%s')",
         DB_TABLE_LABELS,i+1,i+1,DoubleToString(high,8),DoubleToString(low,8),
         DoubleToString(close,8),stamp);
      if(!Exec(db,sql,"seed label")) return(false);

      sql = StringFormat(
         "INSERT INTO %s (DatasetVersion,ObservationID,SnapshotID,LabelID,TradeID,ExportStatus,CreatedAt) "
         "VALUES (%d,%d,%d,%d,NULL,%d,'%s')",
         DB_TABLE_DATASETS,InpDatasetVersion,i+1,i+1,i+1,(int)DATASET_EXPORT_INTERNAL,stamp);
      if(!Exec(db,sql,"seed dataset")) return(false);
     }

   sql = StringFormat(
      "INSERT INTO %s (DatasetVersion,RowCount,ValidRows,InvalidRows,DuplicateRows,"
      "MissingSnapshots,MissingLabels,BrokenReferences,LookAheadViolations,ConsistencyScore,"
      "CompletenessScore,IntegrityScore,OverallScore,QualityStatus,GeneratedAt) "
      "VALUES (%d,%d,%d,0,0,0,0,0,0,100,100,100,100,%d,'%s')",
      DB_TABLE_QUALITY,InpDatasetVersion,bars,bars,(int)QUALITY_PASS,stamp);
   return(Exec(db,sql,"seed quality"));
  }

bool RunModel(const long handle,const SReplaySnapshot &bar,int &label,float &sum)
  {
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
   if(!OnnxRun(handle,ONNX_DEFAULT,inputs,labels,probabilities))
      return(false);

   label = (int)labels[0];
   sum = 0.0f;
   for(int i=0;i<4;i++)
      sum += probabilities[0][i];
   return(label>=0 && label<=3 && sum>=0.99f && sum<=1.01f);
  }

long OpenModel(const string file)
  {
   const long h = OnnxCreate(file,ONNX_DEFAULT);
   if(h==INVALID_HANDLE)
      return(INVALID_HANDLE);
   const long input_shape[] = {1,22};
   const long label_shape[] = {1};
   const long proba_shape[] = {1,4};
   if(!OnnxSetInputShape(h,0,input_shape) ||
      !OnnxSetOutputShape(h,0,label_shape) ||
      !OnnxSetOutputShape(h,1,proba_shape))
     {
      OnnxRelease(h);
      return(INVALID_HANDLE);
     }
   return(h);
  }

void OnStart()
  {
   CEASettings settings;
   settings.Reset();
   settings.symbol_name = "STAGE11_REPLAY_ONNX";
   settings.magic = 911001;
   settings.log_level = LOG_INFO;

   CLogger logger;
   logger.Init(settings.magic,settings.symbol_name,settings.log_level);

   CDatabaseManager db;
   db.Initialize(settings,logger);
   if(!db.Open())
     {
      Print("[QROS_STAGE11] STATUS=FAIL | database open");
      return;
     }

   int symbol_id = 0;
   int timeframe_id = 0;
   datetime start_time = 0;
   datetime end_time = 0;
   const int bars = (InpBars<3 ? 3 : InpBars);
   bool ok = SeedReplayData(db,settings.symbol_name,bars,symbol_id,timeframe_id,start_time,end_time);

   const long logistic = OpenModel("CBEA\\Models\\QROS_LogisticRegression_Baseline_v1.onnx");
   const long forest   = OpenModel("CBEA\\Models\\QROS_RandomForest_Baseline_v1.onnx");
   ok = ok && (logistic!=INVALID_HANDLE && forest!=INVALID_HANDLE);

   CReplayController replay;
   replay.Initialize(settings,logger,db);
   const long replay_id = (ok ? replay.InitializeReplay(InpDatasetVersion,symbol_id,timeframe_id,
                                                        start_time,end_time) : 0);
   ok = ok && (replay_id>0) && replay.StartReplay();

   int inference_count = 0;
   int guard = 0;
   while(ok && replay.State()!=REPLAY_FINISHED && guard<20)
     {
      SReplaySnapshot snap;
      ok = replay.Timeline().GetCurrentSnapshot(snap);
      int label_a=-1,label_b=-1;
      float sum_a=0.0f,sum_b=0.0f;
      ok = ok && RunModel(logistic,snap,label_a,sum_a);
      ok = ok && RunModel(forest,snap,label_b,sum_b);
      if(ok)
        {
         inference_count += 2;
         Print("[QROS_STAGE11] INFERENCE=PASS | bar=",TimeToString(snap.bar_time,TIME_DATE|TIME_MINUTES),
               " | logistic=",label_a," | rf=",label_b,
               " | sums=",DoubleToString(sum_a,4),"/",DoubleToString(sum_b,4));
        }
      ok = ok && replay.StepForward();
      guard++;
     }
   ok = ok && (replay.State()==REPLAY_FINISHED) && (inference_count>=bars*2);

   if(logistic!=INVALID_HANDLE) OnnxRelease(logistic);
   if(forest!=INVALID_HANDLE) OnnxRelease(forest);

   if(ok)
      Print("[QROS_STAGE11] STATUS=PASS | replay_id=",replay_id,
            " | bars=",bars," | inferences=",inference_count,
            " | state=",EnumToString(replay.State()));
   else
      Print("[QROS_STAGE11] STATUS=FAIL | replay_id=",replay_id,
            " | bars=",bars," | inferences=",inference_count,
            " | state=",EnumToString(replay.State()),
            " | err=",GetLastError());

   db.Close();
  }
//+------------------------------------------------------------------+
