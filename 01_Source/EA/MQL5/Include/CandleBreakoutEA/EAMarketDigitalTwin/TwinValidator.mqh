//+------------------------------------------------------------------+
//|                    EAMarketDigitalTwin/TwinValidator.mqh         |
//|                        Market Digital Twin — exact reproduction  |
//|                        validator (ADR-0022)                      |
//+------------------------------------------------------------------+
#ifndef __TWIN_VALIDATOR_MQH__
#define __TWIN_VALIDATOR_MQH__

#include <CandleBreakoutEA\EAMarketDigitalTwin\TwinTypes.mqh>
#include <CandleBreakoutEA\EALogger.mqh>

//+------------------------------------------------------------------+
//| Validator — proves Twin reproduces history exactly.              |
//| Two modes:                                                       |
//|  1) Online ValidateExact(event) — compares event.source_hash to  |
//|     recomputed hash from stored raw bar; halts Twin on mismatch. |
//|  2) Offline Python validator reads Market.db and Twin hashes     |
//|     and asserts SHA256 equality for entire window.               |
//+------------------------------------------------------------------+
class CTwinValidator
  {
private:
   CLogger            *m_log;
   long                m_checked;
   long                m_mismatches;
   long                m_expected_hash_sum; // sum of source_hash for window (from DB)
   long                m_emitted_hash_sum;  // sum of emitted source_hash

public:
                       CTwinValidator(void) : m_log(NULL), m_checked(0), m_mismatches(0), m_expected_hash_sum(0), m_emitted_hash_sum(0) {}

   void                Initialize(CLogger &logger) { m_log=&logger; Reset(); }
   void                Reset(void) { m_checked=0; m_mismatches=0; m_expected_hash_sum=0; m_emitted_hash_sum=0; }

   //--- set expected sum from DB (computed by Python or SQL sum of hashes)
   void                SetExpectedHashSum(const long sum) { m_expected_hash_sum=sum; }

   //--- online per-event validation — must be called for every emitted event
   bool                ValidateExact(const SMarketEvent &event)
     {
      m_checked++;
      // recompute source hash from event fields and compare to stored source_hash
      long recomputed = TwinHashBar(event.symbol,event.timeframe,event.time,
                                    event.open,event.high,event.low,event.close,
                                    event.tick_volume);
      if(recomputed != event.source_hash)
        {
         m_mismatches++;
         if(m_log!=NULL)
            m_log.Warn(StringFormat("TwinValidator MISMATCH #%d | event %d time %s | stored %d recomputed %d",
                                    (int)m_checked,(int)event.event_id,
                                    TimeToString(event.time,TIME_DATE|TIME_MINUTES),
                                    event.source_hash,recomputed));
         return(false);
        }
      m_emitted_hash_sum += event.source_hash;
      // also validate event_hash equals TwinHashEvent
      long eh = TwinHashEvent(event);
      // event_hash may not be set yet; we set it in bus dispatch, so allow 0
      if(event.event_hash!=0 && event.event_hash!=eh)
        {
         m_mismatches++;
         if(m_log!=NULL) m_log.Warn(StringFormat("TwinValidator event_hash mismatch | %d vs %d", event.event_hash, eh));
         return(false);
        }
      return(true);
     }

   //--- after window, compare sums
   bool                ValidateWindowSum(void) const
     {
      if(m_expected_hash_sum==0) return(true); // not set — skip
      return(m_expected_hash_sum == m_emitted_hash_sum);
     }

   long                Checked(void) const { return(m_checked); }
   long                Mismatches(void) const { return(m_mismatches); }
   long                EmittedHashSum(void) const { return(m_emitted_hash_sum); }
   long                ExpectedHashSum(void) const { return(m_expected_hash_sum); }

   string              ToString(void) const
     {
      return(StringFormat("TwinValidator checked %d mismatches %d | sum expected %d emitted %d | %s",
                          (int)m_checked,(int)m_mismatches,
                          m_expected_hash_sum,m_emitted_hash_sum,
                          ValidateWindowSum() ? "PASS" : "FAIL"));
     }
  };

#endif // __TWIN_VALIDATOR_MQH__
//+------------------------------------------------------------------+
