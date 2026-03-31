//+------------------------------------------------------------------+
//|  ATRStop.mqh  -  ATR Stop Loss Finder Module                     |
//+------------------------------------------------------------------+
#ifndef ATRSTOP_MQH
#define ATRSTOP_MQH

#define ATRSTOP_OBJ_PREFIX "ATRSTOP_"

struct ATRStopSettings
{
   int    atr_period;
   double atr_multiplier;
   int    lookback_bars;
   color  long_colour;
   color  short_colour;
};

//+------------------------------------------------------------------+
class CATRStopModule
{
private:
   ATRStopSettings m_settings;
   string          m_symbol;
   int             m_atr_handle;

public:
   CATRStopModule(ATRStopSettings &s)
   {
      m_settings   = s;
      m_symbol     = Symbol();
      m_atr_handle = INVALID_HANDLE;
   }

   bool Init()
   {
      m_atr_handle = iATR(m_symbol, PERIOD_CURRENT, m_settings.atr_period);
      if(m_atr_handle == INVALID_HANDLE)
      {
         Print("ATRStop: failed to create ATR handle");
         return false;
      }
      Draw();
      return true;
   }

   void Deinit()
   {
      ObjectsDeleteAll(0, ATRSTOP_OBJ_PREFIX);
      if(m_atr_handle != INVALID_HANDLE)
         IndicatorRelease(m_atr_handle);
   }

   void Update()
   {
      static datetime last_bar = 0;
      datetime t[];
      ArraySetAsSeries(t, true);
      if(CopyTime(m_symbol, PERIOD_CURRENT, 0, 1, t) != 1) return;
      if(t[0] == last_bar) return;
      last_bar = t[0];

      ObjectsDeleteAll(0, ATRSTOP_OBJ_PREFIX);
      Draw();
   }

private:
   void Draw()
   {
      int bars   = m_settings.lookback_bars;
      int needed = bars + m_settings.atr_period + 2;

      double   atr[], hi[], lo[];
      datetime tm[];
      ArraySetAsSeries(atr, true);
      ArraySetAsSeries(hi,  true);
      ArraySetAsSeries(lo,  true);
      ArraySetAsSeries(tm,  true);

      if(CopyBuffer(m_atr_handle, 0, 0, needed, atr) < needed) return;
      if(CopyHigh(m_symbol, PERIOD_CURRENT, 0, bars, hi)  < bars) return;
      if(CopyLow (m_symbol, PERIOD_CURRENT, 0, bars, lo)  < bars) return;
      if(CopyTime(m_symbol, PERIOD_CURRENT, 0, bars, tm)  < bars) return;

      int period_sec = PeriodSeconds(PERIOD_CURRENT);

      for(int i = bars - 1; i >= 0; i--)
      {
         double long_stop  = lo[i] - atr[i] * m_settings.atr_multiplier;
         double short_stop = hi[i] + atr[i] * m_settings.atr_multiplier;

         datetime t_left  = tm[i];
         datetime t_right = tm[i] + (datetime)period_sec;

         DrawSegment("L_" + IntegerToString(i), t_left, t_right, long_stop,  m_settings.long_colour);
         DrawSegment("S_" + IntegerToString(i), t_left, t_right, short_stop, m_settings.short_colour);
      }

      ChartRedraw(0);
   }

   void DrawSegment(string id, datetime t1, datetime t2, double price, color c)
   {
      string name = ATRSTOP_OBJ_PREFIX + id;
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR,      c);
      ObjectSetInteger(0, name, OBJPROP_WIDTH,      2);
      ObjectSetInteger(0, name, OBJPROP_STYLE,      STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_RAY_LEFT,   false);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT,  false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   }
};

#endif
