//+------------------------------------------------------------------+
//|  goldea.mq5                                                       |
//+------------------------------------------------------------------+
#property copyright   "Goldea"
#property version     "1.00"
#property description "Modular EA"

#include "modules/FVG.mqh"
#include "modules/ATRStop.mqh"

input group  "═══  FAIR VALUE GAP  ═══"
input bool   FVG_Enable                  = true;      // FVG - Enable Module
input int    FVG_History_CandlesBack     = 100;       // FVG - History - Candles Back
input color  FVG_Display_BullishColour   = clrLime;   // FVG - Bullish FVG Colour
input color  FVG_Display_BearishColour   = clrRed;    // FVG - Bearish FVG Colour
input color  FVG_Display_MitigatedColour = clrYellow; // FVG - Mitigated FVG Colour

input group  "═══  ATR STOP LOSS  ═══"
input bool   ATR_Enable                  = true;      // ATR - Enable Module
input int    ATR_Period                  = 14;        // ATR - Period
input double ATR_Multiplier              = 1.5;       // ATR - Multiplier
input int    ATR_LookbackBars            = 100;       // ATR - Bars to Display
input color  ATR_LongColour              = clrAqua;   // ATR - Long Stop Colour
input color  ATR_ShortColour             = clrOrange; // ATR - Short Stop Colour

CFVGModule    *g_fvg  = NULL;
CATRStopModule *g_atr = NULL;

int OnInit()
{
   if(FVG_Enable)
   {
      FVGSettings fs;
      fs.history_candles  = FVG_History_CandlesBack;
      fs.bullish_colour   = FVG_Display_BullishColour;
      fs.bearish_colour   = FVG_Display_BearishColour;
      fs.mitigated_colour = FVG_Display_MitigatedColour;
      g_fvg = new CFVGModule(fs);
      g_fvg.Init();
   }

   if(ATR_Enable)
   {
      ATRStopSettings as;
      as.atr_period     = ATR_Period;
      as.atr_multiplier = ATR_Multiplier;
      as.lookback_bars  = ATR_LookbackBars;
      as.long_colour    = ATR_LongColour;
      as.short_colour   = ATR_ShortColour;
      g_atr = new CATRStopModule(as);
      if(!g_atr.Init()) { delete g_atr; g_atr = NULL; }
   }

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_fvg != NULL) { g_fvg.Deinit(); delete g_fvg; g_fvg = NULL; }
   if(g_atr != NULL) { g_atr.Deinit(); delete g_atr; g_atr = NULL; }
}

void OnTick()
{
   if(g_fvg != NULL) g_fvg.Update();
   if(g_atr != NULL) g_atr.Update();
}
