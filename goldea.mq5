//+------------------------------------------------------------------+
//|  goldea.mq5                                                       |
//+------------------------------------------------------------------+
#property copyright   "Goldea"
#property version     "1.00"
#property description "Modular EA"

#include "modules/FVG.mqh"

input group  "═══  FAIR VALUE GAP  ═══"
input bool   FVG_Enable                  = true;      // FVG - Enable Module
input int    FVG_History_CandlesBack     = 100;       // FVG - History - Candles Back
input color  FVG_Display_BullishColour   = clrLime;   // FVG - Bullish FVG Colour
input color  FVG_Display_BearishColour   = clrRed;    // FVG - Bearish FVG Colour
input color  FVG_Display_MitigatedColour = clrYellow; // FVG - Mitigated FVG Colour

CFVGModule *g_fvg = NULL;

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

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_fvg != NULL) { g_fvg.Deinit(); delete g_fvg; g_fvg = NULL; }
}

void OnTick()
{
   if(g_fvg != NULL) g_fvg.Update();
}
