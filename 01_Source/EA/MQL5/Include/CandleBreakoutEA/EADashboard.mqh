//+------------------------------------------------------------------+
//|                                                   EADashboard.mqh|
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        On-chart HUD: strategy + exit engine      |
//+------------------------------------------------------------------+
#ifndef __EA_DASHBOARD_MQH__
#define __EA_DASHBOARD_MQH__

#include <CandleBreakoutEA\EASettings.mqh>
#include <CandleBreakoutEA\EATradeContext.mqh>
#include <CandleBreakoutEA\EAExitStats.mqh>

//--- panel geometry
const int    DASH_LINE_HEIGHT   = 14;    // pixels between lines
const int    DASH_TOP_MARGIN    = 30;    // pixels from the top edge
const int    DASH_RIGHT_MARGIN  = 10;    // pixels from the right edge
const int    DASH_FONT_SIZE     = 8;
const double DASH_STRONG_SCORE  = 50.0;  // green threshold for momentum
#define DASH_LINES 13                    // panel line count (array dimension)

//+------------------------------------------------------------------+
//| Small right-top HUD. Object names share the visual manager's     |
//| "CBEA_<magic>_" prefix, so CVisualManager::Cleanup removes them  |
//| automatically on deinit. The panel only READS the TradeContext.  |
//+------------------------------------------------------------------+
class CDashboard
  {
private:
   const CEASettings  *m_set;
   string              m_prefix;
   string              m_last_text;
   int                 m_rows;

   void                SetLine(const int idx,const string text,const color clr)
     {
      const string name = m_prefix+IntegerToString(idx);
      if(ObjectFind(0,name)<0)
        {
         ObjectCreate(0,name,OBJ_LABEL,0,0,0);
         ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
         ObjectSetString (0,name,OBJPROP_FONT,"Courier New");
         ObjectSetInteger(0,name,OBJPROP_FONTSIZE,DASH_FONT_SIZE);
         ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
         ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
         ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
        }
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,DASH_RIGHT_MARGIN);
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,DASH_TOP_MARGIN+idx*DASH_LINE_HEIGHT);
      ObjectSetString (0,name,OBJPROP_TEXT,text);
      ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
     }

public:
                       CDashboard(void) : m_set(NULL), m_rows(0) {}

   void                Init(const CEASettings &settings)
     {
      m_set    = &settings;
      m_prefix = StringFormat("CBEA_%I64u_DASH_",m_set.magic);
     }

   //--- the whole panel from one text blob; redraws only on change
   void                Render(const string &lines[],const color &colors[],const int count)
     {
      if(!m_set.dashboard_enabled)
         return;
      string key = "";
      for(int i=0; i<count; i++)
         key += lines[i]+"|";
      if(key==m_last_text)
         return;
      m_last_text = key;

      for(int i=0; i<count; i++)
         SetLine(i,lines[i],colors[i]);
      while(m_rows>count)
        {
         m_rows--;
         ObjectDelete(0,m_prefix+IntegerToString(m_rows));
        }
      m_rows = count;
      ChartRedraw(0);
     }

   //--- one consistent picture built from the shared TradeContext
   void                Update(const STradeContext &ctx,const CExitStats &stats,
                              const string strategy_state)
     {
      if(!m_set.dashboard_enabled)
         return;

      const int digits = (int)SymbolInfoInteger(m_set.symbol_name,SYMBOL_DIGITS);

      string lines[DASH_LINES];
      color  colors[DASH_LINES];
      lines[0]  = "== STRATEGY ============";
      colors[0] = clrDodgerBlue;
      lines[1]  = StringFormat("State       : %s",strategy_state);
      colors[1] = clrWhite;
      lines[2]  = "== EXIT ENGINE =========";
      colors[2] = clrDodgerBlue;
      lines[3]  = StringFormat("BreakEven   : %s",
                               (!ctx.break_even_enabled ? "off"
                                : (ctx.break_even_active ? "active" : "waiting swing")));
      colors[3] = (ctx.break_even_active ? clrGold : clrSilver);
      lines[4]  = StringFormat("Profit Lock : %s",
                               (ctx.profit_lock_active
                                ? StringFormat("armed @ %.0f pts",ctx.profit_lock_level)
                                : "-"));
      colors[4] = (ctx.profit_lock_active ? clrGold : clrSilver);
      lines[5]  = StringFormat("Carry       : %s",(ctx.carry_active ? "used" : "none"));
      colors[5] = (ctx.carry_active ? clrMagenta : clrSilver);
      lines[6]  = StringFormat("Momentum    : %.0f / 100",ctx.momentum_score);
      colors[6] = (ctx.momentum_score>=DASH_STRONG_SCORE ? clrLime : clrOrangeRed);
      lines[7]  = StringFormat("Floating    : %.0f pts",ctx.current_points);
      colors[7] = (ctx.current_points>=0.0 ? clrLime : clrOrangeRed);
      lines[8]  = StringFormat("Planned Exit: %s",ExitReasonToString(ctx.exit_reason));
      colors[8] = clrWhite;
      lines[9]  = "== TRADE CONTEXT ======";
      colors[9] = clrDodgerBlue;
      lines[10] = (ctx.ticket!=0
                   ? StringFormat("#%I64u %s %.2f @ %.*f | MFE %.0f | MAE %.0f",
                                  ctx.ticket,(ctx.direction==POSITION_TYPE_BUY ? "BUY" : "SELL"),
                                  ctx.lots,digits,ctx.entry_price,
                                  ctx.max_floating_profit,ctx.max_floating_loss)
                   : "no open position");
      colors[10]= clrSilver;
      lines[11] = "== EXIT STATISTICS =====";
      colors[11]= clrDodgerBlue;
      lines[12] = stats.SummaryLine();
      colors[12]= clrSilver;
      Render(lines,colors,DASH_LINES);
     }

   //--- remove the panel immediately
   void                Hide(void)
     {
      for(int i=0; i<m_rows; i++)
         ObjectDelete(0,m_prefix+IntegerToString(i));
      m_rows      = 0;
      m_last_text = "";
      ChartRedraw(0);
     }
  };

#endif // __EA_DASHBOARD_MQH__
//+------------------------------------------------------------------+
