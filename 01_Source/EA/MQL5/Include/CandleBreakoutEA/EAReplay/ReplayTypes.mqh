//+------------------------------------------------------------------+
//|                                EAReplay/ReplayTypes.mqh          |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Replay foundation: shared types           |
//+------------------------------------------------------------------+
#ifndef __EA_REPLAY_TYPES_MQH__
#define __EA_REPLAY_TYPES_MQH__

//+------------------------------------------------------------------+
//| Replay session state (persisted in ReplaySessions)               |
//+------------------------------------------------------------------+
enum ENUM_REPLAY_STATE
  {
   REPLAY_STOPPED     = 0,
   REPLAY_INITIALIZED = 1,
   REPLAY_RUNNING     = 2,
   REPLAY_PAUSED      = 3,
   REPLAY_FINISHED    = 4
  };

//+------------------------------------------------------------------+
//| Playback speeds. STEP = manual stepping only, UNLIMITED = as     |
//| fast as the host advances it.                                    |
//+------------------------------------------------------------------+
enum ENUM_REPLAY_SPEED
  {
   REPLAY_SPEED_STEP     = 0,
   REPLAY_SPEED_1X       = 1,
   REPLAY_SPEED_2X       = 2,
   REPLAY_SPEED_5X       = 5,
   REPLAY_SPEED_10X      = 10,
   REPLAY_SPEED_25X      = 25,
   REPLAY_SPEED_100X     = 100,
   REPLAY_SPEED_UNLIMITED= 1000000
  };

//+------------------------------------------------------------------+
//| One recorded bar, exactly as stored in MarketSnapshots.          |
//| Replay reads ONLY the database - never broker data.              |
//+------------------------------------------------------------------+
struct SReplaySnapshot
  {
   long                snapshot_id;
   datetime            bar_time;
   double              spread;
   double              atr;
   double              atr_ratio;
   double              open, high, low, close;
   double              body_size;
   double              body_percent;
   double              upper_shadow;
   double              lower_shadow;
   double              range;
   double              volatility;
   int                 trend_direction;
   double              trend_strength;
   int                 session;
   int                 hour;
   int                 weekday;
   int                 month;
   int                 quarter;
   int                 broker_offset;

   void                Reset(void)
     {
      snapshot_id = 0; bar_time = 0;
      spread = 0; atr = 0; atr_ratio = 0;
      open = 0; high = 0; low = 0; close = 0;
      body_size = 0; body_percent = 0;
      upper_shadow = 0; lower_shadow = 0;
      range = 0; volatility = 0;
      trend_direction = 0; trend_strength = 0;
      session = 0; hour = 0; weekday = 0; month = 0; quarter = 0;
      broker_offset = 0;
     }
  };

//+------------------------------------------------------------------+
//| Observation / label / trade synchronized to the replay clock     |
//+------------------------------------------------------------------+
struct SReplayObservation
  {
   long                observation_id;
   datetime            bar_time;
   int                 type;
   int                 session, hour, weekday, month;
  };

struct SReplayLabel
  {
   long                label_id;
   int                 lookahead;
   double              future_high, future_low, future_close;
   double              mfe, mae;
   int                 direction;
   int                 breakout_success;
  };

struct SReplayTrade
  {
   long                ticket;
   int                 direction;
   double              lots;
   datetime            entry_time, exit_time;
   double              entry_price, exit_price;
   double              profit;
   int                 exit_reason;
  };

#endif // __EA_REPLAY_TYPES_MQH__
//+------------------------------------------------------------------+
