//+------------------------------------------------------------------+
//|                    EAMarketDigitalTwin/TwinAdapters.mqh          |
//|                        Market Digital Twin — 5 identical consumers|
//|                        (Replay, Training, Risk, Research, AI)   |
//|                        ADR-0022 demonstrates single source truth |
//+------------------------------------------------------------------+
#ifndef __TWIN_ADAPTERS_MQH__
#define __TWIN_ADAPTERS_MQH__

#include <CandleBreakoutEA\EAMarketDigitalTwin\TwinTypes.mqh>
#include <CandleBreakoutEA\EALogger.mqh>

//+------------------------------------------------------------------+
//| Base adapter — records last event and its hashes for validator   |
//| to prove identical dispatch.                                     |
//+------------------------------------------------------------------+
class CTwinBaseConsumer : public ITwinConsumer
  {
protected:
   CLogger            *m_log;
   SMarketEvent        m_last;
   long                m_count;
   long                m_last_hash;
   string              m_name;

public:
                       CTwinBaseConsumer(const string name) : m_log(NULL), m_count(0), m_last_hash(0), m_name(name) { m_last.Reset(); }
   void                Initialize(CLogger &logger) { m_log=&logger; }

   virtual void        OnMarketEvent(const SMarketEvent &event) override
     {
      m_last = event; // value copy — identical bytes
      m_last_hash = event.event_hash != 0 ? event.event_hash : TwinHashEvent(event);
      m_count++;
      // optional per-consumer logging (rate-limited)
      // if(m_log!=NULL && m_count%1000==0) m_log.Info(...);
     }

   virtual string      ConsumerName(void) const override { return(m_name); }

   SMarketEvent        LastEvent(void) const { return(m_last); }
   long                LastHash(void) const { return(m_last_hash); }
   long                Count(void) const { return(m_count); }
   void                Reset(void) { m_last.Reset(); m_count=0; m_last_hash=0; }

   string              ToString(void) const
     {
      return(StringFormat("%s | count %d last_hash %d | last %s %.5f",
                          m_name,(int)m_count,m_last_hash,
                          TimeToString(m_last.time,TIME_DATE|TIME_MINUTES),m_last.close));
     }
  };

//+------------------------------------------------------------------+
//| 5 identical consumers — each owns exactly one module but all     |
//| receive same SMarketEvent copy from TwinEventBus.                |
//+------------------------------------------------------------------+
class CTwinReplayConsumer   : public CTwinBaseConsumer { public: CTwinReplayConsumer(void)   : CTwinBaseConsumer("Replay")   {} };
class CTwinTrainingConsumer : public CTwinBaseConsumer { public: CTwinTrainingConsumer(void) : CTwinBaseConsumer("Training") {} };
class CTwinRiskConsumer     : public CTwinBaseConsumer { public: CTwinRiskConsumer(void)     : CTwinBaseConsumer("Risk")     {} };
class CTwinResearchConsumer : public CTwinBaseConsumer { public: CTwinResearchConsumer(void) : CTwinBaseConsumer("Research") {} };
class CTwinAIConsumer       : public CTwinBaseConsumer { public: CTwinAIConsumer(void)       : CTwinBaseConsumer("AI")       {} };

//+------------------------------------------------------------------+
//| Validator for identical dispatch — checks that all 5 consumers   |
//| have same last_hash and same count after N events.               |
//+------------------------------------------------------------------+
bool TwinValidateIdentical(CTwinBaseConsumer *c1,CTwinBaseConsumer *c2,
                           CTwinBaseConsumer *c3,CTwinBaseConsumer *c4,
                           CTwinBaseConsumer *c5,CLogger &log)
  {
   if(c1==NULL || c2==NULL || c3==NULL || c4==NULL || c5==NULL) return(false);
   long h1=c1.LastHash(), h2=c2.LastHash(), h3=c3.LastHash(), h4=c4.LastHash(), h5=c5.LastHash();
   long cnt1=c1.Count(), cnt2=c2.Count(), cnt3=c3.Count(), cnt4=c4.Count(), cnt5=c5.Count();
   bool hash_identical = (h1==h2 && h2==h3 && h3==h4 && h4==h5 && h1!=0);
   bool count_identical = (cnt1==cnt2 && cnt2==cnt3 && cnt3==cnt4 && cnt4==cnt5);
   if(!hash_identical)
      log.Warn(StringFormat("Twin IDENTICAL FAIL hash | Replay %d Training %d Risk %d Research %d AI %d",h1,h2,h3,h4,h5));
   if(!count_identical)
      log.Warn(StringFormat("Twin IDENTICAL FAIL count | Replay %d Training %d Risk %d Research %d AI %d",(int)cnt1,(int)cnt2,(int)cnt3,(int)cnt4,(int)cnt5));
   if(hash_identical && count_identical)
      log.Info(StringFormat("Twin IDENTICAL PASS | hash %d count %d to 5 consumers",h1,(int)cnt1));
   return(hash_identical && count_identical);
  }

#endif // __TWIN_ADAPTERS_MQH__
//+------------------------------------------------------------------+
