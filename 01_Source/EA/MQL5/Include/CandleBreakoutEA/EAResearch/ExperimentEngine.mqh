//+------------------------------------------------------------------+
//|                          EAResearch/ExperimentEngine.mqh         |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Research: experiment lifecycle (Task 0016)|
//+------------------------------------------------------------------+
#ifndef __EA_RESEARCH_EXPERIMENT_MQH__
#define __EA_RESEARCH_EXPERIMENT_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAData\DatabaseTypes.mqh>
#include <CandleBreakoutEA\EAData\DatabaseManager.mqh>

//+------------------------------------------------------------------+
//| One experiment row                                               |
//+------------------------------------------------------------------+
struct SExperimentInfo
  {
   long                id;
   string              name;
   int                 dataset_version;
   int                 feature_version;
   int                 label_version;
   int                 quality_version;
   int                 replay_version;
   string              config_hash;
   datetime            start_time;
   datetime            end_time;
   int                 duration_seconds;
   ENUM_EXPERIMENT_STATUS status;
   string              notes;
  };

//+------------------------------------------------------------------+
//| TASK 0016: experiment lifecycle. Every experiment pins the exact |
//| dataset/feature/label/quality/replay versions it runs on, so all |
//| results are reproducible. Completed experiments are IMMUTABLE -  |
//| no update path touches them.                                     |
//+------------------------------------------------------------------+
class CExperimentEngine
  {
private:
   const CEASettings  *m_set;
   CLogger            *m_log;
   CDatabaseManager   *m_db;

   int                 StatusOf(const long experiment_id)
     {
      string rows[];
      if(m_db.Select(StringFormat("SELECT Status FROM %s WHERE ExperimentID=%d",
                                  DB_TABLE_EXPERIMENTS,(int)experiment_id),rows)!=1)
         return(-1);
      return((int)StringToInteger(rows[0]));
     }

public:
                       CExperimentEngine(void) : m_set(NULL), m_log(NULL), m_db(NULL) {}

   void                Initialize(const CEASettings &settings,CLogger &logger,CDatabaseManager &db)
     {
      m_set = &settings;
      m_log = &logger;
      m_db  = &db;
      m_log.Info("Experiment Engine initialized");
     }

   //--- register a new experiment; versions are pinned at creation
   long                CreateExperiment(const string name,const int dataset_version,
                                        const int feature_version,const int label_version,
                                        const int quality_version,const string config_hash,
                                        const string notes)
     {
      if(m_db==NULL || !m_db.IsOpen())
         return(0);
      if(StringLen(name)==0 || StringLen(config_hash)==0)
        { m_log.Warn("Experiment rejected | empty name or configuration hash"); return(0); }
      if(dataset_version<=0 || feature_version<=0 || label_version<=0 || quality_version<=0)
        { m_log.Warn("Experiment rejected | invalid version pins"); return(0); }

      const string stamp = TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES);
      const string sql = StringFormat(
         "INSERT INTO %s (ExperimentName,DatasetVersion,FeatureVersion,LabelVersion,"
         "QualityVersion,ReplayVersion,ConfigurationHash,Status,Notes,CreatedAt) "
         "VALUES ('%s',%d,%d,%d,%d,%d,'%s',%d,'%s','%s')",
         DB_TABLE_EXPERIMENTS,name,dataset_version,feature_version,label_version,
         quality_version,DB_SCHEMA_VERSION,config_hash,
         (int)EXPERIMENT_CREATED,notes,stamp);
      if(m_db.Insert(sql)!=1)
        {
         m_log.Warn(StringFormat("Experiment insert failed | %s",name));
         return(0);
        }
      string rows[];
      if(m_db.Select(StringFormat("SELECT MAX(ExperimentID) FROM %s",DB_TABLE_EXPERIMENTS),rows)!=1)
         return(0);
      const long id = StringToInteger(rows[0]);
      m_log.Info(StringFormat("Experiment #%d created | %s | dataset v%d | hash %s",
                              (int)id,name,dataset_version,config_hash));
      return(id);
     }

   bool                StartExperiment(const long experiment_id)
     {
      if(m_db==NULL || !m_db.IsOpen())
         return(false);
      const int status = StatusOf(experiment_id);
      if(status!=(int)EXPERIMENT_CREATED)
        { m_log.Warn(StringFormat("Experiment #%d start rejected | status %d",(int)experiment_id,status)); return(false); }
      return(m_db.Update(StringFormat(
                "UPDATE %s SET Status=%d,StartTime=%d WHERE ExperimentID=%d",
                DB_TABLE_EXPERIMENTS,(int)EXPERIMENT_RUNNING,(int)TimeCurrent(),
                (int)experiment_id))==1);
     }

   //--- completion seals the experiment: no further modification is possible
   bool                FinishExperiment(const long experiment_id)
     {
      if(m_db==NULL || !m_db.IsOpen())
         return(false);
      const int status = StatusOf(experiment_id);
      if(status!=(int)EXPERIMENT_RUNNING)
        { m_log.Warn(StringFormat("Experiment #%d finish rejected | status %d",(int)experiment_id,status)); return(false); }
      string rows[];
      datetime start = 0;
      if(m_db.Select(StringFormat("SELECT StartTime FROM %s WHERE ExperimentID=%d",
                                  DB_TABLE_EXPERIMENTS,(int)experiment_id),rows)==1)
         start = (datetime)StringToInteger(rows[0]);
      const datetime now = TimeCurrent();
      const long duration = (start>0 && now>start ? (long)(now-start) : 0);
      const bool ok = m_db.Update(StringFormat(
                       "UPDATE %s SET Status=%d,EndTime=%d,DurationSeconds=%d WHERE ExperimentID=%d",
                       DB_TABLE_EXPERIMENTS,(int)EXPERIMENT_COMPLETED,(int)now,
                       (int)duration,(int)experiment_id))==1;
      if(ok)
         m_log.Info(StringFormat("Experiment #%d completed in %d s | immutable from now on",
                                 (int)experiment_id,(int)duration));
      return(ok);
     }

   bool                CancelExperiment(const long experiment_id)
     {
      if(m_db==NULL || !m_db.IsOpen())
         return(false);
      const int status = StatusOf(experiment_id);
      if(status!=(int)EXPERIMENT_CREATED && status!=(int)EXPERIMENT_RUNNING)
        { m_log.Warn(StringFormat("Experiment #%d cancel rejected | status %d",(int)experiment_id,status)); return(false); }
      return(m_db.Update(StringFormat(
                "UPDATE %s SET Status=%d,EndTime=%d WHERE ExperimentID=%d",
                DB_TABLE_EXPERIMENTS,(int)EXPERIMENT_CANCELLED,(int)TimeCurrent(),
                (int)experiment_id))==1);
     }

   bool                GetExperiment(const long experiment_id,SExperimentInfo &info)
     {
      if(m_db==NULL || !m_db.IsOpen())
         return(false);
      string rows[];
      if(m_db.Select(StringFormat(
            "SELECT ExperimentID,ExperimentName,DatasetVersion,FeatureVersion,LabelVersion,"
            "QualityVersion,ReplayVersion,ConfigurationHash,StartTime,EndTime,"
            "DurationSeconds,Status,Notes FROM %s WHERE ExperimentID=%d",
            DB_TABLE_EXPERIMENTS,(int)experiment_id),rows)!=1)
         return(false);
      string c[];
      if(StringSplit(rows[0],';',c)!=13)
         return(false);
      info.id               = StringToInteger(c[0]);
      info.name             = c[1];
      info.dataset_version  = (int)StringToInteger(c[2]);
      info.feature_version  = (int)StringToInteger(c[3]);
      info.label_version    = (int)StringToInteger(c[4]);
      info.quality_version  = (int)StringToInteger(c[5]);
      info.replay_version   = (int)StringToInteger(c[6]);
      info.config_hash      = c[7];
      info.start_time       = (datetime)StringToInteger(c[8]);
      info.end_time         = (datetime)StringToInteger(c[9]);
      info.duration_seconds = (int)StringToInteger(c[10]);
      info.status           = (ENUM_EXPERIMENT_STATUS)StringToInteger(c[11]);
      info.notes            = c[12];
      return(true);
     }

   int                 ListExperiments(string &lines[])
     {
      ArrayResize(lines,0);
      if(m_db==NULL || !m_db.IsOpen())
         return(-1);
      return(m_db.Select(StringFormat(
                "SELECT ExperimentID,ExperimentName,DatasetVersion,Status,CreatedAt "
                "FROM %s ORDER BY ExperimentID ASC",DB_TABLE_EXPERIMENTS),lines));
     }

   //--- immutability guard shared with the other research engines
   bool                IsMutable(const long experiment_id)
     {
      const int status = StatusOf(experiment_id);
      return(status==(int)EXPERIMENT_CREATED || status==(int)EXPERIMENT_RUNNING);
     }
  };

#endif // __EA_RESEARCH_EXPERIMENT_MQH__
//+------------------------------------------------------------------+
