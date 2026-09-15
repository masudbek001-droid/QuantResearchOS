//+------------------------------------------------------------------+
//|               QuantResearchOS_Stage7Validation_EA.mq5            |
//|               Stage 7: research platform validation (EA harness) |
//+------------------------------------------------------------------+
#property strict

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAData\DatabaseManager.mqh>
#include <CandleBreakoutEA\EAData\DatabaseTypes.mqh>
#include <CandleBreakoutEA\EAResearch\ExperimentEngine.mqh>
#include <CandleBreakoutEA\EAResearch\BenchmarkEngine.mqh>
#include <CandleBreakoutEA\EAResearch\WalkForwardEngine.mqh>

input int InpValidationMagic   = 907001;
input int InpDatasetVersion    = 907001;

bool Exec(CDatabaseManager &db,const string sql,const string label)
  {
   if(db.Execute(sql))
      return(true);
   Print("[QROS_STAGE7] FAIL | ",label);
   return(false);
  }

bool Scalar(CDatabaseManager &db,const string sql,long &value)
  {
   string rows[];
   if(db.Select(sql,rows)!=1)
      return(false);
   value = StringToInteger(rows[0]);
   return(true);
  }

bool ClearResearchTables(CDatabaseManager &db)
  {
   return(Exec(db,"DELETE FROM "+string(DB_TABLE_WF_RUNS),"clear wf runs") &&
          Exec(db,"DELETE FROM "+string(DB_TABLE_BENCHMARKS),"clear benchmarks") &&
          Exec(db,"DELETE FROM "+string(DB_TABLE_EXPERIMENTS),"clear experiments") &&
          Exec(db,"DELETE FROM "+string(DB_TABLE_DATASETS),"clear datasets") &&
          Exec(db,"DELETE FROM "+string(DB_TABLE_TRADES),"clear trades"));
  }

bool SeedMockTradesAndDataset(CDatabaseManager &db,const int dataset_version)
  {
   const string stamp = TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES);
   
   const string sql_trades[] = {
      StringFormat("INSERT INTO %s (TradeID,Ticket,SymbolID,TimeframeID,Magic,Direction,Lots,"
                   "EntryTime,ExitTime,EntryPrice,ExitPrice,Profit,NetProfit,CreatedAt) "
                   "VALUES (1,1001,1,60,%d,0,0.1,1000,2000,2000.0,2005.0,50.0,50.0,'%s')",
                   DB_TABLE_TRADES,InpValidationMagic,stamp),
      StringFormat("INSERT INTO %s (TradeID,Ticket,SymbolID,TimeframeID,Magic,Direction,Lots,"
                   "EntryTime,ExitTime,EntryPrice,ExitPrice,Profit,NetProfit,CreatedAt) "
                   "VALUES (2,1002,1,60,%d,1,0.1,2500,3500,2005.0,2003.0,-20.0,-20.0,'%s')",
                   DB_TABLE_TRADES,InpValidationMagic,stamp),
      StringFormat("INSERT INTO %s (TradeID,Ticket,SymbolID,TimeframeID,Magic,Direction,Lots,"
                   "EntryTime,ExitTime,EntryPrice,ExitPrice,Profit,NetProfit,CreatedAt) "
                   "VALUES (3,1003,1,60,%d,0,0.1,4000,5000,2003.0,2006.0,30.0,30.0,'%s')",
                   DB_TABLE_TRADES,InpValidationMagic,stamp),
      StringFormat("INSERT INTO %s (TradeID,Ticket,SymbolID,TimeframeID,Magic,Direction,Lots,"
                   "EntryTime,ExitTime,EntryPrice,ExitPrice,Profit,NetProfit,CreatedAt) "
                   "VALUES (4,1004,1,60,%d,0,0.1,5500,6500,2006.0,2010.0,40.0,40.0,'%s')",
                   DB_TABLE_TRADES,InpValidationMagic,stamp)
   };

   for(int i=0; i<4; i++)
     {
      if(!Exec(db,sql_trades[i],"seed trade"))
         return(false);
      const string sql_ds = StringFormat(
         "INSERT INTO %s (DatasetID,DatasetVersion,ObservationID,SnapshotID,LabelID,TradeID,ExportStatus,CreatedAt) "
         "VALUES (%d,%d,%d,%d,%d,%d,1,'%s')",
         DB_TABLE_DATASETS,i+1,dataset_version,i+1,i+1,i+1,i+1,stamp);
      if(!Exec(db,sql_ds,"seed dataset row"))
         return(false);
     }
   return(true);
  }

int OnInit()
  {
   CEASettings settings;
   settings.Reset();
   settings.symbol_name = _Symbol;
   settings.main_timeframe = PERIOD_H1;
   settings.magic = InpValidationMagic;
   settings.log_level = LOG_INFO;

   CLogger logger;
   logger.Init(settings.magic,"STAGE7_RESEARCH",settings.log_level);

   CDatabaseManager db;
   db.Initialize(settings,logger);
   if(!db.Open())
     {
      Print("[QROS_STAGE7] STATUS=FAIL | database open failed");
      return(INIT_FAILED);
     }

   bool ok = true;
   ok = ok && ClearResearchTables(db);
   ok = ok && SeedMockTradesAndDataset(db,InpDatasetVersion);

   //--- 1. Initialize research engines
   CExperimentEngine experiments;
   experiments.Initialize(settings,logger,db);

   CBenchmarkEngine benchmarks;
   benchmarks.Initialize(settings,logger,db,experiments);

   CWalkForwardEngine walkforward;
   walkforward.Initialize(settings,logger,db,experiments);

   //--- 2. Experiment lifecycle tests (Task 0016)
   ok = ok && (experiments.CreateExperiment("",InpDatasetVersion,1,1,1,"hash_ok","notes")==0);
   ok = ok && (experiments.CreateExperiment("Exp_Bad_Hash",InpDatasetVersion,1,1,1,"","notes")==0);
   ok = ok && (experiments.CreateExperiment("Exp_Bad_Ver",0,1,1,1,"hash_ok","notes")==0);

   const long exp_id1 = experiments.CreateExperiment("Exp_Baseline_Test",InpDatasetVersion,1,1,1,"cfg_hash_stage7_001","baseline experiment");
   ok = ok && (exp_id1>0);

   SExperimentInfo info1;
   ok = ok && experiments.GetExperiment(exp_id1,info1);
   ok = ok && (info1.status==EXPERIMENT_CREATED);
   ok = ok && experiments.IsMutable(exp_id1);

   ok = ok && experiments.StartExperiment(exp_id1);
   ok = ok && experiments.GetExperiment(exp_id1,info1);
   ok = ok && (info1.status==EXPERIMENT_RUNNING);
   ok = ok && !experiments.StartExperiment(exp_id1);

   //--- 3. Benchmark engine tests (Task 0017)
   ok = ok && benchmarks.CalculateBenchmark(exp_id1);
   ok = ok && !benchmarks.CalculateBenchmark(exp_id1);

   long metric_count = 0;
   ok = ok && Scalar(db,StringFormat("SELECT COUNT(*) FROM %s WHERE ExperimentID=%d",
                                     DB_TABLE_BENCHMARKS,(int)exp_id1),metric_count);
   ok = ok && (metric_count>=7);

   string rows[];
   ok = ok && (db.Select(StringFormat("SELECT MetricValue FROM %s WHERE ExperimentID=%d AND MetricName='WinRate'",
                                      DB_TABLE_BENCHMARKS,(int)exp_id1),rows)==1);
   if(ok && ArraySize(rows)==1)
     {
      const double wr = StringToDouble(rows[0]);
      ok = ok && (MathAbs(wr-75.0)<0.01);
     }

   //--- 4. Walk-Forward engine tests (Task 0018)
   ok = ok && !walkforward.ValidateRun(exp_id1,0,1000,1000,2000);
   ok = ok && !walkforward.ValidateRun(exp_id1,2000,1000,2000,3000);
   ok = ok && !walkforward.ValidateRun(exp_id1,1000,2000,1500,2500);
   ok = ok && walkforward.ValidateRun(exp_id1,1000,2000,2000,3000);

   const long run1 = walkforward.CreateRun(exp_id1,1000,2000,2000,3000,1);
   ok = ok && (run1>0);

   ok = ok && !walkforward.ValidateRun(exp_id1,3000,4000,2500,3500);
   ok = ok && (walkforward.CreateRun(exp_id1,3000,4000,2500,3500,2)==0);

   const long run2 = walkforward.CreateRun(exp_id1,2000,3000,3000,4000,2);
   ok = ok && (run2>0);

   ok = ok && walkforward.RunWindow(run1);
   ok = ok && walkforward.FinishRun(run1,true);

   const long exp_id2 = experiments.CreateExperiment("Exp_WF_Planning",InpDatasetVersion,1,1,1,"cfg_hash_stage7_002","planning test");
   ok = ok && (exp_id2>0);
   ok = ok && experiments.StartExperiment(exp_id2);

   const int planned = walkforward.PlanWindows(exp_id2,WF_ROLLING,1000,4000,1000,1000);
   ok = ok && (planned==2);

   //--- 5. Sealing & Immutability test
   ok = ok && experiments.FinishExperiment(exp_id1);
   ok = ok && experiments.GetExperiment(exp_id1,info1);
   ok = ok && (info1.status==EXPERIMENT_COMPLETED);
   ok = ok && !experiments.IsMutable(exp_id1);

   ok = ok && !benchmarks.AddMetric(exp_id1,"CustomMetric",123.45,"pts");
   ok = ok && !walkforward.CreateRun(exp_id1,5000,6000,6000,7000,3);
   ok = ok && !experiments.StartExperiment(exp_id1);
   ok = ok && !experiments.FinishExperiment(exp_id1);

   string comp_report = "";
   ok = ok && benchmarks.CompareExperiments(exp_id1,exp_id2,comp_report);

   long final_exp=0, final_bench=0, final_wf=0;
   ok = ok && Scalar(db,StringFormat("SELECT COUNT(*) FROM %s",DB_TABLE_EXPERIMENTS),final_exp);
   ok = ok && Scalar(db,StringFormat("SELECT COUNT(*) FROM %s",DB_TABLE_BENCHMARKS),final_bench);
   ok = ok && Scalar(db,StringFormat("SELECT COUNT(*) FROM %s",DB_TABLE_WF_RUNS),final_wf);

   if(ok)
      Print(StringFormat("[QROS_STAGE7] STATUS=PASS | experiments=%d | benchmarks=%d | wf_runs=%d | immutability=PASS",
                         final_exp,final_bench,final_wf));
   else
      Print(StringFormat("[QROS_STAGE7] STATUS=FAIL | exp_id1=%d | exp_id2=%d | metrics=%d | planned=%d",
                         exp_id1,exp_id2,metric_count,planned));

   db.Close();
   return(ok ? INIT_SUCCEEDED : INIT_FAILED);
  }

void OnTick() {}
void OnDeinit(const int reason) {}
//+------------------------------------------------------------------+
