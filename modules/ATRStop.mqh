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

      Draw();
   }

private:
   void Draw()
   {
      double atr[];
      double hi[], lo[];
      ArraySetAsSeries(atr, true);
      ArraySetAsSeries(hi,  true);
      ArraySetAsSeries(lo,  true);

      if(CopyBuffer(m_atr_handle, 0, 1, 1, atr) < 1) return;
      if(CopyHigh(m_symbol, PERIOD_CURRENT, 1, 1, hi) < 1) return;
      if(CopyLow (m_symbol, PERIOD_CURRENT, 1, 1, lo) < 1) return;

      double stop_dist = atr[0] * m_settings.atr_multiplier;
      double long_stop  = lo[0]  - stop_dist;
      double short_stop = hi[0]  + stop_dist;

      DrawLine("LONG",  long_stop,  m_settings.long_colour);
      DrawLine("SHORT", short_stop, m_settings.short_colour);
   }

   void DrawLine(string id, double price, color c)
   {
      string name = ATRSTOP_OBJ_PREFIX + id;
      if(ObjectFind(0, name) < 0)
      {
         ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
         ObjectSetInteger(0, name, OBJPROP_WIDTH,      1);
         ObjectSetInteger(0, name, OBJPROP_STYLE,      STYLE_DASH);
      }
      ObjectSetDouble (0, name, OBJPROP_PRICE, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   }
};

#endif
