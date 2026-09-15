//+------------------------------------------------------------------+
//|                                                     EALogger.mqh |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Single place that writes to the log       |
//+------------------------------------------------------------------+
#ifndef __EA_LOGGER_MQH__
#define __EA_LOGGER_MQH__

#include <CandleBreakoutEA\EASettings.mqh>

//+------------------------------------------------------------------+
//| Every important action of the EA is routed through this class so |
//| the Experts tab stays consistent and filterable.                 |
//|                                                                  |
//| Standard line:  <timestamp> [CBEA <magic> <symbol>] [TAG] text   |
//| Allowed tags:   INFO WARNING ERROR TRADE EXIT BREAK EVEN MOMENTUM|
//| The trade ticket is embedded in the message text when available. |
//+------------------------------------------------------------------+
class CLogger
  {
private:
   string              m_id;      // "[CBEA <magic> <symbol>] "
   ENUM_LOG_LEVEL      m_level;
   bool                m_enabled;

   void                Write(const string tag,const string message) const
     {
      if(!m_enabled)
         return;
      Print(TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS)," ",m_id,"[",tag,"] ",message);
     }

public:
                       CLogger(void) : m_id("[CBEA] "), m_level(LOG_INFO), m_enabled(true) {}

   void                Init(const ulong magic,const string symbol,const ENUM_LOG_LEVEL level)
     {
      m_id    = StringFormat("[CBEA %I64u %s] ",magic,symbol);
      m_level = level;
     }

   void                Enable(const bool enabled) { m_enabled = enabled; }

   //--- level-gated severities
   void                Error(const string message) const
     {
      if(m_level>=LOG_ERRORS)
         Write("ERROR",message);
     }
   void                Warn(const string message) const
     {
      if(m_level>=LOG_WARNINGS)
         Write("WARNING",message);
     }
   void                Info(const string message) const
     {
      if(m_level>=LOG_INFO)
         Write("INFO",message);
     }
   //--- diagnostics, printed with the INFO tag at the top verbosity only
   void                Debug(const string message) const
     {
      if(m_level>=LOG_DEBUG)
         Write("INFO",message);
     }

   //--- audit trail, always printed regardless of verbosity
   void                Trade(const string message) const    { Write("TRADE",message); }
   void                Exit(const string message) const     { Write("EXIT",message); }
   void                BreakEven(const string message) const{ Write("BREAK EVEN",message); }
   void                Momentum(const string message) const { Write("MOMENTUM",message); }
  };

#endif // __EA_LOGGER_MQH__
//+------------------------------------------------------------------+
