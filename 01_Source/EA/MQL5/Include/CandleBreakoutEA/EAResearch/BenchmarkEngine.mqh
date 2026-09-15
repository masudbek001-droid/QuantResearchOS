//+------------------------------------------------------------------+
//|                           EAResearch/BenchmarkEngine.mqh         |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Research: benchmarks (Task 0017)          |
//+------------------------------------------------------------------+
#ifndef __EA_RESEARCH_BENCHMARK_MQH__
#define __EA_RESEARCH_BENCHMARK_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAData\DatabaseTypes.mqh>
#include <CandleBreakoutEA\EAData\DatabaseManager.mqh>
#include <CandleBreakoutEA\EAResearch\ExperimentEngine.mqh>

//+------------------------------------------------------------------+
//| TASK 0017: deterministic performance benchmarks per experiment.  |
//| All metrics are computed from stored Trades rows of the pinned   |
//| dataset version, ordered by ExitTime - the same data always      |
//| yields the same numbers. Sharpe/SQN are declared placeholders.   |
//+------------------------------------------------------------------+
class CBenchmarkEngine
  {
private:
   CLogger            *m_log;
   CDatabaseManager   *m_db;
   CExperimentEngine  *m_experiments;

public:
                       CBenchmarkEngine(void) : m_log(NULL),
                          m_db(NULL), m_experiments(NULL) {}

   void                Initialize(const CEASettings &settings,CLogger &logger,
                                  CDatabaseManager &db,CExperimentEngine &experiments)
     {
      m_log         = &logger;
      m_db          = &db;
      m_experiments = &experiments;
      m_log.Info("Benchmark Engine initialized");
     }

   //--- store one metric; only mutable experiments accept metrics
   bool                AddMetric(const long experiment_id,const string metric_name,
                                 const double metric_value,const string metric_unit)
     {
      if(m_db==NULL || !m_db.IsOpen())
         return(false);
      if(StringLen(metric_name)==0)
         return(false);
      if(m_experiments!=NULL && !m_experiments.IsMutable(experiment_id))
        {
         m_log.Warn(StringFormat("Benchmark rejected | experiment #%d is immutable",
                                 (int)experiment_id));
         return(false);
        }
      const string stamp = TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES);
      return(m_db.Insert(StringFormat(
                "INSERT INTO %s (ExperimentID,MetricName,MetricValue,MetricUnit,CreatedAt) "
                "VALUES (%d,'%s',%s,'%s','%s')",
                DB_TABLE_BENCHMARKS,(int)experiment_id,metric_name,
                DoubleToString(metric_value,6),metric_unit,stamp))==1);
     }

   //--- compute the minimum metric set from the experiment's dataset trades.
   //--- rejected when metrics already exist (reproducibility guard).
   bool                CalculateBenchmark(const long experiment_id)
     {
      if(m_db==NULL || !m_db.IsOpen() || m_experiments==NULL)
         return(false);
      SExperimentInfo exp;
      if(!m_experiments.GetExperiment(experiment_id,exp))
         return(false);
      if(!m_experiments.IsMutable(experiment_id))
        {
         m_log.Warn(StringFormat("Benchmark rejected | experiment #%d is immutable",
                                 (int)experiment_id));
         return(false);
        }
      string rows[];
      if(m_db.Select(StringFormat("SELECT COUNT(*) FROM %s WHERE ExperimentID=%d",
                                  DB_TABLE_BENCHMARKS,(int)experiment_id),rows)==1 &&
         StringToInteger(rows[0])>0)
        {
         m_log.Warn(StringFormat("Benchmark rejected | experiment #%d already benchmarked",
                                 (int)experiment_id));
         return(false);
        }

      //--- closed trades of the pinned dataset, deterministic order
      const int found = m_db.Select(StringFormat(
         "SELECT COALESCE(t.NetProfit,t.Profit),t.EntryTime,t.ExitTime FROM %s d "
         "JOIN %s t ON t.TradeID=d.TradeID "
         "WHERE d.DatasetVersion=%d AND d.TradeID IS NOT NULL AND t.ExitTime IS NOT NULL "
         "ORDER BY t.ExitTime ASC,t.TradeID ASC",
         DB_TABLE_DATASETS,DB_TABLE_TRADES,exp.dataset_version),rows);
      if(found<=0)
        {
         m_log.Warn(StringFormat("Benchmark skipped | dataset v%d has no closed trades",
                                 exp.dataset_version));
         return(false);
        }

      double net = 0.0, gross_win = 0.0, gross_loss = 0.0, equity = 0.0, peak = 0.0, max_dd = 0.0;
      long   wins = 0, holding = 0;
      for(int i=0; i<found; i++)
        {
         string c[];
         if(StringSplit(rows[i],';',c)!=3)
            continue;
         const double profit = StringToDouble(c[0]);
         const datetime in   = (datetime)StringToInteger(c[1]);
         const datetime out  = (datetime)StringToInteger(c[2]);
         net += profit;
         if(profit>0.0)
           { wins++; gross_win += profit; }
         else
            gross_loss += profit;
         if(out>in)
            holding += (long)(out-in);
         equity += profit;
         if(equity>peak)
            peak = equity;
         const double dd = peak-equity;
         if(dd>max_dd)
            max_dd = dd;
        }

      const double win_rate     = 100.0*(double)wins/found;
      const double pf           = (gross_loss<0.0 ? gross_win/-gross_loss : 0.0);
      const double expectancy   = net/found;
      const double avg_trade    = net/found;
      const double avg_holding  = (double)holding/found;
      const double recovery     = (max_dd>0.0 ? net/max_dd : 0.0);

      bool ok = true;
      ok = ok && AddMetric(experiment_id,"WinRate",win_rate,"%");
      ok = ok && AddMetric(experiment_id,"ProfitFactor",pf,"x");
      ok = ok && AddMetric(experiment_id,"Expectancy",expectancy,"money");
      ok = ok && AddMetric(experiment_id,"AverageTrade",avg_trade,"money");
      ok = ok && AddMetric(experiment_id,"AverageHoldingTime",avg_holding,"s");
      ok = ok && AddMetric(experiment_id,"MaximumDrawdown",max_dd,"money");
      ok = ok && AddMetric(experiment_id,"RecoveryFactor",recovery,"x");
      ok = ok && AddMetric(experiment_id,"SharpeRatio",0.0,"ratio");   // placeholder
      ok = ok && AddMetric(experiment_id,"SQN",0.0,"pts");             // placeholder
      if(ok)
         m_log.Info(StringFormat("Benchmark computed | experiment #%d | %d trades | WR %.1f%% | PF %.2f",
                                 (int)experiment_id,found,win_rate,pf));
      return(ok);
     }

   //--- compare any two experiments metric by metric
   bool                CompareExperiments(const long experiment_a,const long experiment_b,
                                          string &report)
     {
      report = "";
      if(m_db==NULL || !m_db.IsOpen())
         return(false);
      string rows[];
      if(m_db.Select(StringFormat(
            "SELECT a.MetricName,a.MetricValue,b.MetricValue,a.MetricUnit "
            "FROM %s a JOIN %s b ON b.MetricName=a.MetricName AND b.ExperimentID=%d "
            "WHERE a.ExperimentID=%d ORDER BY a.MetricName ASC",
            DB_TABLE_BENCHMARKS,DB_TABLE_BENCHMARKS,
            (int)experiment_b,(int)experiment_a),rows)<0)
         return(false);
      report = StringFormat("benchmark comparison | #%d vs #%d\n",(int)experiment_a,(int)experiment_b);
      for(int i=0; i<ArraySize(rows); i++)
        {
         string c[];
         if(StringSplit(rows[i],';',c)!=4)
            continue;
         report += StringFormat("%s: %s vs %s [%s]\n",c[0],c[1],c[2],c[3]);
        }
      return(true);
     }

   //--- full metric list of one experiment
   bool                GenerateBenchmarkReport(const long experiment_id,string &report)
     {
      report = "";
      if(m_db==NULL || !m_db.IsOpen())
         return(false);
      string rows[];
      if(m_db.Select(StringFormat(
            "SELECT MetricName,MetricValue,MetricUnit,CreatedAt FROM %s "
            "WHERE ExperimentID=%d ORDER BY MetricName ASC",
            DB_TABLE_BENCHMARKS,(int)experiment_id),rows)<0)
         return(false);
      report = StringFormat("benchmark report | experiment #%d\n",(int)experiment_id);
      for(int i=0; i<ArraySize(rows); i++)
        {
         string c[];
         if(StringSplit(rows[i],';',c)!=4)
            continue;
         report += StringFormat("%s = %s %s (at %s)\n",c[0],c[1],c[2],c[3]);
        }
      return(true);
     }
  };

#endif // __EA_RESEARCH_BENCHMARK_MQH__
//+------------------------------------------------------------------+
