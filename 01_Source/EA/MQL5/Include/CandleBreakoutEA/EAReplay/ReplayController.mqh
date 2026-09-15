//+------------------------------------------------------------------+
//|                             EAReplay/ReplayController.mqh        |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Replay: session control (TASK 0013)       |
//+------------------------------------------------------------------+
#ifndef __EA_REPLAY_CONTROLLER_MQH__
#define __EA_REPLAY_CONTROLLER_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAData\DatabaseTypes.mqh>
#include <CandleBreakoutEA\EAData\DatabaseManager.mqh>
#include <CandleBreakoutEA\EAReplay\ReplayTypes.mqh>
#include <CandleBreakoutEA\EAReplay\ReplayValidator.mqh>
#include <CandleBreakoutEA\EAReplay\ReplayTimeline.mqh>

//+------------------------------------------------------------------+
//| Controls one replay session. All state lives in the database     |
//| (ReplaySessions); playback data comes only from the recorded     |
//| tables. Integrity is checked before start and after every        |
//| navigation step - a failure stops the replay automatically.      |
//+------------------------------------------------------------------+
class CReplayController
  {
private:
   const CEASettings  *m_set;
   CLogger            *m_log;
   CDatabaseManager   *m_db;
   CReplayValidator    m_validator;
   CReplayTimeline     m_timeline;

   long                m_replay_id;
   int                 m_symbol_id;
   int                 m_timeframe_id;
   int                 m_dataset_version;
   datetime            m_window_start;
   datetime            m_window_end;
   ENUM_REPLAY_STATE   m_state;
   ENUM_REPLAY_SPEED   m_speed;

   bool                Persist(const datetime replay_time,const int bar_index)
     {
      if(m_db==NULL || !m_db.IsOpen() || m_replay_id<=0)
         return(false);
      return(m_db.Update(StringFormat(
                "UPDATE %s SET CurrentReplayTime=%d,CurrentBar=%d,ReplayState=%d,ReplaySpeed=%d "
                "WHERE ReplayID=%d",
                DB_TABLE_REPLAY,(int)replay_time,bar_index,(int)m_state,(int)m_speed,
                (int)m_replay_id))==1);
     }

   //--- TASK 0015 requirement: integrity failure halts the session
   bool                IntegrityGate(void)
     {
      if(m_validator.ValidateReplayIntegrity(m_dataset_version,m_symbol_id,
                                             m_timeframe_id,m_window_start,m_window_end))
         return(true);
      m_log.Warn(StringFormat("Replay #%d stopped automatically | integrity check failed",
                              (int)m_replay_id));
      m_state = REPLAY_STOPPED;
      Persist(m_timeline.CurrentTime(),m_timeline.CurrentIndex());
      return(false);
     }

public:
                       CReplayController(void) : m_set(NULL), m_log(NULL), m_db(NULL),
                          m_replay_id(0), m_symbol_id(0), m_timeframe_id(0),
                          m_dataset_version(0), m_window_start(0), m_window_end(0),
                          m_state(REPLAY_STOPPED), m_speed(REPLAY_SPEED_STEP) {}

   void                Initialize(const CEASettings &settings,CLogger &logger,CDatabaseManager &db)
     {
      m_set = &settings;
      m_log = &logger;
      m_db  = &db;
      m_validator.Initialize(settings,logger,db);
      m_timeline.Initialize(settings,logger,db);
     }

   //--- create a replay session over a validated window
   long                InitializeReplay(const int dataset_version,const int symbol_id,
                                        const int timeframe_id,const datetime start_time,
                                        const datetime end_time)
     {
      if(m_db==NULL || !m_db.IsOpen())
         return(0);
      if(!m_validator.ValidateReplayIntegrity(dataset_version,symbol_id,timeframe_id,
                                              start_time,end_time))
        {
         m_log.Warn("Replay initialization rejected | integrity gate failed");
         return(0);
        }
      if(!m_timeline.LoadReplayWindow(dataset_version,symbol_id,timeframe_id,start_time,end_time))
         return(0);

      const string stamp = TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES);
      const string sql = StringFormat(
         "INSERT INTO %s (DatasetVersion,SymbolID,TimeframeID,StartTime,EndTime,"
         "CurrentReplayTime,ReplayState,ReplaySpeed,CurrentBar,TotalBars,CreatedAt) "
         "VALUES (%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,'%s')",
         DB_TABLE_REPLAY,dataset_version,symbol_id,timeframe_id,
         (int)start_time,(int)end_time,(int)start_time,
         (int)REPLAY_INITIALIZED,(int)m_speed,0,m_timeline.TotalBars(),stamp);
      if(m_db.Insert(sql)!=1)
        {
         m_log.Warn("Replay session insert failed");
         return(0);
        }

      string rows[];
      if(m_db.Select(StringFormat("SELECT MAX(ReplayID) FROM %s",DB_TABLE_REPLAY),rows)!=1)
         return(0);
      m_replay_id       = StringToInteger(rows[0]);
      m_dataset_version = dataset_version;
      m_symbol_id       = symbol_id;
      m_timeframe_id    = timeframe_id;
      m_window_start    = start_time;
      m_window_end      = end_time;
      m_state           = REPLAY_INITIALIZED;
      m_log.Info(StringFormat("Replay #%d initialized | %d bars",
                              (int)m_replay_id,m_timeline.TotalBars()));
      return(m_replay_id);
     }

   bool                StartReplay(void)
     {
      if(m_state!=REPLAY_INITIALIZED && m_state!=REPLAY_PAUSED && m_state!=REPLAY_STOPPED)
         return(false);
      if(!IntegrityGate())
         return(false);
      m_state = REPLAY_RUNNING;
      return(Persist(m_timeline.CurrentTime(),m_timeline.CurrentIndex()));
     }

   bool                PauseReplay(void)
     {
      if(m_state!=REPLAY_RUNNING)
         return(false);
      m_state = REPLAY_PAUSED;
      return(Persist(m_timeline.CurrentTime(),m_timeline.CurrentIndex()));
     }

   bool                ResumeReplay(void)
     {
      if(m_state!=REPLAY_PAUSED)
         return(false);
      if(!IntegrityGate())
         return(false);
      m_state = REPLAY_RUNNING;
      return(Persist(m_timeline.CurrentTime(),m_timeline.CurrentIndex()));
     }

   bool                StopReplay(void)
     {
      if(m_replay_id<=0)
         return(false);
      m_state = REPLAY_STOPPED;
      return(Persist(m_timeline.CurrentTime(),m_timeline.CurrentIndex()));
     }

   //--- jump the replay clock; the timeline finds the recorded bar
   bool                SeekTo(const datetime moment)
     {
      if(m_state!=REPLAY_RUNNING && m_state!=REPLAY_PAUSED && m_state!=REPLAY_INITIALIZED)
         return(false);
      if(!m_timeline.JumpToTime(moment))
         return(false);
      return(Persist(m_timeline.CurrentTime(),m_timeline.CurrentIndex()));
     }

   bool                StepForward(void)
     {
      if(m_state==REPLAY_STOPPED)
         return(false);
      if(!m_timeline.MoveNext())
        {
         if(m_state==REPLAY_RUNNING)
           {
            m_state = REPLAY_FINISHED;
            m_log.Info(StringFormat("Replay #%d finished",(int)m_replay_id));
           }
         return(Persist(m_timeline.CurrentTime(),m_timeline.CurrentIndex()));
        }
      if(!IntegrityGate())
         return(false);
      return(Persist(m_timeline.CurrentTime(),m_timeline.CurrentIndex()));
     }

   bool                StepBackward(void)
     {
      if(m_state==REPLAY_STOPPED)
         return(false);
      if(!m_timeline.MovePrevious())
         return(false);
      if(m_state==REPLAY_FINISHED)
         m_state = REPLAY_PAUSED;
      if(!IntegrityGate())
         return(false);
      return(Persist(m_timeline.CurrentTime(),m_timeline.CurrentIndex()));
     }

   //--- playback speed control (1x..100x, unlimited, step)
   bool                SetSpeed(const ENUM_REPLAY_SPEED speed)
     {
      m_speed = speed;
      return(Persist(m_timeline.CurrentTime(),m_timeline.CurrentIndex()));
     }

   //--- host-driven clock: advances RUNNING sessions by elapsed real time
   void                Advance(const uint elapsed_ms)
     {
      if(m_state!=REPLAY_RUNNING)
         return;
      if(m_speed==REPLAY_SPEED_STEP)
         return;                       // manual stepping only
      if(m_speed==REPLAY_SPEED_UNLIMITED)
        {
         while(m_timeline.MoveNext()) {}
         m_state = REPLAY_FINISHED;
         Persist(m_timeline.CurrentTime(),m_timeline.CurrentIndex());
         return;
        }
      const int tf_ms = PeriodSeconds((ENUM_TIMEFRAMES)m_timeframe_id)*1000;
      const long virtual_ms = (long)elapsed_ms*(long)m_speed;
      const int bars = (int)(virtual_ms/(tf_ms>0 ? tf_ms : 1));
      for(int i=0; i<bars; i++)
         if(!m_timeline.MoveNext())
           {
            m_state = REPLAY_FINISHED;
            break;
           }
      Persist(m_timeline.CurrentTime(),m_timeline.CurrentIndex());
     }

   //--- read access for future replay consumers
   ENUM_REPLAY_STATE   State(void) const { return(m_state); }
   ENUM_REPLAY_SPEED   Speed(void) const { return(m_speed); }
   long                ReplayId(void) const { return(m_replay_id); }
   CReplayTimeline    *Timeline(void) { return(&m_timeline); }
   CReplayValidator   *Validator(void) { return(&m_validator); }
  };

#endif // __EA_REPLAY_CONTROLLER_MQH__
//+------------------------------------------------------------------+
