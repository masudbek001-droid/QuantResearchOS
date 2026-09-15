//+------------------------------------------------------------------+
//|                          EAResearch/WalkForwardEngine.mqh        |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Research: walk-forward runs (Task 0018)   |
//+------------------------------------------------------------------+
#ifndef __EA_RESEARCH_WALKFORWARD_MQH__
#define __EA_RESEARCH_WALKFORWARD_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAData\DatabaseTypes.mqh>
#include <CandleBreakoutEA\EAData\DatabaseManager.mqh>
#include <CandleBreakoutEA\EAResearch\ExperimentEngine.mqh>

//+------------------------------------------------------------------+
//| TASK 0018: walk-forward window planning and run tracking.        |
//| Pure datetime arithmetic - fully deterministic. Validation       |
//| rejects overlapping testing windows and any test that starts     |
//| before its training window ends (leakage guard).                 |
//+------------------------------------------------------------------+
class CWalkForwardEngine
  {
private:
   CLogger            *m_log;
   CDatabaseManager   *m_db;
   CExperimentEngine  *m_experiments;

public:
                       CWalkForwardEngine(void) : m_log(NULL), m_db(NULL), m_experiments(NULL) {}

   void                Initialize(const CEASettings &settings,CLogger &logger,
                                  CDatabaseManager &db,CExperimentEngine &experiments)
     {
      m_log         = &logger;
      m_db          = &db;
      m_experiments = &experiments;
      m_log.Info("Walk-Forward Engine initialized");
     }

   //--- STEP: validation shared by CreateRun and planning
   bool                ValidateRun(const long experiment_id,
                                   const datetime training_start,const datetime training_end,
                                   const datetime testing_start,const datetime testing_end)
     {
      if(training_start<=0 || testing_end<=0)
        { m_log.Warn("WF run rejected | invalid window bounds"); return(false); }
      if(training_end<=training_start || testing_end<=testing_start)
        { m_log.Warn("WF run rejected | empty window"); return(false); }
      if(testing_start<training_end)
        { m_log.Warn("WF run rejected | test overlaps its training window"); return(false); }

      //--- overlapping windows: the testing span of any run of this experiment
      //--- must be disjoint from the new one
      string rows[];
      if(m_db.Select(StringFormat(
            "SELECT COUNT(*) FROM %s WHERE ExperimentID=%d AND "
            "NOT (TestingEnd<=%d OR TestingStart>=%d)",
            DB_TABLE_WF_RUNS,(int)experiment_id,
            (int)testing_start,(int)testing_end),rows)==1 &&
         StringToInteger(rows[0])>0)
        {
         m_log.Warn("WF run rejected | overlapping testing window");
         return(false);
        }
      return(true);
     }

   //--- register one window (validates first)
   long                CreateRun(const long experiment_id,
                                 const datetime training_start,const datetime training_end,
                                 const datetime testing_start,const datetime testing_end,
                                 const int window_number)
     {
      if(m_db==NULL || !m_db.IsOpen() || m_experiments==NULL)
         return(0);
      if(!m_experiments.IsMutable(experiment_id))
        { m_log.Warn(StringFormat("WF run rejected | experiment #%d is immutable",(int)experiment_id)); return(0); }
      if(!ValidateRun(experiment_id,training_start,training_end,testing_start,testing_end))
         return(0);

      int number = window_number;
      if(number<=0)
        {
         string rows[];
         number = 1;
         if(m_db.Select(StringFormat("SELECT MAX(WindowNumber) FROM %s WHERE ExperimentID=%d",
                                     DB_TABLE_WF_RUNS,(int)experiment_id),rows)==1)
            number = (int)StringToInteger(rows[0])+1;
        }

      const string stamp = TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES);
      const string sql = StringFormat(
         "INSERT INTO %s (ExperimentID,TrainingStart,TrainingEnd,TestingStart,TestingEnd,"
         "WindowNumber,ResultStatus,CreatedAt) VALUES (%d,%d,%d,%d,%d,%d,%d,'%s')",
         DB_TABLE_WF_RUNS,(int)experiment_id,(int)training_start,(int)training_end,
         (int)testing_start,(int)testing_end,number,(int)WF_CREATED,stamp);
      if(m_db.Insert(sql)!=1)
        {
         m_log.Warn(StringFormat("WF run insert failed | experiment #%d",(int)experiment_id));
         return(0);
        }
      string rows[];
      if(m_db.Select(StringFormat("SELECT MAX(RunID) FROM %s",DB_TABLE_WF_RUNS),rows)!=1)
         return(0);
      const long run_id = StringToInteger(rows[0]);
      m_log.Info(StringFormat("WF run #%d created | window %d | train %s..%s | test %s..%s",
                              (int)run_id,number,
                              TimeToString(training_start,TIME_DATE),
                              TimeToString(training_end,TIME_DATE),
                              TimeToString(testing_start,TIME_DATE),
                              TimeToString(testing_end,TIME_DATE)));
      return(run_id);
     }

   bool                RunWindow(const long run_id)
     {
      if(m_db==NULL || !m_db.IsOpen())
         return(false);
      return(m_db.Update(StringFormat(
                "UPDATE %s SET ResultStatus=%d WHERE RunID=%d AND ResultStatus=%d",
                DB_TABLE_WF_RUNS,(int)WF_RUNNING,(int)run_id,(int)WF_CREATED))==1);
     }

   bool                FinishRun(const long run_id,const bool success)
     {
      if(m_db==NULL || !m_db.IsOpen())
         return(false);
      return(m_db.Update(StringFormat(
                "UPDATE %s SET ResultStatus=%d WHERE RunID=%d AND ResultStatus=%d",
                DB_TABLE_WF_RUNS,(int)(success ? WF_FINISHED : WF_FAILED),
                (int)run_id,(int)WF_RUNNING))==1);
     }

   //--- deterministic window planning for the three modes.
   //--- ROLLING: fixed train length, slides by test_len.
   //--- EXPANDING: train start anchored, train end = test start.
   //--- FIXED: disjoint consecutive train/test blocks.
   int                 PlanWindows(const long experiment_id,const ENUM_WF_MODE mode,
                                   const datetime range_start,const datetime range_end,
                                   const int train_seconds,const int test_seconds)
     {
      if(m_db==NULL || train_seconds<=0 || test_seconds<=0 || range_end<=range_start)
         return(0);
      int planned = 0;
      datetime train_start = range_start;
      datetime train_end   = range_start+(datetime)train_seconds;
      datetime test_start  = train_end;
      datetime test_end    = test_start+(datetime)test_seconds;

      while(test_end<=range_end)
        {
         if(CreateRun(experiment_id,train_start,train_end,test_start,test_end,0)>0)
            planned++;
         else
            break;   // validation failure: stop planning, keep determinism

         switch(mode)
           {
            case WF_ROLLING:
               train_start = train_start+(datetime)test_seconds;
               train_end   = train_start+(datetime)train_seconds;
               break;
            case WF_EXPANDING:
               train_end = train_end+(datetime)test_seconds;   // anchored start
               break;
            case WF_FIXED:
               train_start = test_end;
               train_end   = train_start+(datetime)train_seconds;
               break;
           }
         test_start = train_end;
         test_end   = test_start+(datetime)test_seconds;
        }
      m_log.Info(StringFormat("Walk-forward planned | experiment #%d | mode %d | %d windows",
                              (int)experiment_id,(int)mode,planned));
      return(planned);
     }
  };

#endif // __EA_RESEARCH_WALKFORWARD_MQH__
//+------------------------------------------------------------------+
