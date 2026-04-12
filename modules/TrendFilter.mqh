//+------------------------------------------------------------------+
//|  TrendFilter.mqh  -  Multi-Timeframe EMA Trend Bias Module      |
//+------------------------------------------------------------------+
//  Scores M15 / H1 / H4 trend using a 50 EMA each:
//    +1 if close > EMA and EMA is rising
//    -1 if close < EMA and EMA is falling
//     0 mixed / unclear
//
//  Total score -3 to +3.
//  Long  allowed when score >= +min_score
//  Short allowed when score <= -min_score
//+------------------------------------------------------------------+
#ifndef TRENDFILTER_MQH
#define TRENDFILTER_MQH

#define TF_OBJ_PREFIX "TF_"

struct TrendFilterSettings
{
   ENUM_TIMEFRAMES tf1;         // e.g. PERIOD_M15
   ENUM_TIMEFRAMES tf2;         // e.g. PERIOD_H1
   ENUM_TIMEFRAMES tf3;         // e.g. PERIOD_H4
   int             ema_period;  // 50
   int             min_score;   // min abs score to allow trade (1, 2, or 3)
};

//+------------------------------------------------------------------+
class CTrendFilterModule
{
private:
   TrendFilterSettings m_settings;
   string              m_symbol;
   int                 m_ema[3];   // handles for tf1/tf2/tf3

public:
   CTrendFilterModule(TrendFilterSettings &s)
   {
      m_settings = s;
      m_symbol   = Symbol();
      m_ema[0] = m_ema[1] = m_ema[2] = INVALID_HANDLE;
   }

   bool Init()
   {
      ENUM_TIMEFRAMES tfs[3];
      tfs[0] = m_settings.tf1;
      tfs[1] = m_settings.tf2;
      tfs[2] = m_settings.tf3;

      for(int i = 0; i < 3; i++)
      {
         m_ema[i] = iMA(m_symbol, tfs[i], m_settings.ema_period, 0, MODE_EMA, PRICE_CLOSE);
         if(m_ema[i] == INVALID_HANDLE)
         {
            PrintFormat("TrendFilter: failed to create EMA handle for TF %d", i);
            return false;
         }
      }
      DrawLabel();
      return true;
   }

   void Deinit()
   {
      ObjectsDeleteAll(0, TF_OBJ_PREFIX);
      for(int i = 0; i < 3; i++)
         if(m_ema[i] != INVALID_HANDLE)
         {
            IndicatorRelease(m_ema[i]);
            m_ema[i] = INVALID_HANDLE;
         }
   }

   void Update()
   {
      static datetime last_bar = 0;
      datetime t[];
      ArraySetAsSeries(t, true);
      if(CopyTime(m_symbol, PERIOD_CURRENT, 0, 1, t) != 1) return;
      if(t[0] == last_bar) return;
      last_bar = t[0];
      DrawLabel();
   }

   //--- Public API ---------------------------------------------------

   // Returns -3 to +3
   int GetScore()
   {
      ENUM_TIMEFRAMES tfs[3];
      tfs[0] = m_settings.tf1;
      tfs[1] = m_settings.tf2;
      tfs[2] = m_settings.tf3;

      int total = 0;
      for(int i = 0; i < 3; i++)
         total += ScoreTF(m_ema[i], tfs[i]);
      return total;
   }

   bool IsLongAllowed()  { return GetScore() >=  m_settings.min_score; }
   bool IsShortAllowed() { return GetScore() <= -m_settings.min_score; }

private:
   //--- Score one timeframe -----------------------------------------
   int ScoreTF(int handle, ENUM_TIMEFRAMES tf)
   {
      if(handle == INVALID_HANDLE) return 0;

      double ema[], cl[];
      ArraySetAsSeries(ema, true);
      ArraySetAsSeries(cl,  true);

      // Need 2 EMA bars to detect slope
      if(CopyBuffer(handle, 0, 0, 2, ema) < 2) return 0;
      if(CopyClose(m_symbol, tf, 0, 1, cl) < 1) return 0;

      bool above  = cl[0]  > ema[0];
      bool rising = ema[0] > ema[1];

      if( above &&  rising) return +1;
      if(!above && !rising) return -1;
      return 0;
   }

   //--- Chart label -------------------------------------------------
   void DrawLabel()
   {
      int    score = GetScore();
      string dir   = score >=  m_settings.min_score ? "BULLISH"
                   : score <= -m_settings.min_score ? "BEARISH"
                   : "NEUTRAL";
      color  col   = score >=  m_settings.min_score ? clrLime
                   : score <= -m_settings.min_score ? clrTomato
                   : clrGray;

      // Individual scores for debugging
      ENUM_TIMEFRAMES tfs[3];
      tfs[0] = m_settings.tf1;
      tfs[1] = m_settings.tf2;
      tfs[2] = m_settings.tf3;

      string detail = "";
      string tf_names[3] = {"M15","H1","H4"};
      // override names with actual TF strings
      tf_names[0] = EnumToString(m_settings.tf1);
      tf_names[1] = EnumToString(m_settings.tf2);
      tf_names[2] = EnumToString(m_settings.tf3);

      for(int i = 0; i < 3; i++)
      {
         int s = ScoreTF(m_ema[i], tfs[i]);
         detail += "  " + tf_names[i] + ":" + (s > 0 ? "+" : "") + IntegerToString(s);
      }

      string name = TF_OBJ_PREFIX + "BIAS";
      string text = "Trend " + dir + " (" + (score > 0 ? "+" : "") + IntegerToString(score) + ")" + detail;

      if(ObjectFind(0, name) < 0)
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);

      ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 20);
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
