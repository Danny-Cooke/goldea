//+------------------------------------------------------------------+
//|  Divergence.mqh  -  RSI / MACD Divergence Filter Module         |
//+------------------------------------------------------------------+
//  Detects classic (regular) bullish and bearish divergence on up
//  to two user-selected timeframes using RSI and/or MACD.
//
//  Bullish divergence : price makes a lower low   while indicator
//                       makes a higher low  at the same swing pivot.
//  Bearish divergence : price makes a higher high while indicator
//                       makes a lower high  at the same swing pivot.
//
//  Pivot detection (as-series arrays, index 0 = newest bar):
//    Bar i is a pivot LOW  if lo[i] is the lowest in window [i-right .. i+left]
//    Bar i is a pivot HIGH if hi[i] is the highest in window [i-right .. i+left]
//  (lower index = more recent, so "left" lookback reaches into history
//   and "right" confirmation waits for newer bars to form)
//
//  MACD divergence uses the main line (buffer 0: fast EMA - slow EMA).
//  RSI divergence uses the RSI line (buffer 0).
//
//  Chart label sits at YDISTANCE=40 (below TrendFilter label at Y=20).
//+------------------------------------------------------------------+
#ifndef DIVERGENCE_MQH
#define DIVERGENCE_MQH

#define DIV_OBJ_PREFIX "DIV_"

//+------------------------------------------------------------------+
//| Confirmation mode                                                |
//+------------------------------------------------------------------+
enum ENUM_DIV_CONFIRM
{
   DIV_ANY_ENABLED,      // Any enabled indicator on any TF shows divergence
   DIV_BOTH_TIMEFRAMES,  // At least one enabled indicator shows div on BOTH TFs
   DIV_BOTH_INDICATORS,  // Both enabled indicators each show div (on any TF)
   DIV_FULL              // All enabled indicators on BOTH TFs show divergence
};

//+------------------------------------------------------------------+
//| Settings struct                                                  |
//+------------------------------------------------------------------+
struct DivergenceSettings
{
   bool             use_rsi;        // Enable RSI divergence check
   bool             use_macd;       // Enable MACD divergence check
   ENUM_TIMEFRAMES  tf1;            // First timeframe to analyse
   ENUM_TIMEFRAMES  tf2;            // Second timeframe to analyse
   int              rsi_period;     // RSI period (e.g. 14)
   int              macd_fast;      // MACD fast EMA period
   int              macd_slow;      // MACD slow EMA period
   int              macd_signal;    // MACD signal period
   int              pivot_left;     // Bars to LEFT  (older) required to confirm a pivot
   int              pivot_right;    // Bars to RIGHT (newer) required to confirm a pivot
   int              max_bars;       // How far back to scan for swing pivots
   ENUM_DIV_CONFIRM confirm_mode;   // Required confirmation level
};

//+------------------------------------------------------------------+
//| CDivergenceModule                                                |
//+------------------------------------------------------------------+
class CDivergenceModule
{
private:
   DivergenceSettings m_settings;
   string             m_symbol;

   // Handles: [0]=tf1, [1]=tf2
   int  m_rsi_handle[2];
   int  m_macd_handle[2];

   // Cached results refreshed once per bar
   bool m_bull;
   bool m_bear;
   // Per-cell detail cache for label: [is_bull][ind_idx][tf_idx]
   bool m_cell[2][2][2];   // [0=bear/1=bull][0=RSI/1=MACD][0=tf1/1=tf2]

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
      ArrayInitialize(m_cell, false);
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

      Refresh();
      DrawLabel();
      return true;
   }

   //--- Deinit --------------------------------------------------------
   void Deinit()
   {
      ObjectsDeleteAll(0, DIV_OBJ_PREFIX);

      for(int i = 0; i < 2; i++)
      {
         if(m_rsi_handle[i] != INVALID_HANDLE)
         {
            IndicatorRelease(m_rsi_handle[i]);
            m_rsi_handle[i] = INVALID_HANDLE;
         }
         if(m_macd_handle[i] != INVALID_HANDLE)
         {
            IndicatorRelease(m_macd_handle[i]);
            m_macd_handle[i] = INVALID_HANDLE;
         }
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
      DrawLabel();
   }

   //--- Public query API (IFVG checks these before placing orders) ---
   bool IsBullishSupported() { return m_bull; }
   bool IsBearishSupported() { return m_bear; }

private:
   //--- Refresh all cached values ------------------------------------
   void Refresh()
   {
      // Fill per-cell matrix
      ENUM_TIMEFRAMES tfs[2];
      tfs[0] = m_settings.tf1;
      tfs[1] = m_settings.tf2;

      for(int bull_int = 0; bull_int <= 1; bull_int++)
      {
         bool bull = (bull_int == 1);
         for(int tf = 0; tf < 2; tf++)
         {
            m_cell[bull_int][0][tf] = m_settings.use_rsi
                                    && CheckDiv(m_rsi_handle[tf],  tfs[tf], bull);
            m_cell[bull_int][1][tf] = m_settings.use_macd
                                    && CheckDiv(m_macd_handle[tf], tfs[tf], bull);
         }
      }

      m_bull = EvaluateConfirmation(true);
      m_bear = EvaluateConfirmation(false);
   }

   //--- Apply confirmation mode to cached cells ----------------------
   bool EvaluateConfirmation(bool bull)
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
            return (m_settings.use_rsi  && rsi_any)
                || (m_settings.use_macd && macd_any);

         case DIV_BOTH_TIMEFRAMES:
            return tf0_any && tf1_any;

         case DIV_BOTH_INDICATORS:
            // Each enabled indicator must fire on at least one TF
            return (m_settings.use_rsi  ? rsi_any  : true)
                && (m_settings.use_macd ? macd_any : true);

         case DIV_FULL:
            // Every enabled indicator must fire on both TFs
            return (m_settings.use_rsi  ? (rsi_tf0  && rsi_tf1)  : true)
                && (m_settings.use_macd ? (macd_tf0 && macd_tf1) : true);
      }

      return false;
   }

   //--- Detect divergence for one indicator on one timeframe ---------
   bool CheckDiv(int ind_handle, ENUM_TIMEFRAMES tf, bool bull)
   {
      if(ind_handle == INVALID_HANDLE) return false;

      int need = m_settings.max_bars + m_settings.pivot_left + 1;

      // Price arrays (need both hi and lo for pivot windows)
      double hi[], lo[];
      ArraySetAsSeries(hi, true);
      ArraySetAsSeries(lo, true);
      if(CopyHigh(m_symbol, tf, 0, need, hi) < need) return false;
      if(CopyLow (m_symbol, tf, 0, need, lo) < need) return false;

      // Indicator: RSI buffer 0 = RSI line
      //            MACD buffer 0 = main line (fast EMA - slow EMA)
      double ind[];
      ArraySetAsSeries(ind, true);
      if(CopyBuffer(ind_handle, 0, 0, need, ind) < need) return false;

      // Find two most recent pivot lows (bull) or pivot highs (bear)
      int p1 = -1, p2 = -1;
      int left  = m_settings.pivot_left;
      int right = m_settings.pivot_right;

      for(int i = right; i < m_settings.max_bars && p2 < 0; i++)
      {
         if(i + left >= need) break;

         bool hit = bull ? IsPivotLow (lo, i, left, right, need)
                         : IsPivotHigh(hi, i, left, right, need);
         if(!hit) continue;

         if(p1 < 0) p1 = i;
         else       p2 = i;
      }

      if(p1 < 0 || p2 < 0) return false;   // fewer than 2 pivots found

      // p1 = more recent pivot (lower index), p2 = older pivot (higher index)
      // Bullish : price lower low (lo[p1] < lo[p2]) AND indicator higher low (ind[p1] > ind[p2])
      // Bearish : price higher high (hi[p1] > hi[p2]) AND indicator lower high (ind[p1] < ind[p2])
      if(bull)
         return (lo[p1] < lo[p2]) && (ind[p1] > ind[p2]);
      else
         return (hi[p1] > hi[p2]) && (ind[p1] < ind[p2]);
   }

   //--- Pivot detection helpers --------------------------------------
   //
   //  As-series: index 0 = newest bar.
   //  left  → older bars (higher indices)
   //  right → newer bars (lower indices)
   //
   //  Pivot LOW  : lo[i] must be the LOWEST bar in the full window
   //  Pivot HIGH : hi[i] must be the HIGHEST bar in the full window
   //
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

   //--- Chart label --------------------------------------------------
   void DrawLabel()
   {
      string dir_text;
      color  col;
      if(m_bull && m_bear)   { dir_text = "BOTH";    col = clrGold;   }
      else if(m_bull)        { dir_text = "BULLISH";  col = clrLime;   }
      else if(m_bear)        { dir_text = "BEARISH";  col = clrTomato; }
      else                   { dir_text = "NONE";     col = clrGray;   }

      // Per-cell detail — show cells for the active direction;
      // if both or none, show bull cells by convention
      int b = m_bear && !m_bull ? 0 : 1;

      string tf1_str = EnumToString(m_settings.tf1);
      string tf2_str = EnumToString(m_settings.tf2);
      string detail  = " [";

      if(m_settings.use_rsi)
      {
         detail += "RSI-" + tf1_str + ":" + (m_cell[b][0][0] ? "Y" : "N") + " ";
         detail += "RSI-" + tf2_str + ":" + (m_cell[b][0][1] ? "Y" : "N") + " ";
      }
      if(m_settings.use_macd)
      {
         detail += "MACD-" + tf1_str + ":" + (m_cell[b][1][0] ? "Y" : "N") + " ";
         detail += "MACD-" + tf2_str + ":" + (m_cell[b][1][1] ? "Y" : "N");
      }
      StringTrimRight(detail);
      detail += "]";

      string text = "Div: " + dir_text + detail;
      string name = DIV_OBJ_PREFIX + "LABEL";

      if(ObjectFind(0, name) < 0)
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
      ChartRedraw(0);
   }
};

#endif
