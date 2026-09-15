//+------------------------------------------------------------------+
//|                    QuantResearchOS_Stage7Validation.mq5          |
//|                    Stage 7: research platform validation         |
//+------------------------------------------------------------------+
#property script_show_inputs
#property strict

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAData\DatabaseManager.mqh>
#include <CandleBreakoutEA\EAData\DatabaseTypes.mqh>
#include <CandleBreakoutEA\EAResearch\ExperimentEngine.mqh>
#include <CandleBreakoutEA\EAResearch\BenchmarkEngine.mqh>
#include <CandleBreakoutEA\EAResearch\WalkForwardEngine.mqh>

input int InpDatasetVersion = 907001;

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

bool ClearResearch(CDatabaseManager &db)
  {
   return(Exec(db,"DELETE FROM "+string(DB_TABLE_WF_RUNS),"clear walk-forward") &&
          Exec(db,"DELETE FROM "+string(DB_TABLE_BENCHMARKS),"clear benchmarks") &&
          Exec(db,"DELETE FROM "+string(DB_TABLE_EXPERIMENTS),"clear experiments") &&
          Exec(db,"DELETE FROM "+string(DB_TABLE_QUALITY),"clear quality") &&
          Exec(db,"DELETE FROM "+string(DB_TABLE_DATASETS),"clear datasets") &&
          Exec(db,"DELETE FROM "+string(DB_TABLE_LABELS),"clear labels") &&
          Exec(db,"DELETE FROM "+string(DB_TABLE_OBSERVATIONS),"clear observations") &&
          Exec(db,"DELETE FROM "+string(DB_TABLE_TRADES),"clear trades") &&
          Exec(db,"DELETE FROM "+string(DB_TABLE_SNAPSHOTS),"clear snapshots") &&
          Exec(db,"DELETE FROM "+string(DB_TABLE_TIMEFRAMES),"clear timeframes") &&
          Exec(db,"DELETE FROM "+string(DB_TABLE_SYMBOLS),"clear symbols"));
  }

bool SeedMasters(CDatabaseManager &db)
  {
   const string stamp = TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES);
   return(Exec(db,StringFormat("INSERT INTO %s (SymbolID,Symbol,Digits,Point,TickSize,TickValue,ContractSize,CreatedAt) "
                               "VALUES (1,'XAUUSD',3,0.001,0.001,0.10,100.0,'%s')",
                               DB_TABLE_SYMBOLS,stamp),"seed symbol") &&
          Exec(db,StringFormat("INSERT INTO %s (TimeframeID,Name,Minutes) VALUES (%d,'PERIOD_H1',60)",
                               DB_TABLE_TIMEFRAMES,(int)PERIOD_H1),"seed timeframe"));
  }

bool SeedSnapshot(CDatabaseManager &db,const int id,const datetime bar_time)
  {
   const string stamp = TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES);
   const double o = 2000.0 + id;
   const double h = o + 5.0;
   const double l = o - 3.0;
   const double c = o + 2.0;
   const string sql = StringFormat(
      "INSERT INTO %s (SnapshotID,SymbolID,TimeframeID,SnapshotTime,Spread,ATR,ATRRatio,"
      "Open,High,Low,Close,BodySize,BodyPercent,UpperShadow,LowerShadow,\"Range\","
      "Volatility,TrendDirection,TrendStrength,CurrentSession,CurrentHour,Weekday,Month,"
      "Quarter,BrokerOffset,CreatedAt) "
      "VALUES (%d,1,%d,%d,40,1.5,1.0,%s,%s,%s,%s,2.0,25.0,3.0,3.0,8.0,1.0,1,80.0,1,10,1,1,1,0,'%s')",
      DB_TABLE_SNAPSHOTS,id,(int)PERIOD_H1,(int)bar_time,
      DoubleToString(o,8),DoubleToString(h,8),DoubleToString(l,8),DoubleToString(c,8),stamp);
   return(Exec(db,sql,"seed snapshot"));
  }

bool SeedObservationLabel(CDatabaseManager &db,const int id,const datetime bar_time)
  {
   const string stamp = TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES);
   const bool obs_ok = Exec(db,StringFormat(
      "INSERT INTO %s (ObservationID,SymbolID,TimeframeID,ObservationTime,BarTime,ObservationType,"
      "FeatureSnapshotID,TradeID,Session,Hour,Weekday,Month,CreatedAt) "
      "VALUES (%d,1,%d,%d,%d,0,%d,NULL,1,10,1,1,'%s')",
      DB_TABLE_OBSERVATIONS,id,(int)PERIOD_H1,(int)bar_time,(int)bar_time,id,stamp),"seed observation");
   const bool label_ok = Exec(db,StringFormat(
      "INSERT INTO %s (LabelID,ObservationID,LabelVersion,LookaheadBars,FutureHigh,FutureLow,FutureClose,"
      "MaxFavorableExcursion,MaxAdverseExcursion,DirectionLabel,BreakoutSuccess,LabelQuality,GeneratedAt) "
      "VALUES (%d,%d,1,3,2010.0,1990.0,2005.0,10.0,5.0,1,1,100,'%s')",
      DB_TABLE_LABELS,id,id,stamp),"seed label");
   return(obs_ok && label_ok);
  }

bool SeedTradeDataset(CDatabaseManager &db,const int row,const int dataset_version,
                      const datetime in_time,const datetime out_time,const double profit)
  {
   const string stamp = TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES);
   const long ticket = 90700100 + row;
   const bool trade_ok = Exec(db,StringFormat(
      "INSERT INTO %s (TradeID,Ticket,SymbolID,TimeframeID,Magic,Direction,Lots,EntryTime,ExitTime,"
      "EntryPrice,ExitPrice,Profit,Swap,Commission,NetProfit,TradeDurationSeconds,TradeDurationBars,"
      "ExitReason,BreakEvenUsed,CarryUsed,MomentumUsed,ProfitLockUsed,EntrySnapshotID,ExitSnapshotID,CreatedAt) "
      "VALUES (%d,%d,1,%d,907001,%d,0.10,%d,%d,2000.0,2001.0,%s,0.0,0.0,%s,3600,1,1,0,0,0,0,%d,%d,'%s')",
      DB_TABLE_TRADES,row,(int)ticket,(int)PERIOD_H1,(row%2),(int)in_time,(int)out_time,
      DoubleToString(profit,2),DoubleToString(profit,2),row,row,stamp),"seed trade");
   const bool ds_ok = Exec(db,StringFormat(
      "INSERT INTO %s (DatasetVersion,ObservationID,SnapshotID,LabelID,TradeID,ExportStatus,CreatedAt) "
      "VALUES (%d,%d,%d,%d,%d,0,'%s')",
      DB_TABLE_DATASETS,dataset_version,row,row,row,row,stamp),"seed dataset");
   return(trade_ok && ds_ok);
  }

bool SeedResearchDataset(CDatabaseManager &db,const int dataset_version)
  {
   if(!SeedMasters(db))
      return(false);
   const datetime base = D'2026.01.05 00:00';
   double profits[4] = {100.0,-50.0,150.0,25.0};
   for(int i=0; i<4; i++)
     {
      const int id = i+1;
      const datetime bar = base + (datetime)(i*3600);
      if(!SeedSnapshot(db,id,bar))
         return(false);
      if(!SeedObservationLabel(db,id,bar))
         return(false);
      if(!SeedTradeDataset(db,id,dataset_version,bar,bar+(datetime)3600,profits[i]))
         return(false);
     }
   const string stamp = TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES);
   return(Exec(db,StringFormat(
      "INSERT INTO %s (DatasetVersion,RowCount,ValidRows,InvalidRows,DuplicateRows,MissingSnapshots,"
      "MissingLabels,BrokenReferences,LookAheadViolations,ConsistencyScore,CompletenessScore,"
      "IntegrityScore,OverallScore,QualityStatus,GeneratedAt) "
      "VALUES (%d,4,4,0,0,0,0,0,0,100,100,100,100,1,'%s')",
      DB_TABLE_QUALITY,dataset_version,stamp),"seed quality"));
  }

void OnStart()
  {
   CEASettings settings;
   settings.Reset();
   settings.symbol_name = _Symbol;
   settings.main_timeframe = PERIOD_H1;
   settings.magic = 907001;
   settings.log_level = LOG_INFO;

   CLogger logger;
   logger.Init(settings.magic,"STAGE7_RESEARCH",settings.log_level);

   CDatabaseManager db;
   db.Initialize(settings,logger);
   if(!db.Open())
     {
      Print("[QROS_STAGE7] STATUS=FAIL | database open");
      return;
     }

   bool ok = true;
   ok = ok && ClearResearch(db);
   ok = ok && SeedResearchDataset(db,InpDatasetVersion);

   CExperimentEngine experiments;
   experiments.Initialize(settings,logger,db);
   CBenchmarkEngine benchmarks;
   benchmarks.Initialize(settings,logger,db,experiments);
   CWalkForwardEngine walkforward;
   walkforward.Initialize(settings,logger,db,experiments);

   const long exp_a = (ok ? experiments.CreateExperiment("Stage7BenchmarkWF",InpDatasetVersion,1,1,1,
                                                         "stage7-config-a","stage7 isolated research validation") : 0);
   ok = ok && (exp_a>0) && experiments.StartExperiment(exp_a);
   ok = ok && benchmarks.CalculateBenchmark(exp_a);
   const bool benchmark_replay_blocked = !benchmarks.CalculateBenchmark(exp_a);

   const datetime train_a0 = D'2026.01.01 00:00';
   const datetime train_a1 = D'2026.01.10 00:00';
   const datetime test_a0  = D'2026.01.10 00:00';
   const datetime test_a1  = D'2026.01.15 00:00';
   const long run_a = (ok ? walkforward.CreateRun(exp_a,train_a0,train_a1,test_a0,test_a1,1) : 0);
   ok = ok && (run_a>0) && walkforward.RunWindow(run_a) && walkforward.FinishRun(run_a,true);
   const bool overlap_blocked = (walkforward.CreateRun(exp_a,D'2026.01.02 00:00',D'2026.01.11 00:00',
                                                       D'2026.01.12 00:00',D'2026.01.16 00:00',2)==0);

   const long exp_b = (ok ? experiments.CreateExperiment("Stage7PlanWF",InpDatasetVersion,1,1,1,
                                                         "stage7-config-b","stage7 walk-forward planning validation") : 0);
   ok = ok && (exp_b>0) && experiments.StartExperiment(exp_b);
   const int planned = (ok ? walkforward.PlanWindows(exp_b,WF_ROLLING,D'2026.02.01 00:00',
                                                     D'2026.03.01 00:00',7*86400,3*86400) : 0);
   ok = ok && (planned>0);

   ok = ok && experiments.FinishExperiment(exp_a);
   const bool immutable_benchmark_blocked = !benchmarks.AddMetric(exp_a,"AfterComplete",1.0,"blocked");
   const bool immutable_wf_blocked = (walkforward.CreateRun(exp_a,D'2026.04.01 00:00',D'2026.04.10 00:00',
                                                           D'2026.04.10 00:00',D'2026.04.15 00:00',99)==0);

   SExperimentInfo info;
   ok = ok && experiments.GetExperiment(exp_a,info) && info.status==EXPERIMENT_COMPLETED;
   ok = ok && benchmark_replay_blocked && overlap_blocked && immutable_benchmark_blocked && immutable_wf_blocked;

   long experiment_count=0, metric_count=0, wf_count=0, completed_count=0;
   ok = ok && Scalar(db,StringFormat("SELECT COUNT(*) FROM %s",DB_TABLE_EXPERIMENTS),experiment_count);
   ok = ok && Scalar(db,StringFormat("SELECT COUNT(*) FROM %s",DB_TABLE_BENCHMARKS),metric_count);
   ok = ok && Scalar(db,StringFormat("SELECT COUNT(*) FROM %s",DB_TABLE_WF_RUNS),wf_count);
   ok = ok && Scalar(db,StringFormat("SELECT COUNT(*) FROM %s WHERE Status=%d",
                                     DB_TABLE_EXPERIMENTS,(int)EXPERIMENT_COMPLETED),completed_count);
   ok = ok && (metric_count==9 && completed_count==1);

   if(ok)
      Print("[QROS_STAGE7] STATUS=PASS | experiments=",experiment_count,
            " | metrics=",metric_count,
            " | wf_runs=",wf_count,
            " | planned=",planned,
            " | immutable=PASS | duplicate_benchmark=BLOCKED | overlap=BLOCKED");
   else
      Print("[QROS_STAGE7] STATUS=FAIL | experiments=",experiment_count,
            " | metrics=",metric_count,
            " | wf_runs=",wf_count,
            " | planned=",planned,
            " | exp_a=",exp_a,
            " | exp_b=",exp_b);

   db.Close();
  }
//+------------------------------------------------------------------+
