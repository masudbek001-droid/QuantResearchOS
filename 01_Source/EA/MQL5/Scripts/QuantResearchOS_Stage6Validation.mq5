//+------------------------------------------------------------------+
//|                    QuantResearchOS_Stage6Validation.mq5          |
//|                    Stage 6: feature/data pipeline validation     |
//+------------------------------------------------------------------+
#property script_show_inputs
#property strict

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAContext\EAContextLayer.mqh>
#include <CandleBreakoutEA\EAFeatureBuilder\EAFeatureBuilder.mqh>
#include <CandleBreakoutEA\EAData\DatabaseManager.mqh>
#include <CandleBreakoutEA\EAData\DatabaseTypes.mqh>
#include <CandleBreakoutEA\EAData\MarketSnapshotWriter.mqh>
#include <CandleBreakoutEA\EAData\ObservationWriter.mqh>
#include <CandleBreakoutEA\EAData\LabelGenerator.mqh>
#include <CandleBreakoutEA\EAData\DataQualityAnalyzer.mqh>
#include <CandleBreakoutEA\EAData\DatasetBuilder.mqh>

input int InpDatasetVersion = 906001;
input int InpSeedBars       = 4;

bool Exec(CDatabaseManager &db,const string sql,const string label)
  {
   if(db.Execute(sql))
      return(true);
   Print("[QROS_STAGE6] FAIL | ",label);
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

bool ClearPipeline(CDatabaseManager &db)
  {
   return(Exec(db,"DELETE FROM "+string(DB_TABLE_DATASETS),"clear datasets") &&
          Exec(db,"DELETE FROM "+string(DB_TABLE_QUALITY),"clear quality") &&
          Exec(db,"DELETE FROM "+string(DB_TABLE_LABELS),"clear labels") &&
          Exec(db,"DELETE FROM "+string(DB_TABLE_OBSERVATIONS),"clear observations") &&
          Exec(db,"DELETE FROM "+string(DB_TABLE_TRADES),"clear trades") &&
          Exec(db,"DELETE FROM "+string(DB_TABLE_SNAPSHOTS),"clear snapshots") &&
          Exec(db,"DELETE FROM "+string(DB_TABLE_TIMEFRAMES),"clear timeframes") &&
          Exec(db,"DELETE FROM "+string(DB_TABLE_SYMBOLS),"clear symbols"));
  }

bool SeedSnapshot(CDatabaseManager &db,const int symbol_id,const int timeframe_id,
                  const datetime bar_time,const int snapshot_id)
  {
   const string symbol = _Symbol;
   const double o = iOpen(symbol,PERIOD_H1,iBarShift(symbol,PERIOD_H1,bar_time));
   const double h = iHigh(symbol,PERIOD_H1,iBarShift(symbol,PERIOD_H1,bar_time));
   const double l = iLow(symbol,PERIOD_H1,iBarShift(symbol,PERIOD_H1,bar_time));
   const double c = iClose(symbol,PERIOD_H1,iBarShift(symbol,PERIOD_H1,bar_time));
   if(o<=0.0 || h<l || c<l || c>h)
      return(false);
   const double range = h-l;
   const double body = MathAbs(c-o);
   const string stamp = TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES);
   MqlDateTime dt;
   TimeToStruct(bar_time,dt);

   const string sql = StringFormat(
      "INSERT INTO %s (SnapshotID,SymbolID,TimeframeID,SnapshotTime,Spread,ATR,ATRRatio,"
      "Open,High,Low,Close,BodySize,BodyPercent,UpperShadow,LowerShadow,\"Range\","
      "Volatility,TrendDirection,TrendStrength,CurrentSession,CurrentHour,Weekday,Month,"
      "Quarter,BrokerOffset,CreatedAt) "
      "VALUES (%d,%d,%d,%d,40,1.5,1.0,%s,%s,%s,%s,%s,%s,%s,%s,%s,1.0,1,80.0,1,%d,%d,%d,%d,0,'%s')",
      DB_TABLE_SNAPSHOTS,snapshot_id,symbol_id,timeframe_id,(int)bar_time,
      DoubleToString(o,8),DoubleToString(h,8),DoubleToString(l,8),DoubleToString(c,8),
      DoubleToString(body,8),DoubleToString(range>0.0 ? 100.0*body/range : 0.0,2),
      DoubleToString(h-MathMax(o,c),8),DoubleToString(MathMin(o,c)-l,8),
      DoubleToString(range,8),dt.hour,dt.day_of_week,dt.mon,(dt.mon-1)/3+1,stamp);
   return(Exec(db,sql,"seed snapshot"));
  }

void OnStart()
  {
   CEASettings settings;
   settings.Reset();
   settings.symbol_name = _Symbol;
   settings.main_timeframe = PERIOD_H1;
   settings.magic = 906001;
   settings.log_level = LOG_INFO;

   CLogger logger;
   logger.Init(settings.magic,"STAGE6_PIPELINE",settings.log_level);

   CDatabaseManager db;
   db.Initialize(settings,logger);
   if(!db.Open())
     {
      Print("[QROS_STAGE6] STATUS=FAIL | database open");
      return;
     }

   bool ok = true;
   CFeatureBuilder features;
   features.Initialize(settings,logger);
   features.Update();
   ok = ok && features.IsReady() && features.Validate();

   CContextLayer contexts;
   contexts.Init(settings,logger);
   CMarketSnapshotWriter snapshots;
   snapshots.Initialize(settings,logger,db,features,contexts);
   CObservationWriter observations;
   observations.Initialize(settings,logger,db,features,snapshots);
   CLabelGenerator labels;
   labels.Initialize(settings,logger,db);
   CDataQualityAnalyzer quality;
   quality.Initialize(settings,logger,db);
   CDatasetBuilder datasets;
   datasets.Initialize(settings,logger,db);
   datasets.AttachQuality(quality);

   ok = ok && ClearPipeline(db);
   const int symbol_id = snapshots.SymbolId();
   const int timeframe_id = snapshots.TimeframeId();
   ok = ok && (symbol_id>0 && timeframe_id==(int)PERIOD_H1);

   const int bars = (InpSeedBars<4 ? 4 : InpSeedBars);
   for(int i=0; ok && i<bars; i++)
     {
      const int shift = bars+2-i;
      const datetime bar_time = iTime(settings.symbol_name,settings.main_timeframe,shift);
      ok = ok && (bar_time>0);
      ok = ok && SeedSnapshot(db,symbol_id,timeframe_id,bar_time,i+1);
      if(ok)
        {
         MqlDateTime dt;
         TimeToStruct(bar_time,dt);
         ok = observations.InsertObservation(bar_time,OBS_NEW_BAR,i+1,-1,1,dt.hour,
                                             dt.day_of_week,dt.mon);
        }
     }

   const int generated = (ok ? labels.GenerateLabels(25) : 0);
   ok = ok && (generated==bars) && labels.ValidateLabels();

   const int built = (ok ? datasets.BuildDataset(InpDatasetVersion) : 0);
   ok = ok && (built==bars) && datasets.ValidateDataset(InpDatasetVersion);

   const ENUM_QUALITY_STATUS q = (ok ? quality.AnalyzeDataset(InpDatasetVersion) : QUALITY_UNKNOWN);
   string qreport = "";
   ok = ok && (q==QUALITY_PASS) && quality.GenerateQualityReport(InpDatasetVersion,qreport);

   FolderCreate("CBEA");
   const bool export_block = datasets.ExportDataset(InpDatasetVersion,DATASET_EXPORT_PARQUET)==false;
   const bool csv_ok = datasets.ExportDataset(InpDatasetVersion,DATASET_EXPORT_CSV);
   ok = ok && export_block && csv_ok;

   long snap_count=0, obs_count=0, label_count=0, ds_count=0, quality_count=0;
   ok = ok && Scalar(db,StringFormat("SELECT COUNT(*) FROM %s",DB_TABLE_SNAPSHOTS),snap_count);
   ok = ok && Scalar(db,StringFormat("SELECT COUNT(*) FROM %s",DB_TABLE_OBSERVATIONS),obs_count);
   ok = ok && Scalar(db,StringFormat("SELECT COUNT(*) FROM %s",DB_TABLE_LABELS),label_count);
   ok = ok && Scalar(db,StringFormat("SELECT COUNT(*) FROM %s WHERE DatasetVersion=%d",
                                     DB_TABLE_DATASETS,InpDatasetVersion),ds_count);
   ok = ok && Scalar(db,StringFormat("SELECT COUNT(*) FROM %s WHERE DatasetVersion=%d",
                                     DB_TABLE_QUALITY,InpDatasetVersion),quality_count);

   if(ok)
      Print("[QROS_STAGE6] STATUS=PASS | features=PASS | snapshots=",snap_count,
            " | observations=",obs_count," | labels=",label_count,
            " | datasets=",ds_count," | quality=",quality_count,
            " | export=PASS");
   else
      Print("[QROS_STAGE6] STATUS=FAIL | feature_status=",FbStatusToString(features.LastStatus()),
            " | generated=",generated," | built=",built," | quality=",EnumToString(q));

   db.Close();
  }
//+------------------------------------------------------------------+
