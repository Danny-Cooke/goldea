//+------------------------------------------------------------------+
//|  IFVG.mqh  -  Inverted Fair Value Gap Module                     |
//+------------------------------------------------------------------+
#ifndef IFVG_MQH
#define IFVG_MQH

#include <Trade/Trade.mqh>

#define IFVG_OBJ_PREFIX "IFVG_"

enum ENUM_IFVG_SL_MODE
{
   IFVG_SL_SWING = 0,  // Swing high/low + buffer
   IFVG_SL_ATR   = 1   // ATR Stop (lo - ATR*mult / hi + ATR*mult)
};

struct IFVGSettings
{
   int    history_candles;
   color  colour;
   int    count;            // draw last N zones by fill time
   bool   invalidate;       // remove if price breaks back through
   double tp_multiplier;    // TP = swing-distance * this value  (e.g. 2.0)
   int    sl_lookback;      // bars back to search for swing hi/lo
   double sl_buffer_pts;    // extra buffer on SL in points (SWING mode only)
   color  long_colour;
   color  short_colour;
   // Trading
   double              lot_size;
   int                 magic;
   // SL mode
   ENUM_IFVG_SL_MODE   sl_mode;
   int                 atr_period;       // used when sl_mode = IFVG_SL_ATR
   double              atr_multiplier;   // used when sl_mode = IFVG_SL_ATR
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
   CTrade       m_trade;
   int          m_atr_handle;

   // Active setup tracking
   datetime     m_setup_fill;
   bool         m_setup_long;
   ulong        m_pending_ticket;

public:
   CIFVGModule(IFVGSettings &s)
   {
      m_settings       = s;
      m_symbol         = Symbol();
      m_atr_handle     = INVALID_HANDLE;
      m_setup_fill     = 0;
      m_setup_long     = false;
      m_pending_ticket = 0;
   }

   bool Init()
   {
      m_trade.SetExpertMagicNumber(m_settings.magic);

      if(m_settings.sl_mode == IFVG_SL_ATR)
      {
         m_atr_handle = iATR(m_symbol, PERIOD_CURRENT, m_settings.atr_period);
         if(m_atr_handle == INVALID_HANDLE)
         {
            Print("IFVG: failed to create ATR handle");
            return false;
         }
      }

      Scan();
      return true;
   }

   void Deinit()
   {
      CancelPending();
      ObjectsDeleteAll(0, IFVG_OBJ_PREFIX);
      if(m_atr_handle != INVALID_HANDLE)
      {
         IndicatorRelease(m_atr_handle);
         m_atr_handle = INVALID_HANDLE;
      }
   }

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

      SortDesc(ifvgs);

      int total  = ArraySize(ifvgs);
      int draw_n = MathMin(total, m_settings.count);

      for(int i = 0; i < draw_n; i++)
         DrawRect("Z_" + IntegerToString(i),
                  ifvgs[i].time_start, ifvgs[i].top, ifvgs[i].bottom);

      if(total > 0)
      {
         DrawSetup(ifvgs[0], hi, lo, bars);
         ManageTrade(ifvgs[0], hi, lo, bars);
      }
      else
         CancelPending();

      PrintFormat("IFVG | found=%d  showing=%d  invalidate=%s  tp_mult=%.1f  sl=%s",
                  total, draw_n,
                  m_settings.invalidate ? "ON" : "OFF",
                  m_settings.tp_multiplier,
                  m_settings.sl_mode == IFVG_SL_ATR ? "ATR" : "SWING");
      if(total > 0)
         PrintFormat("IFVG | latest=%s  top=%.5f  bot=%.5f  fill=%s",
                     ifvgs[0].is_bullish ? "SHORT-setup" : "LONG-setup",
                     ifvgs[0].top, ifvgs[0].bottom,
                     TimeToString(ifvgs[0].fill_time));

      ChartRedraw(0);
   }

   //--- Shared level computation (draw + trade) ----------------------
   //
   //  SL source depends on sl_mode:
   //    SWING → recent swing low/high ± buffer  (unchanged)
   //    ATR   → lo[0] - ATR*mult  (long)
   //             hi[0] + ATR*mult  (short)
   //
   //  TP is always:  entry ± swing_distance × tp_multiplier
   //  (swing_distance = entry − swing_lo  /  swing_hi − entry)
   //------------------------------------------------------------------
   void ComputeLevels(IFVGZone &z, double &hi[], double &lo[], int bars,
                      bool &is_long, double &entry, double &sl, double &tp)
   {
      entry      = (z.top + z.bottom) / 2.0;
      is_long    = !z.is_bullish;

      int lb = MathMin(m_settings.sl_lookback, bars - 1);
      double swing_lo = lo[0];
      double swing_hi = hi[0];
      for(int k = 1; k <= lb; k++)
      {
         if(lo[k] < swing_lo) swing_lo = lo[k];
         if(hi[k] > swing_hi) swing_hi = hi[k];
      }

      // --- SL ---
      if(m_settings.sl_mode == IFVG_SL_ATR)
      {
         double atr_val = GetATR(0);
         if(atr_val <= 0) atr_val = 0;  // fallback: SL at entry (will be skipped by trade logic)
         if(is_long)
            sl = lo[0] - atr_val * m_settings.atr_multiplier;
         else
            sl = hi[0] + atr_val * m_settings.atr_multiplier;
      }
      else  // SWING
      {
         double buf = m_settings.sl_buffer_pts * _Point;
         sl = is_long ? swing_lo - buf : swing_hi + buf;
      }

      // --- TP: always based on swing distance from entry ---
      double swing_dist = is_long ? (entry - swing_lo) : (swing_hi - entry);
      if(swing_dist <= 0) swing_dist = MathAbs(entry - sl);  // fallback
      tp = is_long ? entry + swing_dist * m_settings.tp_multiplier
                   : entry - swing_dist * m_settings.tp_multiplier;
   }

   double GetATR(int shift)
   {
      if(m_atr_handle == INVALID_HANDLE) return 0;
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(m_atr_handle, 0, shift, 1, buf) == 1)
         return buf[0];
      return 0;
   }

   //--- Draw trade setup lines ---------------------------------------
   void DrawSetup(IFVGZone &z, double &hi[], double &lo[], int bars)
   {
      bool is_long; double entry, sl, tp;
      ComputeLevels(z, hi, lo, bars, is_long, entry, sl, tp);

      string dir_tag  = is_long ? "LONG" : "SHORT";
      color  line_col = is_long ? m_settings.long_colour : m_settings.short_colour;
      double risk     = MathAbs(entry - sl);

      DrawHLine("ENTRY", entry, line_col, STYLE_SOLID,
                dir_tag + "  Entry @ " + DoubleToString(entry, _Digits));
      DrawHLine("SL", sl, clrRed, STYLE_DASHDOT,
                dir_tag + "  SL    @ " + DoubleToString(sl, _Digits)
                + "  (risk=" + DoubleToString(risk / _Point, 0) + " pts)");
      DrawHLine("TP", tp, clrLime, STYLE_DASH,
                dir_tag + "  TP    @ " + DoubleToString(tp, _Digits)
                + "  (" + DoubleToString(m_settings.tp_multiplier, 1) + "R)");
   }

   //--- Trade management ---------------------------------------------
   void ManageTrade(IFVGZone &z, double &hi[], double &lo[], int bars)
   {
      bool is_long; double entry, sl, tp;
      ComputeLevels(z, hi, lo, bars, is_long, entry, sl, tp);

      bool setup_changed = (z.fill_time != m_setup_fill || is_long != m_setup_long);
      if(!setup_changed) return;

      CancelPending();

      if(!HasOpenPosition())
         PlaceLimitOrder(is_long, entry, sl, tp);

      m_setup_fill = z.fill_time;
      m_setup_long = is_long;
   }

   bool HasOpenPosition()
   {
      for(int i = 0; i < PositionsTotal(); i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0
            && PositionGetInteger(POSITION_MAGIC) == (long)m_settings.magic
            && PositionGetString(POSITION_SYMBOL) == m_symbol)
            return true;
      }
      return false;
   }

   void CancelPending()
   {
      if(m_pending_ticket == 0) return;
      if(OrderSelect(m_pending_ticket))
         m_trade.OrderDelete(m_pending_ticket);
      m_pending_ticket = 0;
   }

   void PlaceLimitOrder(bool is_long, double entry, double sl, double tp)
   {
      double price = NormalizeDouble(entry, _Digits);
      sl           = NormalizeDouble(sl,    _Digits);
      tp           = NormalizeDouble(tp,    _Digits);

      // Sanity: sl must be on the correct side of entry
      if(is_long  && sl >= price) { Print("IFVG: SL >= entry for LONG, skipping"); return; }
      if(!is_long && sl <= price) { Print("IFVG: SL <= entry for SHORT, skipping"); return; }

      bool placed = false;
      if(is_long)
      {
         double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
         if(price < ask)
            placed = m_trade.BuyLimit(m_settings.lot_size, price, m_symbol, sl, tp);
      }
      else
      {
         double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
         if(price > bid)
            placed = m_trade.SellLimit(m_settings.lot_size, price, m_symbol, sl, tp);
      }

      if(placed)
         m_pending_ticket = m_trade.ResultOrder();
      else
         PrintFormat("IFVG | PlaceLimitOrder skipped – entry=%.5f not valid for %s",
                     price, is_long ? "BuyLimit" : "SellLimit");
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
