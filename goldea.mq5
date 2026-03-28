//+------------------------------------------------------------------+
//|  goldea.mq5                                                       |
//+------------------------------------------------------------------+
#property copyright   "Goldea"
#property version     "1.00"
#property description "Modular EA"

#include "modules/FVG.mqh"
#include "modules/IFVG.mqh"

input group  "═══  FAIR VALUE GAP  ═══"
input bool   FVG_Enable                  = true;      // FVG - Enable Module
input int    FVG_History_CandlesBack     = 100;        // FVG - History - Candles Back
input color  FVG_Display_BullishColour   = clrLime;   // FVG - Display - Bullish Colour
input color  FVG_Display_BearishColour   = clrRed;    // FVG - Display - Bearish Colour

input group  "═══  INVERTED FVG  ═══"
input bool   IFVG_Enable                 = true;      // IFVG - Enable Module
input color  IFVG_Display_Colour         = clrYellow; // IFVG - Display - Colour
input int    IFVG_Display_Count          = 3;          // IFVG - Display - Show Last N
input bool   IFVG_Invalidate_On_Break    = true;       // IFVG - Invalidate on price break

CFVGModule  *g_fvg  = NULL;
CIFVGModule *g_ifvg = NULL;

int OnInit()
{
   if(FVG_Enable)
   {
      FVGSettings fs;
      fs.history_candles = FVG_History_CandlesBack;
      fs.bullish_colour  = FVG_Display_BullishColour;
      fs.bearish_colour  = FVG_Display_BearishColour;
      g_fvg = new CFVGModule(fs);
      g_fvg.Init();
   }

   if(IFVG_Enable)
   {
      IFVGSettings is;
      is.history_candles = FVG_History_CandlesBack;
      is.colour          = IFVG_Display_Colour;
      is.count           = IFVG_Display_Count;
      is.invalidate      = IFVG_Invalidate_On_Break;
      g_ifvg = new CIFVGModule(is);
      g_ifvg.Init();
   }

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_fvg  != NULL) { g_fvg.Deinit();  delete g_fvg;  g_fvg  = NULL; }
   if(g_ifvg != NULL) { g_ifvg.Deinit(); delete g_ifvg; g_ifvg = NULL; }
}

void OnTick()
{
   if(g_fvg  != NULL) g_fvg.Update();
   if(g_ifvg != NULL) g_ifvg.Update();
}
