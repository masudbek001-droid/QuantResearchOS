//+------------------------------------------------------------------+
//|                                 EAData/TradeWriter.mqh           |
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Trade Intelligence: trade metadata writer |
//+------------------------------------------------------------------+
#ifndef __EA_DAL_TRADE_WRITER_MQH__
#define __EA_DAL_TRADE_WRITER_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EALogger.mqh>
#include <CandleBreakoutEA\EAData\DatabaseTypes.mqh>
#include <CandleBreakoutEA\EAData\DatabaseManager.mqh>
#include <CandleBreakoutEA\EAData\MarketSnapshotWriter.mqh>

//+------------------------------------------------------------------+
//| Persists complete trade metadata into Trades (schema v3) for     |
//| future quantitative research - not for reporting. Every trade is |
//| linked to the market observations known at entry and exit.       |
//| No business logic: the writer only validates and stores.         |
//+------------------------------------------------------------------+
class CTradeWriter
  {
private:
   const CEASettings  *m_set;
   CLogger            *m_log;
   CDatabaseManager   *m_db;
   CMarketSnapshotWriter *m_snapshots;   // reference ids + snapshot linkage source

   //--- newest observation recorded strictly before the given moment
   long                LatestSnapshotBefore(const datetime moment)
     {
      if(m_snapshots==NULL)
         return(-1);
      const int sym = m_snapshots.SymbolId();
      const int tf  = m_snapshots.TimeframeId();
      if(sym<=0 || tf<=0)
         return(-1);
      string rows[];
      if(m_db.Select(StringFormat(
            "SELECT SnapshotID FROM %s WHERE SymbolID=%d AND TimeframeID=%d AND SnapshotTime<%d "
            "ORDER BY SnapshotTime DESC LIMIT 1",
            DB_TABLE_SNAPSHOTS,sym,tf,(int)moment),rows)==1)
         return(StringToInteger(rows[0]));
      return(-1);
     }

   bool                SnapshotExists(const long snapshot_id)
     {
      if(snapshot_id<=0)
         return(false);
      string rows[];
      return(m_db.Select(StringFormat("SELECT COUNT(*) FROM %s WHERE SnapshotID=%d",
                                      DB_TABLE_SNAPSHOTS,(int)snapshot_id),rows)==1 &&
             StringToInteger(rows[0])>0);
     }

public:
                       CTradeWriter(void) : m_set(NULL), m_log(NULL), m_db(NULL), m_snapshots(NULL) {}

   void                Initialize(const CEASettings &settings,CLogger &logger,
                                  CDatabaseManager &db,CMarketSnapshotWriter &snapshots)
     {
      m_set       = &settings;
      m_log       = &logger;
      m_db        = &db;
      m_snapshots = &snapshots;
      m_log.Info("Trade writer initialized");
     }

   //--- STEP 4 rule set for a trade row; shared by insert and update
   bool                ValidateTrade(const ulong ticket,const double lots,
                                     const datetime entry_time,const datetime exit_time,
                                     const long entry_snapshot_id)
     {
      if(ticket==0)
         return(false);
      if(lots<0.0)
        { m_log.Warn(StringFormat("Trade #%I64u rejected | negative lot",ticket)); return(false); }
      if(entry_time<=0)
        { m_log.Warn(StringFormat("Trade #%I64u rejected | invalid entry time",ticket)); return(false); }
      if(exit_time>0 && exit_time<entry_time)
        { m_log.Warn(StringFormat("Trade #%I64u rejected | invalid exit time",ticket)); return(false); }
      if(m_snapshots!=NULL && (m_snapshots.SymbolId()<=0 || m_snapshots.TimeframeId()<=0))
        { m_log.Warn(StringFormat("Trade #%I64u rejected | invalid symbol/timeframe",ticket)); return(false); }
      if(entry_snapshot_id>=0 && !SnapshotExists(entry_snapshot_id))
        { m_log.Warn(StringFormat("Trade #%I64u rejected | missing snapshot",ticket)); return(false); }
      return(true);
     }

   //--- STEP 3: register a newly opened position (exit fields stay NULL)
   bool                InsertTrade(const ulong ticket,const bool is_buy,const double lots,
                                   const datetime entry_time,const double entry_price,
                                   const datetime entry_bar)
     {
      if(m_db==NULL || !m_db.IsOpen())
         return(false);

      //--- STEP 4: duplicate ticket
      string rows[];
      if(m_db.Select(StringFormat("SELECT COUNT(*) FROM %s WHERE Ticket=%d",
                                  DB_TABLE_TRADES,(int)ticket),rows)==1 &&
         StringToInteger(rows[0])>0)
        {
         m_log.Debug(StringFormat("Trade #%I64u already stored",ticket));
         return(false);
        }

      //--- STEP 2: entry observation = newest snapshot before the entry bar
      const long entry_snap = LatestSnapshotBefore(entry_bar>0 ? entry_bar : entry_time+1);
      if(!ValidateTrade(ticket,lots,entry_time,0,entry_snap))
         return(false);

      const int sym = m_snapshots.SymbolId();
      const int tf  = m_snapshots.TimeframeId();
      const string stamp = TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES);
      const string sql = StringFormat(
         "INSERT INTO %s (Ticket,SymbolID,TimeframeID,Magic,Direction,Lots,"
         "EntryTime,EntryPrice,EntrySnapshotID,CreatedAt) VALUES (%d,%d,%d,%d,%s,%d,%s,%d,'%s')",
         DB_TABLE_TRADES,(int)ticket,sym,tf,(int)m_set.magic,(int)(is_buy ? 0 : 1),
         DoubleToString(lots,2),(int)entry_time,DoubleToString(entry_price,8),
         (int)entry_snap,stamp);

      if(m_db.Insert(sql)!=1)
        {
         m_log.Warn(StringFormat("Trade #%I64u insert failed",ticket));
         return(false);
        }
      m_log.Info(StringFormat("Trade stored | #%I64u | entry snapshot #%d",ticket,(int)entry_snap));
      return(true);
     }

   //--- STEP 3: fill the exit side of a stored trade
   bool                UpdateTradeExit(const ulong ticket,const datetime entry_time,
                                       const datetime entry_bar,const datetime exit_time,
                                       const double exit_price,const double profit,
                                       const double swap,const double commission,
                                       const int exit_reason,const bool be_used,
                                       const bool carry_used,const bool momentum_used,
                                       const bool pl_used)
     {
      if(m_db==NULL || !m_db.IsOpen() || ticket==0)
         return(false);

      string rows[];
      if(m_db.Select(StringFormat("SELECT COUNT(*) FROM %s WHERE Ticket=%d",
                                  DB_TABLE_TRADES,(int)ticket),rows)!=1 ||
         StringToInteger(rows[0])!=1)
        {
         m_log.Warn(StringFormat("Trade #%I64u exit rejected | row missing",ticket));
         return(false);
        }
      if(!ValidateTrade(ticket,0.0,entry_time,exit_time,-1))
         return(false);

      //--- STEP 2: exit observation = newest snapshot recorded by exit time
      const long exit_snap = LatestSnapshotBefore(exit_time+1);
      if(!SnapshotExists(exit_snap))
        {
         m_log.Warn(StringFormat("Trade #%I64u exit rejected | missing snapshot",ticket));
         return(false);
        }

      //--- durations: bars counted between entry and exit candle
      int duration_bars = 0;
      if(entry_bar>0)
        {
         const int eb = iBarShift(m_set.symbol_name,m_set.main_timeframe,entry_bar);
         const int xb = iBarShift(m_set.symbol_name,m_set.main_timeframe,exit_time);
         if(eb>=0 && xb>=0 && eb>=xb)
            duration_bars = eb-xb;
        }
      const long duration_sec = (exit_time>entry_time ? (long)(exit_time-entry_time) : 0);

      const string sql = StringFormat(
         "UPDATE %s SET ExitTime=%d,ExitPrice=%s,Profit=%s,Swap=%s,Commission=%s,"
         "NetProfit=%s,TradeDurationSeconds=%d,TradeDurationBars=%d,ExitReason=%d,"
         "BreakEvenUsed=%d,CarryUsed=%d,MomentumUsed=%d,ProfitLockUsed=%d,ExitSnapshotID=%d "
         "WHERE Ticket=%d",
         DB_TABLE_TRADES,(int)exit_time,DoubleToString(exit_price,8),
         DoubleToString(profit,2),DoubleToString(swap,2),DoubleToString(commission,2),
         DoubleToString(profit+swap+commission,2),
         (int)duration_sec,duration_bars,exit_reason,
         (int)(be_used ? 1 : 0),(int)(carry_used ? 1 : 0),
         (int)(momentum_used ? 1 : 0),(int)(pl_used ? 1 : 0),
         (int)exit_snap,(int)ticket);

      if(m_db.Update(sql)!=1)
        {
         m_log.Warn(StringFormat("Trade #%I64u exit update failed",ticket));
         return(false);
        }
      m_log.Info(StringFormat("Trade exit stored | #%I64u | %d bars | snapshot #%d",
                              ticket,duration_bars,(int)exit_snap));
      return(true);
     }
  };

#endif // __EA_DAL_TRADE_WRITER_MQH__
//+------------------------------------------------------------------+
