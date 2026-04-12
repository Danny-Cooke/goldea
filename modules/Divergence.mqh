//+------------------------------------------------------------------+
//|  Divergence.mqh  -  RSI / MACD Divergence Filter Module         |
//+------------------------------------------------------------------+
//  Detects classic (regular) bullish and bearish divergence on two
//  user-selected timeframes using RSI and/or MACD.
//
//  Bullish divergence : price lower low  + indicator higher low
//  Bearish divergence : price higher high + indicator lower high
//
//  Pivot detection (as-series, index 0 = newest bar):
//    Bar i is a pivot LOW  if lo[i] is the lowest  in window [i-right .. i+left]
//    Bar i is a pivot HIGH if hi[i] is the highest in window [i-right .. i+left]
//
//  VISUAL OUTPUT
//    - Arrows (up/down) drawn on price chart at the two most recent
//      swing pivots where divergence is detected.
//    - OBJ_TREND line connecting those two price pivots.
//    - OBJ_TEXT label near the most-recent pivot: "BULL DIV" / "BEAR DIV".
//    - Summary corner label (top-left, YDISTANCE=40).
//
//  MACD divergence: main line (buffer 0).  RSI divergence: buffer 0.
//+------------------------------------------------------------------+
#ifndef DIVERGENCE_MQH
#define DIVERGENCE_MQH

#define DIV_OBJ_PREFIX "DIV_"

//+------------------------------------------------------------------+
enum ENUM_DIV_CONFIRM
{
   DIV_ANY_ENABLED,      // Any enabled indicator on any TF shows divergence
   DIV_BOTH_TIMEFRAMES,  // At least one enabled indicator fires on BOTH TFs
   DIV_BOTH_INDICATORS,  // Both enabled indicators each fire (on any TF)
   DIV_FULL              // All enabled indicators on BOTH TFs confirm
};

//+------------------------------------------------------------------+
struct DivergenceSettings
{
   bool             use_rsi;
   bool             use_macd;
   ENUM_TIMEFRAMES  tf1;
   ENUM_TIMEFRAMES  tf2;
   int              rsi_period;
   int              macd_fast;
   int              macd_slow;
   int              macd_signal;
   int              pivot_left;     // bars to the LEFT  (older history) of pivot
   int              pivot_right;    // bars to the RIGHT (newer bars)   of pivot
   int              max_bars;       // how far back to scan for swing pivots
   ENUM_DIV_CONFIRM confirm_mode;
};

//+------------------------------------------------------------------+
class CDivergenceModule
{
private:
   DivergenceSettings m_settings;
   string             m_symbol;

   int  m_rsi_handle[2];    // [0]=tf1, [1]=tf2
   int  m_macd_handle[2];

   bool m_bull;
   bool m_bear;
   // m_cell[bull?1:0][rsi=0/macd=1][tf index 0/1]
   bool m_cell[2][2][2];

public:
   CDivergenceModule(DivergenceSettings &s)
   {
      m_settings = s;
      m_symbol   = Symbol();

      m_rsi_handle[0]  = INVALID_HANDLE;
      m_rsi_handle[1]  = INVALID_HANDLE;
      m_macd_handle[0] = INVALID_HANDLE;
      m_macd_handle[1] = INVALID_HANDLE;

      m_bull = false;
      m_bear = false;

      // Explicit loop — ArrayInitialize on static bool arrays is unreliable in MQL5
      for(int i = 0; i < 2; i++)
         for(int j = 0; j < 2; j++)
            for(int k = 0; k < 2; k++)
               m_cell[i][j][k] = false;
   }

   //--- Init ----------------------------------------------------------
   bool Init()
   {
      ENUM_TIMEFRAMES tfs[2];
      tfs[0] = m_settings.tf1;
      tfs[1] = m_settings.tf2;

      for(int i = 0; i < 2; i++)
      {
         if(m_settings.use_rsi)
         {
            m_rsi_handle[i] = iRSI(m_symbol, tfs[i],
                                   m_settings.rsi_period, PRICE_CLOSE);
            if(m_rsi_handle[i] == INVALID_HANDLE)
            {
               PrintFormat("Divergence: failed to create RSI handle for TF%d", i + 1);
               return false;
            }
         }

         if(m_settings.use_macd)
         {
            m_macd_handle[i] = iMACD(m_symbol, tfs[i],
                                     m_settings.macd_fast,
                                     m_settings.macd_slow,
                                     m_settings.macd_signal,
                                     PRICE_CLOSE);
            if(m_macd_handle[i] == INVALID_HANDLE)
            {
               PrintFormat("Divergence: failed to create MACD handle for TF%d", i + 1);
               return false;
            }
         }
      }

      PrintFormat("Divergence: module initialised  RSI=%s MACD=%s TF1=%s TF2=%s mode=%s",
                  m_settings.use_rsi  ? "ON" : "OFF",
                  m_settings.use_macd ? "ON" : "OFF",
                  TFShort(m_settings.tf1), TFShort(m_settings.tf2),
                  EnumToString(m_settings.confirm_mode));

      Refresh();
      Draw();
      return true;
   }

   //--- Deinit --------------------------------------------------------
   void Deinit()
   {
      ObjectsDeleteAll(0, DIV_OBJ_PREFIX);

      for(int i = 0; i < 2; i++)
      {
         if(m_rsi_handle[i]  != INVALID_HANDLE) { IndicatorRelease(m_rsi_handle[i]);  m_rsi_handle[i]  = INVALID_HANDLE; }
         if(m_macd_handle[i] != INVALID_HANDLE) { IndicatorRelease(m_macd_handle[i]); m_macd_handle[i] = INVALID_HANDLE; }
      }
   }

   //--- Update (call from OnTick) -------------------------------------
   void Update()
   {
      static datetime last_bar = 0;
      datetime t[];
      ArraySetAsSeries(t, true);
      if(CopyTime(m_symbol, PERIOD_CURRENT, 0, 1, t) != 1) return;
      if(t[0] == last_bar) return;
      last_bar = t[0];

      Refresh();
      Draw();
   }

   //--- Public query API ---------------------------------------------
   bool IsBullishSupported() { return m_bull; }
   bool IsBearishSupported() { return m_bear; }

private:
   //--- Refresh all cached values ------------------------------------
   void Refresh()
   {
      ENUM_TIMEFRAMES tfs[2];
      tfs[0] = m_settings.tf1;
      tfs[1] = m_settings.tf2;

      for(int b = 0; b <= 1; b++)
         for(int tf = 0; tf < 2; tf++)
         {
            m_cell[b][0][tf] = m_settings.use_rsi
                             && CheckDiv(m_rsi_handle[tf],  tfs[tf], b == 1);
            m_cell[b][1][tf] = m_settings.use_macd
                             && CheckDiv(m_macd_handle[tf], tfs[tf], b == 1);
         }

      m_bull = Evaluate(true);
      m_bear = Evaluate(false);
   }

   //--- Apply confirmation mode to cached cell matrix ---------------
   bool Evaluate(bool bull)
   {
      int b = bull ? 1 : 0;

      bool rsi_tf0  = m_cell[b][0][0];
      bool rsi_tf1  = m_cell[b][0][1];
      bool macd_tf0 = m_cell[b][1][0];
      bool macd_tf1 = m_cell[b][1][1];

      bool rsi_any  = rsi_tf0  || rsi_tf1;
      bool macd_any = macd_tf0 || macd_tf1;
      bool tf0_any  = rsi_tf0  || macd_tf0;
      bool tf1_any  = rsi_tf1  || macd_tf1;

      if(!m_settings.use_rsi && !m_settings.use_macd) return false;

      switch(m_settings.confirm_mode)
      {
         case DIV_ANY_ENABLED:
            return (m_settings.use_rsi && rsi_any) || (m_settings.use_macd && macd_any);

         case DIV_BOTH_TIMEFRAMES:
            return tf0_any && tf1_any;

         case DIV_BOTH_INDICATORS:
            return (m_settings.use_rsi  ? rsi_any  : true)
                && (m_settings.use_macd ? macd_any : true);

         case DIV_FULL:
            return (m_settings.use_rsi  ? (rsi_tf0 && rsi_tf1)  : true)
                && (m_settings.use_macd ? (macd_tf0 && macd_tf1) : true);
      }
      return false;
   }

   //--- CheckDiv: detect divergence for one indicator on one TF -----
   bool CheckDiv(int handle, ENUM_TIMEFRAMES tf, bool bull)
   {
      if(handle == INVALID_HANDLE) return false;

      int p1 = -1, p2 = -1;
      if(!FindPivots(handle, tf, bull, p1, p2)) return false;

      int need = m_settings.max_bars + m_settings.pivot_left + 1;

      double hi[], lo[], ind[];
      ArraySetAsSeries(hi,  true);
      ArraySetAsSeries(lo,  true);
      ArraySetAsSeries(ind, true);

      if(CopyHigh(m_symbol, tf, 0, need, hi)  < need) return false;
      if(CopyLow (m_symbol, tf, 0, need, lo)  < need) return false;
      if(CopyBuffer(handle, 0, 0, need, ind)  < need) return false;

      if(bull)
         return (lo[p1] < lo[p2]) && (ind[p1] > ind[p2]);
      else
         return (hi[p1] > hi[p2]) && (ind[p1] < ind[p2]);
   }

   //--- FindPivots: locate two most-recent pivot lows (bull) or highs (bear) --
   bool FindPivots(int handle, ENUM_TIMEFRAMES tf, bool bull, int &p1, int &p2)
   {
      if(handle == INVALID_HANDLE) return false;

      int need = m_settings.max_bars + m_settings.pivot_left + 1;
      int left  = m_settings.pivot_left;
      int right = m_settings.pivot_right;

      double hi[], lo[];
      ArraySetAsSeries(hi, true);
      ArraySetAsSeries(lo, true);

      if(CopyHigh(m_symbol, tf, 0, need, hi) < need) return false;
      if(CopyLow (m_symbol, tf, 0, need, lo) < need) return false;

      p1 = -1; p2 = -1;

      for(int i = right; i < m_settings.max_bars && p2 < 0; i++)
      {
         if(i + left >= need) break;
         bool hit = bull ? IsPivotLow (lo, i, left, right, need)
                         : IsPivotHigh(hi, i, left, right, need);
         if(hit) { if(p1 < 0) p1 = i; else p2 = i; }
      }

      return (p1 >= 0 && p2 >= 0);
   }

   //--- Pivot helpers -------------------------------------------------
   bool IsPivotLow(double &lo[], int i, int left, int right, int size)
   {
      if(i - right < 0 || i + left >= size) return false;
      double v = lo[i];
      for(int k = i - right; k <= i + left; k++)
         if(k != i && lo[k] < v) return false;
      return true;
   }

   bool IsPivotHigh(double &hi[], int i, int left, int right, int size)
   {
      if(i - right < 0 || i + left >= size) return false;
      double v = hi[i];
      for(int k = i - right; k <= i + left; k++)
         if(k != i && hi[k] > v) return false;
      return true;
   }

   //--- Master draw: wipe all, redraw chart objects + corner label ---
   void Draw()
   {
      ObjectsDeleteAll(0, DIV_OBJ_PREFIX);

      int obj_idx = 0;

      ENUM_TIMEFRAMES tfs[2];
      tfs[0] = m_settings.tf1;
      tfs[1] = m_settings.tf2;

      // Colours per direction (TF1 slightly brighter, TF2 slightly muted)
      color bull_col[2]; bull_col[0] = clrLimeGreen;    bull_col[1] = clrMediumSeaGreen;
      color bear_col[2]; bear_col[0] = clrRed;           bear_col[1] = clrOrangeRed;

      for(int ti = 0; ti < 2; ti++)
      {
         if(m_settings.use_rsi)
         {
            if(m_cell[1][0][ti])  // bullish RSI
               DrawDivLines(m_rsi_handle[ti], tfs[ti], true,  bull_col[ti], obj_idx, "RSI");
            if(m_cell[0][0][ti])  // bearish RSI
               DrawDivLines(m_rsi_handle[ti], tfs[ti], false, bear_col[ti], obj_idx, "RSI");
         }
         if(m_settings.use_macd)
         {
            if(m_cell[1][1][ti])  // bullish MACD
               DrawDivLines(m_macd_handle[ti], tfs[ti], true,  bull_col[ti], obj_idx, "MACD");
            if(m_cell[0][1][ti])  // bearish MACD
               DrawDivLines(m_macd_handle[ti], tfs[ti], false, bear_col[ti], obj_idx, "MACD");
         }
      }

      DrawCornerLabel();
      ChartRedraw(0);
   }

   //--- Draw arrows + trend line for one detected divergence ---------
   void DrawDivLines(int handle, ENUM_TIMEFRAMES tf, bool bull,
                     color col, int &idx, string ind_name)
   {
      int p1 = -1, p2 = -1;
      if(!FindPivots(handle, tf, bull, p1, p2)) return;

      int need = m_settings.max_bars + m_settings.pivot_left + 1;

      double hi[], lo[];
      datetime tm[];
      ArraySetAsSeries(hi, true);
      ArraySetAsSeries(lo, true);
      ArraySetAsSeries(tm, true);

      if(CopyHigh(m_symbol, tf, 0, need, hi) < need) return;
      if(CopyLow (m_symbol, tf, 0, need, lo) < need) return;
      if(CopyTime(m_symbol, tf, 0, need, tm) < need) return;

      double price1 = bull ? lo[p1] : hi[p1];
      double price2 = bull ? lo[p2] : hi[p2];

      // Arrows at both pivots
      ENUM_OBJECT arr_type = bull ? OBJ_ARROW_UP : OBJ_ARROW_DOWN;

      string n_arr1 = DIV_OBJ_PREFIX + IntegerToString(idx++);
      string n_arr2 = DIV_OBJ_PREFIX + IntegerToString(idx++);
      string n_line = DIV_OBJ_PREFIX + IntegerToString(idx++);
      string n_txt  = DIV_OBJ_PREFIX + IntegerToString(idx++);

      ObjectCreate(0, n_arr1, arr_type, 0, tm[p1], price1);
      ObjectSetInteger(0, n_arr1, OBJPROP_COLOR,      col);
      ObjectSetInteger(0, n_arr1, OBJPROP_WIDTH,      2);
      ObjectSetInteger(0, n_arr1, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n_arr1, OBJPROP_HIDDEN,     true);

      ObjectCreate(0, n_arr2, arr_type, 0, tm[p2], price2);
      ObjectSetInteger(0, n_arr2, OBJPROP_COLOR,      col);
      ObjectSetInteger(0, n_arr2, OBJPROP_WIDTH,      2);
      ObjectSetInteger(0, n_arr2, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n_arr2, OBJPROP_HIDDEN,     true);

      // Trend line connecting the two price pivots
      ObjectCreate(0, n_line, OBJ_TREND, 0, tm[p2], price2, tm[p1], price1);
      ObjectSetInteger(0, n_line, OBJPROP_COLOR,     col);
      ObjectSetInteger(0, n_line, OBJPROP_WIDTH,     2);
      ObjectSetInteger(0, n_line, OBJPROP_STYLE,     STYLE_DASH);
      ObjectSetInteger(0, n_line, OBJPROP_RAY_LEFT,  false);
      ObjectSetInteger(0, n_line, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, n_line, OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0, n_line, OBJPROP_HIDDEN,    true);

      // Text label at the most-recent pivot
      string label = (bull ? "BULL" : "BEAR") + string(" DIV ") + ind_name
                   + " " + TFShort(tf);
      ObjectCreate(0, n_txt, OBJ_TEXT, 0, tm[p1], price1);
      ObjectSetString (0, n_txt, OBJPROP_TEXT,      label);
      ObjectSetInteger(0, n_txt, OBJPROP_COLOR,     col);
      ObjectSetInteger(0, n_txt, OBJPROP_FONTSIZE,  8);
      ObjectSetString (0, n_txt, OBJPROP_FONT,      "Consolas");
      ObjectSetInteger(0, n_txt, OBJPROP_ANCHOR,    bull ? ANCHOR_UPPER : ANCHOR_LOWER);
      ObjectSetInteger(0, n_txt, OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0, n_txt, OBJPROP_HIDDEN,    true);
   }

   //--- Corner summary label ----------------------------------------
   void DrawCornerLabel()
   {
      string dir;
      color  col;
      if(m_bull && m_bear)   { dir = "BOTH";    col = clrGold;   }
      else if(m_bull)        { dir = "BULLISH";  col = clrLime;   }
      else if(m_bear)        { dir = "BEARISH";  col = clrTomato; }
      else                   { dir = "NONE";     col = clrGray;   }

      // Per-cell Y/N detail
      int b = (m_bear && !m_bull) ? 0 : 1;
      string detail = "  [";
      if(m_settings.use_rsi)
      {
         detail += "RSI-" + TFShort(m_settings.tf1) + ":" + (m_cell[b][0][0] ? "Y":"N") + " ";
         detail += "RSI-" + TFShort(m_settings.tf2) + ":" + (m_cell[b][0][1] ? "Y":"N") + " ";
      }
      if(m_settings.use_macd)
      {
         detail += "MACD-" + TFShort(m_settings.tf1) + ":" + (m_cell[b][1][0] ? "Y":"N") + " ";
         detail += "MACD-" + TFShort(m_settings.tf2) + ":" + (m_cell[b][1][1] ? "Y":"N");
      }
      StringTrimRight(detail);
      detail += "]";

      string name = DIV_OBJ_PREFIX + "LABEL";
      string text = "Div: " + dir + detail;

      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 40);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  11);
      ObjectSetString (0, name, OBJPROP_FONT,      "Consolas");
      ObjectSetInteger(0, name, OBJPROP_COLOR,     col);
      ObjectSetString (0, name, OBJPROP_TEXT,      text);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,    true);
   }

   //--- Short timeframe name helper ----------------------------------
   string TFShort(ENUM_TIMEFRAMES tf)
   {
      switch(tf)
      {
         case PERIOD_M1:  return "M1";
         case PERIOD_M5:  return "M5";
         case PERIOD_M15: return "M15";
         case PERIOD_M30: return "M30";
         case PERIOD_H1:  return "H1";
         case PERIOD_H4:  return "H4";
         case PERIOD_D1:  return "D1";
         case PERIOD_W1:  return "W1";
         case PERIOD_MN1: return "MN";
         default:         return EnumToString(tf);
      }
   }
};

#endif
