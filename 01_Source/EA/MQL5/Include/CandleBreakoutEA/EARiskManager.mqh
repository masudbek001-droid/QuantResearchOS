//+------------------------------------------------------------------+
//|                                                 EARiskManager.mqh|
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Daily limits + trading hours filter       |
//+------------------------------------------------------------------+
#ifndef __EA_RISK_MANAGER_MQH__
#define __EA_RISK_MANAGER_MQH__

#include <CandleBreakoutEA\EAUtils.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EATradeHistory.mqh>

//+------------------------------------------------------------------+
//| Decides whether a brand new candle cycle may start.              |
//+------------------------------------------------------------------+
class CRiskManager
  {
private:
   const CEASettings  *m_set;
   CLogger            *m_log;
   CTradeHistory      *m_history;
   double              m_last_logged_pnl;

   //--- server hour of a moment, in [0..23]
   int                 HourOf(const datetime moment) const
     {
      MqlDateTime stamp;
      TimeToStruct(moment,stamp);
      return(stamp.hour);
     }

   bool                IsHourEnabled(const int hour) const
     {
      if(!m_set.use_hours_filter)
         return(true);
      if(hour<0 || hour>23)
         return(false);
      return(((m_set.hours_mask & (1L<<hour))!=0));
     }

public:
                       CRiskManager(void) : m_set(NULL), m_log(NULL), m_history(NULL), m_last_logged_pnl(0.0) {}

   void                Init(const CEASettings &settings,CLogger &logger,CTradeHistory &history)
     {
      m_set     = &settings;
      m_log     = &logger;
      m_history = &history;
     }

   bool                IsHourTradable(void) const
     {
      return(IsHourEnabled(HourOf(TimeCurrent())));
     }

   double              DailyProfit(void) const
     {
      return(m_history.DailyProfit());
     }

   //--- main gate: BLOCK_NONE means the breakout may be armed
   ENUM_TRADE_BLOCK    Check(string &reason)
     {
      reason = "";
      if(m_set==NULL)
        {
         reason = "risk manager not initialized";
         return(BLOCK_HOURS);
        }

      if(!IsHourTradable())
        {
         reason = StringFormat("Trading Hours Filter | %02d:00 is disabled",HourOf(TimeCurrent()));
         m_log.Warn(reason);
         return(BLOCK_HOURS);
        }

      if(!m_set.use_daily_limits)
         return(BLOCK_NONE);

      const double pnl = DailyProfit();
      if(m_set.daily_profit_limit>0.0 && pnl>=m_set.daily_profit_limit)
        {
         reason = StringFormat("Daily Limit Reached | profit %.2f >= %.2f",pnl,m_set.daily_profit_limit);
         m_log.Warn(reason);
         return(BLOCK_DAILY_PNL);
        }
      if(m_set.daily_loss_limit>0.0 && pnl<=-MathAbs(m_set.daily_loss_limit))
        {
         reason = StringFormat("Daily Limit Reached | loss %.2f <= -%.2f",pnl,MathAbs(m_set.daily_loss_limit));
         m_log.Warn(reason);
         return(BLOCK_DAILY_PNL);
        }
      return(BLOCK_NONE);
     }

   //--- called once per candle so the log shows the running result
   void                ReportDailyState(void)
     {
      const double pnl = DailyProfit();
      if(MathAbs(pnl-m_last_logged_pnl)<0.01)
         return;
      m_last_logged_pnl = pnl;
      m_log.Info(StringFormat("Daily P/L = %.2f (profit limit %.2f / loss limit %.2f)",
                              pnl,m_set.daily_profit_limit,m_set.daily_loss_limit));
     }
  };

#endif // __EA_RISK_MANAGER_MQH__
//+------------------------------------------------------------------+
