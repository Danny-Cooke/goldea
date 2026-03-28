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
   int    count;        // display last N by fill time
   bool   invalidate;   // remove IFVG if price breaks back through
};

struct IFVGZone
{
   datetime time_start;
   double   top;
   double   bottom;
   bool     is_bullish;   // true = originally bullish FVG (now bearish zone)
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
      int bull_found=0, bull_filled=0, bull_broken=0;
      int bear_found=0, bear_filled=0, bear_broken=0;

      for(int c3 = 1; c3 <= m_settings.history_candles - 2; c3++)
      {
         int c2 = c3 + 1;
         int c1 = c3 + 2;
         if(c1 >= bars) break;

         //----------------------------------------------------------
         // BULLISH FVG → IFVG (becomes bearish zone after full fill)
         // Condition : hi[c1] < lo[c3]
         // Gap       : bottom = hi[c1], top = lo[c3]
         // Full fill : lo[k] < bottom  (price drove below gap bottom)
         // Broken    : after fill, close[k] > top (candle closes above zone top)
         //----------------------------------------------------------
         if(hi[c1] < lo[c3])
         {
            bull_found++;
            double bot = hi[c1];
            double top = lo[c3];

            int fill_idx = -1;
            for(int k = c3 - 1; k >= 0; k--)
               if(lo[k] < bot) { fill_idx = k; break; }

            if(fill_idx >= 0)
            {
               bull_filled++;
               bool broken = false;
               if(m_settings.invalidate)
                  for(int k = fill_idx - 1; k >= 0; k--)
                     if(cl[k] > top) { broken = true; break; }

               if(!broken)
                  AddZone(ifvgs, tm[c1], top, bot, true, tm[fill_idx]);
               else
                  bull_broken++;
            }
         }

         //----------------------------------------------------------
         // BEARISH FVG → IFVG (becomes bullish zone after full fill)
         // Condition : lo[c1] > hi[c3]
         // Gap       : bottom = hi[c3], top = lo[c1]
         // Full fill : hi[k] > top  (price drove above gap top)
         // Broken    : after fill, close[k] < bottom (candle closes below zone bottom)
         //----------------------------------------------------------
         if(lo[c1] > hi[c3])
         {
            bear_found++;
            double bot = hi[c3];
            double top = lo[c1];

            int fill_idx = -1;
            for(int k = c3 - 1; k >= 0; k--)
               if(hi[k] > top) { fill_idx = k; break; }

            if(fill_idx >= 0)
            {
               bear_filled++;
               bool broken = false;
               if(m_settings.invalidate)
                  for(int k = fill_idx - 1; k >= 0; k--)
                     if(cl[k] < bot) { broken = true; break; }

               if(!broken)
                  AddZone(ifvgs, tm[c1], top, bot, false, tm[fill_idx]);
               else
                  bear_broken++;
            }
         }
      }

      // Sort newest fill first, draw last N
      SortDesc(ifvgs);
      int draw_n = MathMin(ArraySize(ifvgs), m_settings.count);
      for(int i = 0; i < draw_n; i++)
      {
         DrawRect("Z_" + IntegerToString(i),
                  ifvgs[i].time_start, ifvgs[i].top, ifvgs[i].bottom);
      }

      // Debug output
      PrintFormat("IFVG Scan | BULL FVGs: found=%d filled=%d broken=%d | BEAR FVGs: found=%d filled=%d broken=%d | IFVGs total=%d showing=%d",
                  bull_found, bull_filled, bull_broken,
                  bear_found, bear_filled, bear_broken,
                  ArraySize(ifvgs), draw_n);
      for(int i = 0; i < draw_n; i++)
         PrintFormat("  IFVG[%d] %s | top=%.5f bot=%.5f | filled=%s",
                     i,
                     ifvgs[i].is_bullish ? "BULL->BEAR" : "BEAR->BULL",
                     ifvgs[i].top, ifvgs[i].bottom,
                     TimeToString(ifvgs[i].fill_time));

      ChartRedraw(0);
   }

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
};

#endif
