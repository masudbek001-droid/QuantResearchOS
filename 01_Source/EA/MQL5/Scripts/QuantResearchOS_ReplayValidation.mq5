//+------------------------------------------------------------------+
//|                    QuantResearchOS_ReplayValidation.mq5          |
//|                    Stage 5: isolated replay validation harness   |
//+------------------------------------------------------------------+
#property script_show_inputs
#property strict

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAData\DatabaseManager.mqh>
#include <CandleBreakoutEA\EAData\DatabaseTypes.mqh>
#include <CandleBreakoutEA\EAReplay\ReplayController.mqh>

input int InpDatasetVersion = 905001;
input int InpBars           = 4;

bool Exec(CDatabaseManager &db,const string sql,const string label)
  {
   if(db.Execute(sql))
      return(true);
   Print("[QROS_STAGE5] FAIL | ",label);
   return(false);
  }

bool SeedReplayData(CDatabaseManager &db,const string symbol,const int bars,
                    int &symbol_id,int &timeframe_id,datetime &start_time,
                    datetime &end_time)
  {
   symbol_id = 1;
   timeframe_id = (int)PERIOD_M15;
   start_time = D'2026.01.05 00:00';
   end_time = start_time+(datetime)((bars-1)*PeriodSeconds(PERIOD_M15));
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

   sql = StringFormat("INSERT INTO %s (TimeframeID,Name,Minutes) VALUES (%d,'%s',15)",
                      DB_TABLE_TIMEFRAMES,timeframe_id,EnumToString(PERIOD_M15));
   if(!Exec(db,sql,"seed timeframe")) return(false);

   for(int i=0; i<bars; i++)
     {
      const datetime t = start_time+(datetime)(i*PeriodSeconds(PERIOD_M15));
      const double open = 2000.0+i;
      const double high = open+2.0;
      const double low = open-1.0;
      const double close = open+1.0;

      sql = StringFormat(
         "INSERT INTO %s (SnapshotID,SymbolID,TimeframeID,SnapshotTime,Spread,ATR,ATRRatio,"
         "Open,High,Low,Close,BodySize,BodyPercent,UpperShadow,LowerShadow,\"Range\","
         "Volatility,TrendDirection,TrendStrength,CurrentSession,CurrentHour,Weekday,Month,"
         "Quarter,BrokerOffset,CreatedAt) "
         "VALUES (%d,%d,%d,%d,40,1.5,1.0,%s,%s,%s,%s,1.0,33.3,1.0,1.0,3.0,"
         "0.5,1,70.0,1,%d,1,1,1,0,'%s')",
         DB_TABLE_SNAPSHOTS,i+1,symbol_id,timeframe_id,(int)t,
         DoubleToString(open,8),DoubleToString(high,8),DoubleToString(low,8),
         DoubleToString(close,8),(int)((t/3600)%24),stamp);
      if(!Exec(db,sql,"seed snapshot")) return(false);

      sql = StringFormat(
         "INSERT INTO %s (ObservationID,SymbolID,TimeframeID,ObservationTime,BarTime,"
         "ObservationType,FeatureSnapshotID,TradeID,Session,Hour,Weekday,Month,CreatedAt) "
         "VALUES (%d,%d,%d,%d,%d,0,%d,NULL,1,%d,1,1,'%s')",
         DB_TABLE_OBSERVATIONS,i+1,symbol_id,timeframe_id,(int)t,(int)t,
         i+1,(int)((t/3600)%24),stamp);
      if(!Exec(db,sql,"seed observation")) return(false);

      sql = StringFormat(
         "INSERT INTO %s (LabelID,ObservationID,LabelVersion,LookaheadBars,FutureHigh,FutureLow,"
         "FutureClose,MaxFavorableExcursion,MaxAdverseExcursion,DirectionLabel,BreakoutSuccess,"
         "LabelQuality,GeneratedAt) "
         "VALUES (%d,%d,1,3,%s,%s,%s,2.0,1.0,1,1,1,'%s')",
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

void OnStart()
  {
   CEASettings settings;
   settings.Reset();
   settings.symbol_name = "STAGE5_REPLAY";
   settings.magic = 905001;
   settings.log_level = LOG_INFO;

   CLogger logger;
   logger.Init(settings.magic,settings.symbol_name,settings.log_level);

   CDatabaseManager db;
   db.Initialize(settings,logger);
   if(!db.Open())
     {
      Print("[QROS_STAGE5] STATUS=FAIL | database open");
      return;
     }

   int symbol_id = 0;
   int timeframe_id = 0;
   datetime start_time = 0;
   datetime end_time = 0;
   const int bars = (InpBars<3 ? 3 : InpBars);
   if(!SeedReplayData(db,settings.symbol_name,bars,symbol_id,timeframe_id,start_time,end_time))
     {
      db.Close();
      Print("[QROS_STAGE5] STATUS=FAIL | seed");
      return;
     }

   CReplayController replay;
   replay.Initialize(settings,logger,db);
   const long replay_id = replay.InitializeReplay(InpDatasetVersion,symbol_id,timeframe_id,
                                                  start_time,end_time);
   bool ok = (replay_id>0);
   ok = ok && replay.StartReplay();
   ok = ok && replay.StepForward();
   ok = ok && replay.SeekTo(start_time+(datetime)(2*PeriodSeconds(PERIOD_M15)));
   ok = ok && replay.PauseReplay();
   ok = ok && replay.ResumeReplay();
   int guard = 0;
   while(ok && replay.State()!=REPLAY_FINISHED && guard<20)
     {
      ok = replay.StepForward();
      guard++;
     }
   ok = ok && (replay.State()==REPLAY_FINISHED);

   string rows[];
   const int sessions = db.Select(StringFormat(
      "SELECT ReplayState,CurrentBar,TotalBars FROM %s WHERE ReplayID=%d",
      DB_TABLE_REPLAY,(int)replay_id),rows);
   ok = ok && (sessions==1);
   if(ok)
      Print("[QROS_STAGE5] STATUS=PASS | replay_id=",replay_id,
            " | bars=",bars," | state=",EnumToString(replay.State()));
   else
      Print("[QROS_STAGE5] STATUS=FAIL | replay runtime");

   db.Close();
  }
//+------------------------------------------------------------------+
