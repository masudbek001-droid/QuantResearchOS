//+------------------------------------------------------------------+
//|                    EAMarketDigitalTwin/TwinClock.mqh             |
//|                        Market Digital Twin — deterministic virtual|
//|                        clock (ADR-0022)                          |
//+------------------------------------------------------------------+
#ifndef __TWIN_CLOCK_MQH__
#define __TWIN_CLOCK_MQH__

//+------------------------------------------------------------------+
//| Deterministic virtual clock — advances only via Twin.Next().     |
//| Never reads TimeCurrent() except at Twin creation for stamp.     |
//| All consumers see same time per event_id.                        |
//+------------------------------------------------------------------+
class CTwinClock
  {
private:
   datetime            m_current;
   long                m_bar_index;   // 0-based
   long                m_total;
   bool                m_started;

public:
                       CTwinClock(void) : m_current(0), m_bar_index(-1), m_total(0), m_started(false) {}

   void                Initialize(const datetime start_time,const long total_bars)
     {
      m_current   = start_time;
      m_total     = total_bars;
      m_bar_index = -1;
      m_started   = false;
     }

   bool                HasNext(void) const { return(m_bar_index + 1 < m_total); }
   bool                HasPrev(void) const { return(m_bar_index > 0); }

   //--- advance to next bar/tick; returns new time
   datetime            Advance(const datetime next_time)
     {
      m_bar_index++;
      m_current = next_time;
      m_started = true;
      return(m_current);
     }

   datetime            Retreat(const datetime prev_time)
     {
      if(m_bar_index>0) m_bar_index--;
      m_current = prev_time;
      return(m_current);
     }

   datetime            CurrentTime(void) const { return(m_current); }
   long                CurrentIndex(void) const { return(m_bar_index); }
   long                TotalBars(void) const { return(m_total); }
   bool                IsStarted(void) const { return(m_started); }
   void                Reset(void) { m_current=0; m_bar_index=-1; m_total=0; m_started=false; }

   string              ToString(void) const
     {
      return(StringFormat("clock idx %d/%d time %s started %s",
                          (int)m_bar_index,(int)m_total,
                          TimeToString(m_current,TIME_DATE|TIME_MINUTES),
                          m_started ? "true" : "false"));
     }
  };

#endif // __TWIN_CLOCK_MQH__
//+------------------------------------------------------------------+
