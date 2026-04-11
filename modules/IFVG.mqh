//+------------------------------------------------------------------+
//|  IFVG.mqh  -  Inverted Fair Value Gap Module                     |
//+------------------------------------------------------------------+
#ifndef IFVG_MQH
#define IFVG_MQH

#define IFVG_OBJ_PREFIX "IFVG_"

struct IFVGSettings
{
   int    history_candles;
   color  colour;
   int    count;            // draw last N zones by fill time
   bool   invalidate;       // remove if price breaks back through
   double tp_multiplier;    // TP = risk * this value  (e.g. 1.5 or 3.0)
   int    sl_lookback;      // bars back to search for swing hi/lo for SL
   double sl_buffer_pts;    // extra buffer on SL in points (e.g. 50)
   color  long_colour;      // line colour for long setups
   color  short_colour;     // line colour for short setups
};

struct IFVGZone
{
   datetime time_start;
   double   top;
   double   bottom;
   bool     is_bullish;   // true = was bullish FVG  → short setup
                          // false = was bearish FVG → long  setup
   datetime fill_time;
};

//+------------------------------------------------------------------+
class CIFVGModule
{
private:
   IFVGSettings m_settings;
   string       m_symbol;

public:
   CIFVGModule(IFVGSettings &s)
   {
      m_settings = s;
      m_symbol   = Symbol();
   }

   bool Init()   { Scan(); return true; }
   void Deinit() { ObjectsDeleteAll(0, IFVG_OBJ_PREFIX); }

   void Update()
   {
      static datetime last_bar = 0;
      datetime t[];
      ArraySetAsSeries(t, true);
      if(CopyTime(m_symbol, PERIOD_CURRENT, 0, 1, t) == 1 && t[0] != last_bar)
      {
         last_bar = t[0];
         ObjectsDeleteAll(0, IFVG_OBJ_PREFIX);
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

      IFVGZone ifvgs[];

      for(int c3 = 1; c3 <= m_settings.history_candles - 2; c3++)
      {
         int c1 = c3 + 2;
         if(c1 >= bars) break;

         //----------------------------------------------------------
         // BULLISH FVG (hi[c1] < lo[c3])  →  SHORT setup after fill
         // Gap   : bottom = hi[c1], top = lo[c3]
         // Fill  : lo[k] < bottom  (wick passed through gap bottom)
         // Broken: close[k] > top  (closed above zone = invalidated)
         //----------------------------------------------------------
         if(hi[c1] < lo[c3])
         {
            double bot = hi[c1];
            double top = lo[c3];

            int fill_idx = -1;
            for(int k = c3 - 1; k >= 0; k--)
               if(lo[k] < bot) { fill_idx = k; break; }

            if(fill_idx >= 0)
            {
               bool broken = false;
               if(m_settings.invalidate)
                  for(int k = fill_idx - 1; k >= 0; k--)
                     if(cl[k] > top) { broken = true; break; }

               if(!broken)
                  AddZone(ifvgs, tm[c1], top, bot, true, tm[fill_idx]);
            }
         }

         //----------------------------------------------------------
         // BEARISH FVG (lo[c1] > hi[c3])  →  LONG setup after fill
         // Gap   : bottom = hi[c3], top = lo[c1]
         // Fill  : hi[k] > top  (wick passed through gap top)
         // Broken: close[k] < bottom (closed below zone = invalidated)
         //----------------------------------------------------------
         if(lo[c1] > hi[c3])
         {
            double bot = hi[c3];
            double top = lo[c1];

            int fill_idx = -1;
            for(int k = c3 - 1; k >= 0; k--)
               if(hi[k] > top) { fill_idx = k; break; }

            if(fill_idx >= 0)
            {
               bool broken = false;
               if(m_settings.invalidate)
                  for(int k = fill_idx - 1; k >= 0; k--)
                     if(cl[k] < bot) { broken = true; break; }

               if(!broken)
                  AddZone(ifvgs, tm[c1], top, bot, false, tm[fill_idx]);
            }
         }
      }

      // Sort newest fill first
      SortDesc(ifvgs);

      int total = ArraySize(ifvgs);
      int draw_n = MathMin(total, m_settings.count);

      // Draw the IFVG zone rectangles
      for(int i = 0; i < draw_n; i++)
         DrawRect("Z_" + IntegerToString(i),
                  ifvgs[i].time_start, ifvgs[i].top, ifvgs[i].bottom);

      // Draw trade setup lines for the most recent IFVG
      if(total > 0)
         DrawSetup(ifvgs[0], hi, lo, bars);

      PrintFormat("IFVG | found=%d  showing=%d  invalidate=%s  tp_mult=%.1f",
                  total, draw_n,
                  m_settings.invalidate ? "ON" : "OFF",
                  m_settings.tp_multiplier);
      if(total > 0)
         PrintFormat("IFVG | latest=%s  top=%.5f  bot=%.5f  fill=%s",
                     ifvgs[0].is_bullish ? "SHORT-setup" : "LONG-setup",
                     ifvgs[0].top, ifvgs[0].bottom,
                     TimeToString(ifvgs[0].fill_time));

      ChartRedraw(0);
   }

   //--- Build trade levels from the most-recently-mitigated IFVG ----
   void DrawSetup(IFVGZone &z, double &hi[], double &lo[], int bars)
   {
      double entry = (z.top + z.bottom) / 2.0;
      double buf   = m_settings.sl_buffer_pts * _Point;

      // Scan sl_lookback bars from current bar for the swing extreme
      int lb = MathMin(m_settings.sl_lookback, bars - 1);
      double swing_lo = lo[0];
      double swing_hi = hi[0];
      for(int k = 1; k <= lb; k++)
      {
         if(lo[k] < swing_lo) swing_lo = lo[k];
         if(hi[k] > swing_hi) swing_hi = hi[k];
      }

      double sl, tp, risk;
      string dir_tag;
      color  line_col;

      if(!z.is_bullish)   // bearish FVG mitigated → LONG
      {
         sl       = swing_lo - buf;
         risk     = entry - sl;
         tp       = entry + risk * m_settings.tp_multiplier;
         dir_tag  = "LONG";
         line_col = m_settings.long_colour;
      }
      else                // bullish FVG mitigated → SHORT
      {
         sl       = swing_hi + buf;
         risk     = sl - entry;
         tp       = entry - risk * m_settings.tp_multiplier;
         dir_tag  = "SHORT";
         line_col = m_settings.short_colour;
      }

      DrawHLine("ENTRY", entry, line_col,  STYLE_SOLID,
                dir_tag + "  Entry @ " + DoubleToString(entry, _Digits));
      DrawHLine("SL",    sl,    clrRed,    STYLE_DASHDOT,
                dir_tag + "  SL    @ " + DoubleToString(sl,    _Digits)
                + "  (risk=" + DoubleToString(risk / _Point, 0) + " pts)");
      DrawHLine("TP",    tp,    clrLime,   STYLE_DASH,
                dir_tag + "  TP    @ " + DoubleToString(tp,    _Digits)
                + "  (" + DoubleToString(m_settings.tp_multiplier, 1) + "R)");
   }

   //--- Helpers -------------------------------------------------------
   void AddZone(IFVGZone &arr[], datetime t_start, double top, double bot,
                bool bullish, datetime fill_time)
   {
      int sz = ArraySize(arr);
      ArrayResize(arr, sz + 1);
      arr[sz].time_start = t_start;
      arr[sz].top        = top;
      arr[sz].bottom     = bot;
      arr[sz].is_bullish = bullish;
      arr[sz].fill_time  = fill_time;
   }

   void SortDesc(IFVGZone &arr[])
   {
      int n = ArraySize(arr);
      for(int i = 0; i < n - 1; i++)
         for(int j = i + 1; j < n; j++)
            if(arr[j].fill_time > arr[i].fill_time)
            {
               IFVGZone tmp = arr[i]; arr[i] = arr[j]; arr[j] = tmp;
            }
   }

   void DrawRect(string id, datetime t_start, double top, double bot)
   {
      string   name  = IFVG_OBJ_PREFIX + id;
      datetime right = TimeCurrent() + (datetime)(PeriodSeconds(PERIOD_CURRENT) * 10);
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t_start, top, right, bot);
      ObjectSetInteger(0, name, OBJPROP_COLOR,      m_settings.colour);
      ObjectSetInteger(0, name, OBJPROP_FILL,       true);
      ObjectSetInteger(0, name, OBJPROP_BACK,       false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   }

   void DrawHLine(string id, double price, color c, ENUM_LINE_STYLE style, string label)
   {
      string name = IFVG_OBJ_PREFIX + "HL_" + id;
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR,      c);
      ObjectSetInteger(0, name, OBJPROP_WIDTH,      2);
      ObjectSetInteger(0, name, OBJPROP_STYLE,      style);
      ObjectSetString (0, name, OBJPROP_TOOLTIP,    label);
      ObjectSetString (0, name, OBJPROP_TEXT,       label);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   }
};

#endif
