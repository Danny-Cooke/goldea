//+------------------------------------------------------------------+
//|  goldea.mq5  -  Goldea EA                                        |
//|  Modular Expert Advisor / Visual Indicator for XAUUSD            |
//+------------------------------------------------------------------+
#property copyright   "Goldea"
#property version     "1.00"
#property description "Modular EA – attach to chart to use as visual indicator"

#include "modules/FVG.mqh"

//====================================================================
//  FVG MODULE INPUTS
//====================================================================
input group  "═══════════  FAIR VALUE GAP MODULE  ═══════════"
input bool   FVG_Enable                  = true;         // FVG - Enable Module
input int    FVG_History_CandlesBack     = 50;           // FVG - History   - Candles Back
input color  FVG_Display_BullishColour   = clrLime;      // FVG - Display   - Bullish Colour
input color  FVG_Display_BearishColour   = clrRed;       // FVG - Display   - Bearish Colour
input int    FVG_Display_Opacity         = 60;           // FVG - Display   - Rectangle Opacity (0=solid, 100=invisible)
input double FVG_Filter_MinSizePips      = 5.0;          // FVG - Filter    - Minimum Size (pips)
input int    FVG_Range_LookbackCandles   = 10;           // FVG - Range     - Lookback Candles
input int    FVG_Range_ATRPeriod         = 14;           // FVG - Range     - ATR Period
input double FVG_Range_ATRMultiplier     = 1.5;          // FVG - Range     - ATR Multiplier (range tight if spread < X * ATR)
input double FVG_Breakout_ATRMultiplier  = 1.0;          // FVG - Breakout  - ATR Multiplier (impulse body > X * ATR)

//====================================================================
//  GLOBALS
//====================================================================
CFVGModule *g_fvg = NULL;

//====================================================================
int OnInit()
{
   if(FVG_Enable)
   {
      FVGSettings s;
      s.history_candles  = FVG_History_CandlesBack;
      s.bullish_colour   = FVG_Display_BullishColour;
      s.bearish_colour   = FVG_Display_BearishColour;
      s.opacity          = FVG_Display_Opacity;
      s.min_size_pips    = FVG_Filter_MinSizePips;
      s.range_lookback   = FVG_Range_LookbackCandles;
      s.range_atr_period = FVG_Range_ATRPeriod;
      s.range_atr_mult   = FVG_Range_ATRMultiplier;
      s.breakout_atr_mult= FVG_Breakout_ATRMultiplier;

      g_fvg = new CFVGModule(s);
      if(!g_fvg.Init())
      {
         Print("Goldea: FVG module failed to initialise.");
         return INIT_FAILED;
      }
   }

   return INIT_SUCCEEDED;
}

//====================================================================
void OnDeinit(const int reason)
{
   if(g_fvg != NULL)
   {
      g_fvg.Deinit();
      delete g_fvg;
      g_fvg = NULL;
   }
}

//====================================================================
void OnTick()
{
   if(g_fvg != NULL)
      g_fvg.Update();
}
