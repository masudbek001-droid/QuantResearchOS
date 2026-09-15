//+------------------------------------------------------------------+
//|                            EAFeatureBuilder/EAFeatureBuilder.mqh |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Centralized market feature calculation    |
//+------------------------------------------------------------------+
#ifndef __EA_FB_BUILDER_MQH__
#define __EA_FB_BUILDER_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EAUtils.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAFeatureBuilder\FeatureTypes.mqh>
#include <CandleBreakoutEA\EAFeatureBuilder\FeatureSnapshot.mqh>
#include <CandleBreakoutEA\EAFeatureBuilder\FeatureValidation.mqh>

//+------------------------------------------------------------------+
//| The ONLY module allowed to derive market statistics (ADR-0002).  |
//| Observation-only: never places, modifies or closes anything.     |
//| Cached per completed main-TF bar; Update() inside a bar is free. |
//| The published snapshot is immutable: consumers get copies.       |
//+------------------------------------------------------------------+
class CFeatureBuilder
  {
private:
   const CEASettings  *m_set;
   CLogger            *m_log;
   SFeatureSnapshot    m_snapshot;      // last VALID snapshot
   ENUM_FB_STATUS      m_status;        // result of the last pass
   datetime            m_cache_bar;

   double              BarOpen(const int i)  const { return(iOpen (m_set.symbol_name,m_set.main_timeframe,i)); }
   double              BarHigh(const int i)  const { return(iHigh (m_set.symbol_name,m_set.main_timeframe,i)); }
   double              BarLow(const int i)   const { return(iLow  (m_set.symbol_name,m_set.main_timeframe,i)); }
   double              BarClose(const int i) const { return(iClose(m_set.symbol_name,m_set.main_timeframe,i)); }

   double              TrueRange(const int i) const
     {
      const double h = BarHigh(i), l = BarLow(i), pc = BarClose(i+1);
      return(MathMax(h-l,MathMax(MathAbs(h-pc),MathAbs(l-pc))));
     }

public:
                       CFeatureBuilder(void) : m_set(NULL), m_log(NULL),
                                               m_status(FB_ERR_MISSING_RATES), m_cache_bar(0) {}

   void                Initialize(const CEASettings &settings,CLogger &logger)
     {
      m_set = &settings;
      m_log = &logger;
      Reset();
      m_log.Info(StringFormat("Feature Builder initialized | %s %s | atr %d | trend %d",
                              m_set.symbol_name,EnumToString(m_set.main_timeframe),
                              FB_ATR_PERIOD,FB_TREND_PERIOD));
     }

   void                Reset(void)
     {
      m_snapshot.Reset();
      if(m_set!=NULL)
        {
         m_snapshot.Symbol    = m_set.symbol_name;
         m_snapshot.Timeframe = m_set.main_timeframe;
        }
      m_status    = FB_ERR_MISSING_RATES;
      m_cache_bar = 0;
     }

   //--- one series pass per completed bar; validation gates publication
   void                Update(void)
     {
      if(m_set==NULL)
         return;

      const datetime bar = iTime(m_set.symbol_name,m_set.main_timeframe,0);
      if(bar<=0 || bar==m_cache_bar)
         return;

      SFeatureSnapshot snap;
      snap.Symbol    = m_set.symbol_name;
      snap.Timeframe = m_set.main_timeframe;

      //--- clock features are always available
      MqlDateTime stamp;
      TimeToStruct(TimeCurrent(),stamp);
      snap.Timestamp   = TimeCurrent();
      snap.CurrentHour = stamp.hour;
      snap.Weekday     = stamp.day_of_week;
      snap.Month       = stamp.mon;
      snap.Quarter     = (stamp.mon-1)/3+1;
      snap.Session     = (stamp.hour<FB_ASIA_END_HOUR ? FB_SESSION_ASIA
                          : (stamp.hour<FB_LONDON_END_HOUR ? FB_SESSION_LONDON
                          : FB_SESSION_NEWYORK));
      snap.BrokerOffset= (int)MathRound((double)(TimeCurrent()-TimeGMT())/3600.0);
      snap.Spread      = CEAUtils::SpreadPoints(m_set.symbol_name);

      //--- series features need depth
      if(Bars(m_set.symbol_name,m_set.main_timeframe)<FB_MIN_BARS)
        {
         m_status = FB_ERR_MISSING_RATES;
         return;
        }
      m_cache_bar = bar;

      if(!CFeatureValidation::IsValidCandle(BarOpen(1),BarHigh(1),BarLow(1),BarClose(1)))
        {
         m_status = FB_ERR_INVALID_CANDLE;
         return;
        }

      double atr = 0.0;
      for(int i=1; i<=FB_ATR_PERIOD; i++)
         atr += TrueRange(i);
      snap.ATR = atr/FB_ATR_PERIOD;

      const double point = CEAUtils::PointValue(m_set.symbol_name);
      snap.Volatility       = (point>0.0 ? snap.ATR/point : 0.0);
      snap.PreviousRange    = BarHigh(2)-BarLow(2);
      snap.CurrentRange     = BarHigh(1)-BarLow(1);
      snap.BodySize         = MathAbs(BarClose(1)-BarOpen(1));
      snap.UpperShadow      = BarHigh(1)-MathMax(BarOpen(1),BarClose(1));
      snap.LowerShadow      = MathMin(BarOpen(1),BarClose(1))-BarLow(1);
      snap.ATRRatio         = (snap.ATR>0.0 ? snap.CurrentRange/snap.ATR : 0.0);
      snap.BodyPercent      = (snap.CurrentRange>0.0 ? 100.0*snap.BodySize/snap.CurrentRange : 0.0);
      snap.UpperShadowRatio = (snap.CurrentRange>0.0 ? snap.UpperShadow/snap.CurrentRange : 0.0);
      snap.LowerShadowRatio = (snap.CurrentRange>0.0 ? snap.LowerShadow/snap.CurrentRange : 0.0);
      snap.Bullish          = (BarClose(1)>BarOpen(1));
      snap.Bearish          = (BarClose(1)<BarOpen(1));

      int up = 0, down = 0;
      for(int i=1; i<=FB_TREND_PERIOD; i++)
        {
         if(BarClose(i)>BarOpen(i))
            up++;
         else
            if(BarClose(i)<BarOpen(i))
               down++;
        }
      snap.TrendDirection = (up>down ? FB_TREND_UP : (down>up ? FB_TREND_DOWN : FB_TREND_FLAT));
      snap.TrendStrength  = 100.0*(double)MathMax(up,down)/FB_TREND_PERIOD;

      //--- publish only a fully validated snapshot
      const ENUM_FB_STATUS status = CFeatureValidation::Validate(snap);
      if(status==FB_OK)
        {
         m_snapshot = snap;
         if(m_status!=FB_OK)
            m_log.Info(StringFormat("Feature Builder recovered | %s",FbStatusToString(status)));
        }
      else
         if(m_status==FB_OK)
            m_log.Warn(StringFormat("Feature Builder rejected snapshot | %s",FbStatusToString(status)));
      m_status = status;
     }

   //--- re-check the published snapshot on demand
   bool                Validate(void) const
     {
      return(CFeatureValidation::Validate(m_snapshot)==FB_OK);
     }

   //--- immutable access: callers receive a copy
   SFeatureSnapshot    GetSnapshot(void) const
     {
      return(m_snapshot);
     }

   ENUM_FB_STATUS      LastStatus(void) const { return(m_status); }
   bool                IsReady(void)    const { return(m_status==FB_OK); }

   string              ToString(void) const
     {
      return(StringFormat("features: %s | spread %.0f | ATR %.5f (x%.2f) | body %.0f%% | sh %.2f/%.2f | trend %d (%.0f) | %s h%02d",
                          FbStatusToString(m_status),m_snapshot.Spread,m_snapshot.ATR,
                          m_snapshot.ATRRatio,m_snapshot.BodyPercent,
                          m_snapshot.UpperShadowRatio,m_snapshot.LowerShadowRatio,
                          (int)m_snapshot.TrendDirection,m_snapshot.TrendStrength,
                          EnumToString(m_snapshot.Session),m_snapshot.CurrentHour));
     }
  };

#endif // __EA_FB_BUILDER_MQH__
//+------------------------------------------------------------------+
