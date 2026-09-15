//+------------------------------------------------------------------+
//|                              EAData/LabelGenerator.mqh           |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Label Engine: ground-truth outcome labels |
//+------------------------------------------------------------------+
#ifndef __EA_DAL_LABEL_GENERATOR_MQH__
#define __EA_DAL_LABEL_GENERATOR_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EAUtils.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAFeatureBuilder\FeatureValidation.mqh>
#include <CandleBreakoutEA\EAData\DatabaseTypes.mqh>
#include <CandleBreakoutEA\EAData\DatabaseManager.mqh>
#include <CandleBreakoutEA\EAData\ObservationWriter.mqh>

//+------------------------------------------------------------------+
//| STEP 2: direction vocabulary. Ground truth about the past -      |
//| never a prediction, never an input to any trading decision.      |
//+------------------------------------------------------------------+
enum ENUM_DIRECTION_LABEL
  {
   LABEL_UNKNOWN        = 0,
   LABEL_UP             = 1,  // future close beyond +0.5 x bar range
   LABEL_DOWN           = 2,  // future close beyond -0.5 x bar range
   LABEL_RANGE          = 3,  // future close inside the threshold band
   LABEL_FAKE_BREAKOUT  = 4   // breakout observation that reversed on the future
  };

//--- labelling contract
#define LABEL_VERSION         1   // bump only through an ADR
#define LABEL_LOOKAHEAD_BARS  3   // completed bars behind the observed bar
#define LABEL_BATCH_LIMIT    25   // rows labelled per pass
#define LABEL_MOVE_THRESHOLD  0.5 // x observed bar range
#define LABEL_FAKE_THRESHOLD  0.25

//+------------------------------------------------------------------+
//| Generates outcome labels for recorded observations AFTER enough  |
//| future bars exist. Writes through the DAL only; reads only raw   |
//| historical prices; no feature recomputation, no trading impact.  |
//+------------------------------------------------------------------+
class CLabelGenerator
  {
private:
   const CEASettings  *m_set;
   CLogger            *m_log;
   CDatabaseManager   *m_db;
   datetime            m_last_pass;
   int                 m_generated;

   //--- STEP 4: rule set for one candidate label
   bool                ValidateCandidate(const long observation_id,const int lookahead,
                                         const double future_high,const double future_low,
                                         const double future_close)
     {
      if(observation_id<=0)
        { m_log.Warn("Label rejected | missing observation"); return(false); }
      if(lookahead<0)
        { m_log.Warn("Label rejected | negative lookahead"); return(false); }
      if(!CFeatureValidation::IsFinite(future_high) ||
         !CFeatureValidation::IsFinite(future_low) ||
         !CFeatureValidation::IsFinite(future_close))
        { m_log.Warn("Label rejected | invalid future prices"); return(false); }
      if(future_high<future_low ||
         future_close<future_low || future_close>future_high)
        { m_log.Warn("Label rejected | invalid future prices"); return(false); }
      return(true);
     }

public:
                       CLabelGenerator(void) : m_set(NULL), m_log(NULL), m_db(NULL),
                          m_last_pass(0), m_generated(0) {}

   void                Initialize(const CEASettings &settings,CLogger &logger,CDatabaseManager &db)
     {
      m_set = &settings;
      m_log = &logger;
      m_db  = &db;
      m_log.Info(StringFormat("Label Engine initialized | lookahead %d bars | label v%d",
                              LABEL_LOOKAHEAD_BARS,LABEL_VERSION));
     }

   //--- STEP 4 validation of stored label rows (integrity re-check)
   bool                ValidateLabels(void)
     {
      if(m_db==NULL || !m_db.IsOpen())
         return(false);
      string rows[];
      if(m_db.Select(StringFormat(
            "SELECT COUNT(*) FROM %s l LEFT JOIN %s o ON o.ObservationID=l.ObservationID "
            "WHERE o.ObservationID IS NULL OR l.FutureHigh<l.FutureLow OR l.LookaheadBars<0",
            DB_TABLE_LABELS,DB_TABLE_OBSERVATIONS),rows)!=1)
         return(false);
      return(StringToInteger(rows[0])==0);
     }

   //--- STEP 3: label every observation whose full future window now exists
   int                 GenerateLabels(const int limit)
     {
      if(m_db==NULL || !m_db.IsOpen() || m_set==NULL)
         return(0);

      string rows[];
      const int found = m_db.Select(StringFormat(
         "SELECT o.ObservationID,o.BarTime,o.ObservationType FROM %s o "
         "LEFT JOIN %s l ON l.ObservationID=o.ObservationID AND l.LabelVersion=%d "
         "WHERE l.LabelID IS NULL ORDER BY o.BarTime ASC LIMIT %d",
         DB_TABLE_OBSERVATIONS,DB_TABLE_LABELS,LABEL_VERSION,limit),rows);
      if(found<=0)
         return(0);

      int created = 0;
      for(int i=0; i<found; i++)
        {
         string cells[];
         const int parts = StringSplit(rows[i],';',cells);
         if(parts!=3)
            continue;
         const long     obs_id   = StringToInteger(cells[0]);
         const datetime bar_time = (datetime)StringToInteger(cells[1]);
         const int      obs_type = (int)StringToInteger(cells[2]);

         //--- labels only after sufficient future bars exist
         const int shift = iBarShift(m_set.symbol_name,m_set.main_timeframe,bar_time);
         if(shift<0)
            continue;
         if(shift<LABEL_LOOKAHEAD_BARS)
            break;   // rows are ordered by BarTime: everything after is even newer

         //--- raw future window behind the observed bar
         double future_high = 0.0, future_low = 0.0;
         for(int k=1; k<=LABEL_LOOKAHEAD_BARS; k++)
           {
            const double h = iHigh(m_set.symbol_name,m_set.main_timeframe,shift-k);
            const double l = iLow (m_set.symbol_name,m_set.main_timeframe,shift-k);
            if(h<=0.0 || l<=0.0)
              { future_high = 0.0; break; }   // incomplete window
            if(k==1 || h>future_high)
               future_high = h;
            if(k==1 || l<future_low)
               future_low = l;
           }
         const double future_close = iClose(m_set.symbol_name,m_set.main_timeframe,
                                            shift-LABEL_LOOKAHEAD_BARS);
         const double ref = iClose(m_set.symbol_name,m_set.main_timeframe,shift);
         const double rng = iHigh (m_set.symbol_name,m_set.main_timeframe,shift)-
                            iLow  (m_set.symbol_name,m_set.main_timeframe,shift);
         if(future_high<=0.0 || ref<=0.0 || rng<=0.0)
            continue;   // incomplete window or bad series: leave the row pending

         if(!ValidateCandidate(obs_id,LABEL_LOOKAHEAD_BARS,future_high,future_low,future_close))
            continue;

         //--- STEP 2: ground-truth direction + breakout outcome
         const double net = future_close-ref;
         int    direction = LABEL_RANGE;
         int    success   = 0;
         if(obs_type==(int)OBS_BREAKOUT_UP)
           {
            if(net>=LABEL_MOVE_THRESHOLD*rng)
              { direction = LABEL_UP;   success = 1; }
            else if(net<=-LABEL_FAKE_THRESHOLD*rng)
                 direction = LABEL_FAKE_BREAKOUT;
           }
         else if(obs_type==(int)OBS_BREAKOUT_DOWN)
           {
            if(net<=-LABEL_MOVE_THRESHOLD*rng)
              { direction = LABEL_DOWN; success = 1; }
            else if(net>=LABEL_FAKE_THRESHOLD*rng)
                 direction = LABEL_FAKE_BREAKOUT;
           }
         else
           {
            if(net>=LABEL_MOVE_THRESHOLD*rng)
               direction = LABEL_UP;
            else if(net<=-LABEL_MOVE_THRESHOLD*rng)
               direction = LABEL_DOWN;
           }

         const double mfe = future_high-ref;   // best excursion above the bar close
         const double mae = ref-future_low;    // worst excursion below the bar close
         const string stamp = TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES);
         const string sql = StringFormat(
            "INSERT INTO %s (ObservationID,LabelVersion,LookaheadBars,FutureHigh,FutureLow,"
            "FutureClose,MaxFavorableExcursion,MaxAdverseExcursion,DirectionLabel,"
            "BreakoutSuccess,LabelQuality,GeneratedAt) VALUES (%d,%d,%d,%s,%s,%s,%s,%s,%d,%d,%d,'%s')",
            DB_TABLE_LABELS,(int)obs_id,LABEL_VERSION,LABEL_LOOKAHEAD_BARS,
            DoubleToString(future_high,8),DoubleToString(future_low,8),
            DoubleToString(future_close,8),DoubleToString(mfe,8),DoubleToString(mae,8),
            direction,success,100,stamp);

         if(m_db.Insert(sql)==1)
           {
            created++;
            m_generated++;
           }
         else
            m_log.Warn(StringFormat("Label insert failed | observation #%d",(int)obs_id));
        }

      if(created>0)
         m_log.Debug(StringFormat("Labels generated | +%d | total %d",created,m_generated));
      return(created);
     }

   //--- STEP 3: cheap per-tick entry; one batch pass per completed bar
   void                UpdatePendingLabels(void)
     {
      if(m_db==NULL || !m_db.IsOpen())
         return;
      const datetime bar = iTime(m_set.symbol_name,m_set.main_timeframe,0);
      if(bar<=0 || bar==m_last_pass)
         return;
      m_last_pass = bar;
      GenerateLabels(LABEL_BATCH_LIMIT);
     }

   int                 LabelsGenerated(void) const { return(m_generated); }
  };

#endif // __EA_DAL_LABEL_GENERATOR_MQH__
//+------------------------------------------------------------------+
