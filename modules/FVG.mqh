//+------------------------------------------------------------------+
//|  FVG.mqh  -  Fair Value Gap Module                               |
//+------------------------------------------------------------------+
#ifndef FVG_MQH
#define FVG_MQH

#define FVG_OBJ_PREFIX "FVG_"

struct FVGSettings
{
   int    history_candles;
   color  bullish_colour;
   color  bearish_colour;
   color  mitigated_colour;
};

//+------------------------------------------------------------------+
class CFVGModule
{
private:
   FVGSettings  m_settings;
   string       m_symbol;

public:
   CFVGModule(FVGSettings &s)
   {
      m_settings = s;
      m_symbol   = Symbol();
   }

   bool Init()   { Scan(); return true; }
   void Deinit() { ObjectsDeleteAll(0, FVG_OBJ_PREFIX); }

   void Update()
   {
      static datetime last_bar = 0;
      datetime t[];
      ArraySetAsSeries(t, true);
      if(CopyTime(m_symbol, PERIOD_CURRENT, 0, 1, t) == 1 && t[0] != last_bar)
      {
         last_bar = t[0];
         ObjectsDeleteAll(0, FVG_OBJ_PREFIX);
         Scan();
      }
   }

private:
   void Scan()
   {
      int bars = m_settings.history_candles + 5;

      double   hi[], lo[], cl[];
      datetime tm[];
      ArraySetAsSeries(hi, true);
      ArraySetAsSeries(lo, true);
      ArraySetAsSeries(cl, true);
      ArraySetAsSeries(tm, true);

      if(CopyHigh (m_symbol, PERIOD_CURRENT, 0, bars, hi) < bars) return;
      if(CopyLow  (m_symbol, PERIOD_CURRENT, 0, bars, lo) < bars) return;
      if(CopyClose(m_symbol, PERIOD_CURRENT, 0, bars, cl) < bars) return;
      if(CopyTime (m_symbol, PERIOD_CURRENT, 0, bars, tm) < bars) return;

      int drawn = 0;

      for(int c3 = 1; c3 <= m_settings.history_candles - 2; c3++)
      {
         int c2 = c3 + 1;
         int c1 = c3 + 2;
         if(c1 >= bars) break;

         //--- Bullish FVG: gap between hi[c1] (bottom) and lo[c3] (top)
         if(hi[c1] < lo[c3])
         {
            double bot = hi[c1];
            double top = lo[c3];

            bool mitigated = false;
            for(int k = c3 - 1; k >= 0; k--)
               if(cl[k] < top) { mitigated = true; break; }

            color c = mitigated ? m_settings.mitigated_colour : m_settings.bullish_colour;
            DrawRect("B_" + IntegerToString(drawn++), tm[c1], top, bot, c);
         }

         //--- Bearish FVG: gap between hi[c3] (bottom) and lo[c1] (top)
         if(lo[c1] > hi[c3])
         {
            double bot = hi[c3];
            double top = lo[c1];

            bool mitigated = false;
            for(int k = c3 - 1; k >= 0; k--)
               if(cl[k] > bot) { mitigated = true; break; }

            color c = mitigated ? m_settings.mitigated_colour : m_settings.bearish_colour;
            DrawRect("R_" + IntegerToString(drawn++), tm[c1], top, bot, c);
         }
      }

      ChartRedraw(0);
   }

   void DrawRect(string id, datetime t_start, double top, double bot, color c)
   {
      string   name  = FVG_OBJ_PREFIX + id;
      datetime right = t_start + (datetime)(PeriodSeconds(PERIOD_CURRENT) * 4);

      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t_start, top, right, bot);
      ObjectSetInteger(0, name, OBJPROP_COLOR,      c);
      ObjectSetInteger(0, name, OBJPROP_FILL,       true);
      ObjectSetInteger(0, name, OBJPROP_BACK,       false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   }
};

#endif
