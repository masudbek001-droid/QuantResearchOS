//+------------------------------------------------------------------+
//|                                                  EAVisualManager.mqh|
//|                        Candle Breakout Expert Advisor for MT5    |
//|                        Chart objects                             |
//+------------------------------------------------------------------+
#ifndef __EA_VISUAL_MANAGER_MQH__
#define __EA_VISUAL_MANAGER_MQH__

#include <CandleBreakoutEA\EAUtils.mqh>
#include <CandleBreakoutEA\EALogger.mqh>

//+------------------------------------------------------------------+
//| Draws the breakout levels, the entries, the exits and the current|
//| break even line. Every object is prefixed and removed on exit.   |
//+------------------------------------------------------------------+
class CVisualManager
  {
private:
   const CEASettings  *m_set;
   CLogger            *m_log;
   string              m_prefix;
   int                 m_counter;

   string              MakeName(const string base_name)
     {
      m_counter++;
      return(StringFormat("%s%s_%d",m_prefix,base_name,m_counter));
     }

   void                DrawLine(const string name,const double price,const color line_color,
                                const int width,const ENUM_LINE_STYLE style)
     {
      ObjectCreate(0,name,OBJ_HLINE,0,0,price);
      ObjectSetDouble(0,name,OBJPROP_PRICE,price);
      ObjectSetInteger(0,name,OBJPROP_COLOR,line_color);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
      ObjectSetInteger(0,name,OBJPROP_STYLE,style);
      ObjectSetInteger(0,name,OBJPROP_BACK,true);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
     }

public:
                       CVisualManager(void) : m_set(NULL), m_log(NULL), m_counter(0) {}

   void                Init(const CEASettings &settings,CLogger &logger)
     {
      m_set    = &settings;
      m_log    = &logger;
      m_prefix = StringFormat("CBEA_%I64u_",m_set.magic);
      m_counter= 0;
     }

   //--- wipe every object owned by this EA
   void                Cleanup(void)
     {
      if(!m_set.visual_enabled)
         return;
      const int total = ObjectsTotal(0,-1,-1);
      for(int i=total-1; i>=0; i--)
        {
         const string name = ObjectName(0,i,-1,-1);
         if(StringFind(name,m_prefix)==0)
            ObjectDelete(0,name);
        }
      ChartRedraw(0);
     }

   //--- previous candle high / low, the breakout trigger levels
   void                DrawBreakoutLevels(const double prev_high,const double prev_low)
     {
      if(!m_set.visual_enabled)
         return;
      DrawLine(m_prefix+"PrevHigh",prev_high,clrDodgerBlue,1,STYLE_DASH);
      DrawLine(m_prefix+"PrevLow", prev_low, clrOrangeRed, 1,STYLE_DASH);
      ObjectSetString(0,m_prefix+"PrevHigh",OBJPROP_TEXT,"Prev High");
      ObjectSetString(0,m_prefix+"PrevLow", OBJPROP_TEXT,"Prev Low");
      ChartRedraw(0);
      m_log.Debug(StringFormat("Visual | breakout levels drawn at %s / %s",
                               CEAUtils::DoubleToStr(prev_high,(int)SymbolInfoInteger(m_set.symbol_name,SYMBOL_DIGITS)),
                               CEAUtils::DoubleToStr(prev_low,(int)SymbolInfoInteger(m_set.symbol_name,SYMBOL_DIGITS))));
     }

   //--- the two pending orders, drawn as short vertical markers
   void                DrawPendingLevels(const double buy_price,const double sell_price,const datetime expiration)
     {
      if(!m_set.visual_enabled)
         return;
      if(buy_price>0.0)
        {
         const string name = MakeName("BuyStop");
         ObjectCreate(0,name,OBJ_TREND,0,TimeCurrent(),buy_price,expiration,buy_price);
         ObjectSetInteger(0,name,OBJPROP_COLOR,clrLime);
         ObjectSetInteger(0,name,OBJPROP_WIDTH,2);
         ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
         ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
         ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
        }
      if(sell_price>0.0)
        {
         const string name = MakeName("SellStop");
         ObjectCreate(0,name,OBJ_TREND,0,TimeCurrent(),sell_price,expiration,sell_price);
         ObjectSetInteger(0,name,OBJPROP_COLOR,clrRed);
         ObjectSetInteger(0,name,OBJPROP_WIDTH,2);
         ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
         ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
         ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
        }
      ChartRedraw(0);
     }

   //--- entry marker
   void                DrawEntry(const bool is_buy,const double price,const datetime moment)
     {
      if(!m_set.visual_enabled)
         return;
      const string name = MakeName(is_buy ? "EntryBuy" : "EntrySell");
      ObjectCreate(0,name,OBJ_ARROW,0,moment,price);
      ObjectSetInteger(0,name,OBJPROP_ARROWCODE,is_buy ? 233 : 234);
      ObjectSetInteger(0,name,OBJPROP_COLOR,is_buy ? clrLime : clrRed);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,2);
      ObjectSetInteger(0,name,OBJPROP_ANCHOR,is_buy ? ANCHOR_TOP : ANCHOR_BOTTOM);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetString(0,name,OBJPROP_TEXT,is_buy ? "Entry BUY" : "Entry SELL");
      ChartRedraw(0);
      m_log.Debug(StringFormat("Visual | entry marker at %s",CEAUtils::DoubleToStr(price,(int)SymbolInfoInteger(m_set.symbol_name,SYMBOL_DIGITS))));
     }

   //--- exit marker
   void                DrawExit(const bool is_buy,const double price,const datetime moment)
     {
      if(!m_set.visual_enabled)
         return;
      const string name = MakeName("Exit");
      ObjectCreate(0,name,OBJ_ARROW,0,moment,price);
      ObjectSetInteger(0,name,OBJPROP_ARROWCODE,251);
      ObjectSetInteger(0,name,OBJPROP_COLOR,clrYellow);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,2);
      ObjectSetInteger(0,name,OBJPROP_ANCHOR,is_buy ? ANCHOR_BOTTOM : ANCHOR_TOP);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetString(0,name,OBJPROP_TEXT,"Exit");
      ChartRedraw(0);
      m_log.Debug(StringFormat("Visual | exit marker at %s",CEAUtils::DoubleToStr(price,(int)SymbolInfoInteger(m_set.symbol_name,SYMBOL_DIGITS))));
     }

   //--- current break even / trailing stop level
   void                DrawStopLevel(const double price)
     {
      if(!m_set.visual_enabled)
         return;
      const string name = m_prefix+"BreakEven";
      if(price<=0.0)
        {
         ObjectDelete(0,name);
         ChartRedraw(0);
         return;
        }
      if(ObjectFind(0,name)<0)
         DrawLine(name,price,clrGold,1,STYLE_DOT);
      ObjectSetDouble(0,name,OBJPROP_PRICE,price);
      ObjectSetString(0,name,OBJPROP_TEXT,StringFormat("BE %s",CEAUtils::DoubleToStr(price,(int)SymbolInfoInteger(m_set.symbol_name,SYMBOL_DIGITS))));
      ChartRedraw(0);
     }
  };

#endif // __EA_VISUAL_MANAGER_MQH__
//+------------------------------------------------------------------+
