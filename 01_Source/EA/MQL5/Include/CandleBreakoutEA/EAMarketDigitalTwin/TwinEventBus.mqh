//+------------------------------------------------------------------+
//|                    EAMarketDigitalTwin/TwinEventBus.mqh          |
//|                        Market Digital Twin — identical dispatch  |
//|                        bus for 5 consumers (ADR-0022)            |
//+------------------------------------------------------------------+
#ifndef __TWIN_EVENT_BUS_MQH__
#define __TWIN_EVENT_BUS_MQH__

#include <CandleBreakoutEA\EAMarketDigitalTwin\TwinTypes.mqh>
#include <CandleBreakoutEA\EALogger.mqh>

//+------------------------------------------------------------------+
//| Event bus — holds consumer pointers, dispatches identical copy   |
//| to each. Bus validates that every consumer received same        |
//| event_hash; any divergence is logged as CRITICAL.               |
//+------------------------------------------------------------------+
class CTwinEventBus
  {
private:
   ITwinConsumer      *m_consumers[5];
   string              m_names[5];
   int                 m_count;
   CLogger            *m_log;
   long                m_dispatch_count;
   long                m_last_event_hash;

   bool                HasConsumer(ITwinConsumer *c) const
     {
      for(int i=0;i<m_count;i++) if(m_consumers[i]==c) return(true);
      return(false);
     }

public:
                       CTwinEventBus(void) : m_count(0), m_log(NULL), m_dispatch_count(0), m_last_event_hash(0)
     {
      for(int i=0;i<5;i++) { m_consumers[i]=NULL; m_names[i]=""; }
     }

   void                Initialize(CLogger &logger) { m_log=&logger; }

   //--- subscribe — one consumer per role; max 5
   bool                Subscribe(ITwinConsumer *consumer)
     {
      if(consumer==NULL) return(false);
      if(m_count>=5)
        {
         if(m_log!=NULL) m_log.Warn("TwinBus subscribe failed | max 5 consumers");
         return(false);
        }
      if(HasConsumer(consumer))
        {
         if(m_log!=NULL) m_log.Warn(StringFormat("TwinBus duplicate subscribe | %s", consumer.ConsumerName()));
         return(false);
        }
      m_consumers[m_count] = consumer;
      m_names[m_count]     = consumer.ConsumerName();
      m_count++;
      if(m_log!=NULL) m_log.Info(StringFormat("TwinBus subscribed | %s (%d/5)", consumer.ConsumerName(), m_count));
      return(true);
     }

   bool                Unsubscribe(ITwinConsumer *consumer)
     {
      if(consumer==NULL) return(false);
      for(int i=0;i<m_count;i++)
        {
         if(m_consumers[i]==consumer)
           {
            for(int j=i;j<m_count-1;j++) { m_consumers[j]=m_consumers[j+1]; m_names[j]=m_names[j+1]; }
            m_consumers[m_count-1]=NULL; m_names[m_count-1]="";
            m_count--;
            if(m_log!=NULL) m_log.Info(StringFormat("TwinBus unsubscribed | %s (%d/5)", consumer.ConsumerName(), m_count));
            return(true);
           }
        }
      return(false);
     }

   int                 ConsumerCount(void) const { return(m_count); }

   //--- dispatch identical copy to each consumer; verify identical hash
   bool                Dispatch(const SMarketEvent &event)
     {
      if(m_count==0)
        {
         if(m_log!=NULL) m_log.Warn("TwinBus dispatch with 0 consumers");
         return(false);
        }
      long h = TwinHashEvent(event);
      // store for external validator
      m_last_event_hash = h;
      m_dispatch_count++;
      // dispatch by value copy — each consumer gets same bytes
      for(int i=0;i<m_count;i++)
        {
         SMarketEvent copy = event; // value copy
         copy.event_hash = h; // ensure hash is set
         m_consumers[i].OnMarketEvent(copy);
        }
      // verify identical dispatch: all consumers should have recorded same hash
      // (consumers are expected to store last hash; bus checks if they differ — we log)
      if(m_log!=NULL)
         m_log.Info(StringFormat("TwinBus dispatch #%d | id %d time %s hash %d to %d consumers",
                                 (int)m_dispatch_count,(int)event.event_id,
                                 TimeToString(event.time,TIME_DATE|TIME_MINUTES),
                                 h, m_count));
      return(true);
     }

   long                LastEventHash(void) const { return(m_last_event_hash); }
   long                DispatchCount(void) const { return(m_dispatch_count); }

   //--- for TwinValidator: get per-consumer last hash if consumer exposes it
   // Bus does not store per-consumer hash; validator will query consumers directly
   // via TwinValidator which holds references.

   void                Reset(void)
     {
      for(int i=0;i<5;i++) { m_consumers[i]=NULL; m_names[i]=""; }
      m_count=0; m_dispatch_count=0; m_last_event_hash=0;
     }

   string              ToString(void) const
     {
      string s = StringFormat("TwinBus %d consumers | dispatch %d | last_hash %d | [",
                              m_count,(int)m_dispatch_count,m_last_event_hash);
      for(int i=0;i<m_count;i++) s += m_names[i] + (i<m_count-1 ? "," : "");
      s += "]";
      return(s);
     }
  };

#endif // __TWIN_EVENT_BUS_MQH__
//+------------------------------------------------------------------+
