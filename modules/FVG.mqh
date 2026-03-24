//+------------------------------------------------------------------+
//|  FVG.mqh  -  Fair Value Gap Module                               |
//+------------------------------------------------------------------+
#ifndef FVG_MQH
#define FVG_MQH

#define FVG_OBJ_PREFIX  "FVG_"
#define FVG_MAX_ZONES   1000

//--- FVG type
enum ENUM_FVG_TYPE
{
   FVG_BULLISH,
   FVG_BEARISH
};

//--- Settings passed in from the EA inputs
struct FVGSettings
{
   int    history_candles;       // FVG - History - Candles Back
   color  bullish_colour;        // FVG - Display - Bullish Colour
   color  bearish_colour;        // FVG - Display - Bearish Colour
   int    opacity;               // FVG - Display - Rectangle Opacity (0=opaque, 100=transparent)
   double min_size_pips;         // FVG - Filter  - Minimum Size (pips)
   int    range_lookback;        // FVG - Range   - Lookback Candles
   int    range_atr_period;      // FVG - Range   - ATR Period
   double range_atr_mult;        // FVG - Range   - ATR Multiplier
   double breakout_atr_mult;     // FVG - Breakout- ATR Multiplier
};

//--- A single active FVG zone
struct FVGZone
{
   datetime        time_start;       // left edge  (candle 1 open time)
   double          top;              // original top of gap
   double          bottom;           // original bottom of gap
   double          current_top;      // shrinks as price fills from top
   double          current_bottom;   // shrinks as price fills from bottom
   ENUM_FVG_TYPE   fvg_type;
   ENUM_TIMEFRAMES timeframe;
   int             tf_index;         // index into m_timeframes[]
   string          obj_name;
   bool            active;
   bool            drawn;
};

//+------------------------------------------------------------------+
class CFVGModule
{
private:
   FVGSettings     m_settings;
   FVGZone         m_zones[];
   int             m_zone_count;

   ENUM_TIMEFRAMES m_timeframes[7];
   string          m_tf_names[7];
   datetime        m_last_bar_time[7];
   int             m_atr_handles[7];
   double          m_tf_high[7];     // cached current-bar high per TF
   double          m_tf_low[7];      // cached current-bar low  per TF

   ENUM_TIMEFRAMES m_last_chart_tf;
   string          m_symbol;
   double          m_point;
   double          m_pip_size;       // 1 pip in price units
   int             m_obj_counter;

public:
   //-------------------------------------------------------------------
   CFVGModule(FVGSettings &settings)
   {
      m_settings    = settings;
      m_zone_count  = 0;
      m_obj_counter = 0;
      ArrayResize(m_zones, FVG_MAX_ZONES);

      m_timeframes[0] = PERIOD_M1;  m_tf_names[0] = "M1";
      m_timeframes[1] = PERIOD_M5;  m_tf_names[1] = "M5";
      m_timeframes[2] = PERIOD_M15; m_tf_names[2] = "M15";
      m_timeframes[3] = PERIOD_M30; m_tf_names[3] = "M30";
      m_timeframes[4] = PERIOD_H1;  m_tf_names[4] = "H1";
      m_timeframes[5] = PERIOD_H4;  m_tf_names[5] = "H4";
      m_timeframes[6] = PERIOD_D1;  m_tf_names[6] = "D1";

      m_symbol        = Symbol();
      m_point         = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      m_last_chart_tf = (ENUM_TIMEFRAMES)Period();

      // 1 pip: 10 points for 3/5-digit symbols (forex), 1 point otherwise (metals)
      int digits  = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      m_pip_size  = (digits == 3 || digits == 5) ? m_point * 10.0 : m_point;

      ArrayInitialize(m_last_bar_time, 0);
      ArrayInitialize(m_atr_handles,  INVALID_HANDLE);
      ArrayInitialize(m_tf_high,      0.0);
      ArrayInitialize(m_tf_low,       0.0);
   }

   //-------------------------------------------------------------------
   bool Init()
   {
      for(int i = 0; i < 7; i++)
      {
         m_atr_handles[i] = iATR(m_symbol, m_timeframes[i], m_settings.range_atr_period);
         if(m_atr_handles[i] == INVALID_HANDLE)
         {
            PrintFormat("FVG: Failed to create ATR handle for %s", m_tf_names[i]);
            return false;
         }
      }

      // Full historical scan on all timeframes
      for(int i = 0; i < 7; i++)
         FullScan(i);

      return true;
   }

   //-------------------------------------------------------------------
   void Update()
   {
      // If user switched chart timeframe, rebuild drawings
      ENUM_TIMEFRAMES chart_tf = (ENUM_TIMEFRAMES)Period();
      if(chart_tf != m_last_chart_tf)
      {
         ObjectsDeleteAll(0, FVG_OBJ_PREFIX);
         for(int i = 0; i < m_zone_count; i++)
            m_zones[i].drawn = false;
         m_last_chart_tf = chart_tf;
      }

      // Check each timeframe for a new bar → scan for new FVG
      for(int i = 0; i < 7; i++)
      {
         datetime t[];
         ArraySetAsSeries(t, true);
         if(CopyTime(m_symbol, m_timeframes[i], 0, 1, t) == 1)
         {
            if(m_last_bar_time[i] == 0)
               m_last_bar_time[i] = t[0];
            else if(t[0] != m_last_bar_time[i])
            {
               m_last_bar_time[i] = t[0];
               CheckNewBar(i);
            }
         }
      }

      // Cache current-bar high/low for every timeframe (used in fill tracking)
      CachePrices();

      // Fill tracking + removal
      UpdateFillTracking();

      // Draw / update rectangles for the current chart timeframe
      UpdateDrawings();
   }

   //-------------------------------------------------------------------
   void Deinit()
   {
      for(int i = 0; i < 7; i++)
         if(m_atr_handles[i] != INVALID_HANDLE)
         {
            IndicatorRelease(m_atr_handles[i]);
            m_atr_handles[i] = INVALID_HANDLE;
         }
      ObjectsDeleteAll(0, FVG_OBJ_PREFIX);
   }

//===================================================================
private:
   //-------------------------------------------------------------------
   // Full scan of a timeframe over the configured history window
   //-------------------------------------------------------------------
   void FullScan(int tf_idx)
   {
      ENUM_TIMEFRAMES tf = m_timeframes[tf_idx];
      int need = m_settings.history_candles + m_settings.range_lookback
                 + m_settings.range_atr_period + 10;

      double hi[], lo[], op[], cl[];
      datetime tm[];
      double   atr[];

      if(!LoadBars(tf, need, hi, lo, op, cl, tm)) return;
      if(!LoadATR(tf_idx, need, atr))             return;

      // Store current bar time
      datetime t[];
      ArraySetAsSeries(t, true);
      if(CopyTime(m_symbol, tf, 0, 1, t) == 1)
         m_last_bar_time[tf_idx] = t[0];

      // Scan: c3 is the newest candle of the 3-candle pattern (skip index 0 = forming)
      for(int c3 = 1; c3 <= m_settings.history_candles; c3++)
      {
         int c2 = c3 + 1;
         int c1 = c3 + 2;
         if(c1 + m_settings.range_lookback + 2 >= need) break;
         TryAddFVG(c1, c2, c3, tf_idx, hi, lo, op, cl, tm, atr, need);
      }
   }

   //-------------------------------------------------------------------
   // Called when a new bar opens on a timeframe – checks only the
   // bar that just closed (c3=1, c2=2, c1=3)
   //-------------------------------------------------------------------
   void CheckNewBar(int tf_idx)
   {
      int need = m_settings.range_lookback + m_settings.range_atr_period + 10;

      double hi[], lo[], op[], cl[];
      datetime tm[];
      double   atr[];

      if(!LoadBars(m_timeframes[tf_idx], need, hi, lo, op, cl, tm)) return;
      if(!LoadATR(tf_idx, need, atr))                                return;

      TryAddFVG(3, 2, 1, tf_idx, hi, lo, op, cl, tm, atr, need);
   }

   //-------------------------------------------------------------------
   // Attempt to register a bullish or bearish FVG at (c1, c2, c3)
   //-------------------------------------------------------------------
   void TryAddFVG(int c1, int c2, int c3, int tf_idx,
                  double &hi[], double &lo[], double &op[], double &cl[],
                  datetime &tm[], double &atr[], int buf)
   {
      if(c1 >= buf || c2 >= buf || c3 >= buf) return;

      ENUM_TIMEFRAMES tf = m_timeframes[tf_idx];

      // --- Bullish FVG: candle1.high < candle3.low ---
      if(hi[c1] < lo[c3])
      {
         double gap = lo[c3] - hi[c1];
         if(gap >= m_settings.min_size_pips * m_pip_size)
            if(PassesFilter(c1, c2, true, hi, lo, op, cl, atr, buf))
               AddZone(tm[c1], hi[c1], lo[c3], FVG_BULLISH, tf, tf_idx);
      }

      // --- Bearish FVG: candle1.low > candle3.high ---
      if(lo[c1] > hi[c3])
      {
         double gap = lo[c1] - hi[c3];
         if(gap >= m_settings.min_size_pips * m_pip_size)
            if(PassesFilter(c1, c2, false, hi, lo, op, cl, atr, buf))
               AddZone(tm[c1], hi[c3], lo[c1], FVG_BEARISH, tf, tf_idx);
      }
   }

   //-------------------------------------------------------------------
   // Range + breakout filter
   // c2 = the impulse (middle) candle; range is the 'range_lookback'
   // candles BEFORE c2 (i.e. indices c2+1 … c2+range_lookback)
   //-------------------------------------------------------------------
   bool PassesFilter(int c1, int c2, bool bullish,
                     double &hi[], double &lo[], double &op[], double &cl[],
                     double &atr[], int buf)
   {
      int r_start = c2 + 1;
      int r_end   = c2 + m_settings.range_lookback;
      if(r_end >= buf) return false;

      double r_high = -DBL_MAX, r_low = DBL_MAX;
      for(int i = r_start; i <= r_end; i++)
      {
         if(hi[i] > r_high) r_high = hi[i];
         if(lo[i] < r_low)  r_low  = lo[i];
      }

      double atr_val = atr[r_start]; // ATR at the edge of the range
      if(atr_val <= 0.0) return false;

      // Range must be tight: spread < range_atr_mult * ATR
      if((r_high - r_low) >= m_settings.range_atr_mult * atr_val) return false;

      // Impulse candle (c2) body must be large: body > breakout_atr_mult * ATR
      double body = MathAbs(cl[c2] - op[c2]);
      if(body < m_settings.breakout_atr_mult * atr_val) return false;

      // Impulse candle direction must match FVG direction
      bool c2_bull = (cl[c2] > op[c2]);
      if(bullish  && !c2_bull) return false;
      if(!bullish &&  c2_bull) return false;

      // Impulse candle must close BEYOND the range
      if(bullish  && cl[c2] <= r_high) return false;
      if(!bullish && cl[c2] >= r_low)  return false;

      return true;
   }

   //-------------------------------------------------------------------
   // Register a new zone (skip duplicates, reuse inactive slots)
   //-------------------------------------------------------------------
   void AddZone(datetime t_start, double bot, double top,
                ENUM_FVG_TYPE ftype, ENUM_TIMEFRAMES tf, int tf_idx)
   {
      // Duplicate check
      for(int i = 0; i < m_zone_count; i++)
         if(m_zones[i].active &&
            m_zones[i].time_start == t_start &&
            m_zones[i].timeframe  == tf      &&
            m_zones[i].fvg_type   == ftype)
            return;

      // Find empty slot or expand array
      int slot = -1;
      for(int i = 0; i < m_zone_count; i++)
         if(!m_zones[i].active) { slot = i; break; }
      if(slot == -1)
      {
         if(m_zone_count >= FVG_MAX_ZONES) return;
         slot = m_zone_count++;
      }

      string name = FVG_OBJ_PREFIX + m_tf_names[tf_idx] + "_" +
                    IntegerToString(m_obj_counter++);

      m_zones[slot].time_start     = t_start;
      m_zones[slot].top            = top;
      m_zones[slot].bottom         = bot;
      m_zones[slot].current_top    = top;
      m_zones[slot].current_bottom = bot;
      m_zones[slot].fvg_type       = ftype;
      m_zones[slot].timeframe      = tf;
      m_zones[slot].tf_index       = tf_idx;
      m_zones[slot].obj_name       = name;
      m_zones[slot].active         = true;
      m_zones[slot].drawn          = false;
   }

   //-------------------------------------------------------------------
   // Cache the current-bar high/low for every monitored timeframe
   //-------------------------------------------------------------------
   void CachePrices()
   {
      for(int i = 0; i < 7; i++)
      {
         double h[], l[];
         ArraySetAsSeries(h, true);
         ArraySetAsSeries(l, true);
         if(CopyHigh(m_symbol, m_timeframes[i], 0, 1, h) == 1) m_tf_high[i] = h[0];
         if(CopyLow (m_symbol, m_timeframes[i], 0, 1, l) == 1) m_tf_low[i]  = l[0];
      }
   }

   //-------------------------------------------------------------------
   // Shrink rectangles as price fills the gap; remove when fully filled
   //-------------------------------------------------------------------
   void UpdateFillTracking()
   {
      for(int i = 0; i < m_zone_count; i++)
      {
         if(!m_zones[i].active) continue;

         double cur_high = m_tf_high[m_zones[i].tf_index];
         double cur_low  = m_tf_low [m_zones[i].tf_index];

         if(m_zones[i].fvg_type == FVG_BULLISH)
         {
            // Bullish gap fills from the TOP as price retraces down
            if(cur_low < m_zones[i].current_top)
            {
               double new_top = MathMax(cur_low, m_zones[i].current_bottom);
               m_zones[i].current_top = new_top;
            }
         }
         else // FVG_BEARISH
         {
            // Bearish gap fills from the BOTTOM as price retraces up
            if(cur_high > m_zones[i].current_bottom)
            {
               double new_bot = MathMin(cur_high, m_zones[i].current_top);
               m_zones[i].current_bottom = new_bot;
            }
         }

         // Fully filled → remove
         if(m_zones[i].current_top <= m_zones[i].current_bottom + m_point * 0.5)
         {
            if(m_zones[i].drawn)
               ObjectDelete(0, m_zones[i].obj_name);
            m_zones[i].active = false;
         }
      }
   }

   //-------------------------------------------------------------------
   // Create or update chart rectangles for the current chart timeframe
   //-------------------------------------------------------------------
   void UpdateDrawings()
   {
      ENUM_TIMEFRAMES chart_tf  = (ENUM_TIMEFRAMES)Period();
      datetime        right     = TimeCurrent() + (datetime)(PeriodSeconds(chart_tf) * 20);

      for(int i = 0; i < m_zone_count; i++)
      {
         if(!m_zones[i].active)             continue;
         if(m_zones[i].timeframe != chart_tf) continue;

         color c = (m_zones[i].fvg_type == FVG_BULLISH)
                   ? m_settings.bullish_colour
                   : m_settings.bearish_colour;

         if(!m_zones[i].drawn)
         {
            if(ObjectCreate(0, m_zones[i].obj_name, OBJ_RECTANGLE, 0,
                            m_zones[i].time_start, m_zones[i].current_top,
                            right,                 m_zones[i].current_bottom))
            {
               ObjectSetInteger(0, m_zones[i].obj_name, OBJPROP_COLOR,        c);
               ObjectSetInteger(0, m_zones[i].obj_name, OBJPROP_FILL,         true);
               ObjectSetInteger(0, m_zones[i].obj_name, OBJPROP_BACK,         true);
               ObjectSetInteger(0, m_zones[i].obj_name, OBJPROP_TRANSPARENCY, m_settings.opacity);
               ObjectSetInteger(0, m_zones[i].obj_name, OBJPROP_SELECTABLE,   false);
               ObjectSetInteger(0, m_zones[i].obj_name, OBJPROP_HIDDEN,       true);
               m_zones[i].drawn = true;
            }
         }
         else
         {
            // Shrink top/bottom and push right edge forward
            ObjectSetDouble (0, m_zones[i].obj_name, OBJPROP_PRICE, 0, m_zones[i].current_top);
            ObjectSetDouble (0, m_zones[i].obj_name, OBJPROP_PRICE, 1, m_zones[i].current_bottom);
            ObjectSetInteger(0, m_zones[i].obj_name, OBJPROP_TIME,  1, right);
         }
      }

      ChartRedraw(0);
   }

   //-------------------------------------------------------------------
   // Helpers: load OHLC and ATR buffers (arrays as series, index 0=newest)
   //-------------------------------------------------------------------
   bool LoadBars(ENUM_TIMEFRAMES tf, int count,
                 double &hi[], double &lo[], double &op[], double &cl[], datetime &tm[])
   {
      ArraySetAsSeries(hi, true); ArraySetAsSeries(lo, true);
      ArraySetAsSeries(op, true); ArraySetAsSeries(cl, true);
      ArraySetAsSeries(tm, true);
      if(CopyHigh (m_symbol, tf, 0, count, hi) < count) return false;
      if(CopyLow  (m_symbol, tf, 0, count, lo) < count) return false;
      if(CopyOpen (m_symbol, tf, 0, count, op) < count) return false;
      if(CopyClose(m_symbol, tf, 0, count, cl) < count) return false;
      if(CopyTime (m_symbol, tf, 0, count, tm) < count) return false;
      return true;
   }

   bool LoadATR(int tf_idx, int count, double &buf[])
   {
      ArraySetAsSeries(buf, true);
      return (CopyBuffer(m_atr_handles[tf_idx], 0, 0, count, buf) >= count);
   }
};

#endif // FVG_MQH
