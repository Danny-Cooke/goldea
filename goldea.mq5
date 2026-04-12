//+------------------------------------------------------------------+
//|  goldea.mq5                                                       |
//+------------------------------------------------------------------+
#property copyright   "Goldea"
#property version     "1.00"
#property description "Modular EA"

#include "modules/FVG.mqh"
#include "modules/ATRStop.mqh"
#include "modules/TrendFilter.mqh"
#include "modules/IFVG.mqh"

input group  "═══  FAIR VALUE GAP  ═══"
input bool   FVG_Enable                  = true;      // FVG - Enable Module
input int    FVG_History_CandlesBack     = 100;       // FVG - History - Candles Back
input color  FVG_Display_BullishColour   = clrLime;   // FVG - Bullish FVG Colour
input color  FVG_Display_BearishColour   = clrRed;    // FVG - Bearish FVG Colour
input color  FVG_Display_MitigatedColour = clrYellow; // FVG - Mitigated FVG Colour

input group  "═══  IFVG STRATEGY  ═══"
input bool   IFVG_Enable                = true;          // IFVG - Enable Module
input int    IFVG_History_CandlesBack   = 100;           // IFVG - History - Candles Back
input color  IFVG_Zone_Colour           = clrMagenta;    // IFVG - Zone Colour
input int    IFVG_Zone_Count            = 3;             // IFVG - Zones to Display
input bool   IFVG_Invalidate            = false;         // IFVG - Remove Broken Zones
input double IFVG_TP_Multiplier         = 2.0;           // IFVG - TP Risk Multiplier (e.g. 2 = 2R)
input int    IFVG_SL_LookbackBars       = 20;            // IFVG - SL Swing Lookback (bars)
input double IFVG_SL_BufferPoints       = 50.0;          // IFVG - SL Buffer (points)
input color  IFVG_Long_Colour           = clrDodgerBlue; // IFVG - Long Setup Colour
input color  IFVG_Short_Colour          = clrOrangeRed;  // IFVG - Short Setup Colour
input double              IFVG_LotSize        = 0.01;         // IFVG - Lot Size
input int                 IFVG_Magic          = 42001;        // IFVG - Magic Number
input ENUM_IFVG_SL_MODE   IFVG_SL_Mode        = IFVG_SL_ATR; // IFVG - SL Mode
input int                 IFVG_ATR_Period      = 14;           // IFVG - ATR Period (ATR mode)
input double              IFVG_ATR_Multiplier  = 1.5;          // IFVG - ATR Multiplier (ATR mode)

input group  "═══  TREND FILTER  ═══"
input bool              TF_Enable       = true;           // Trend Filter - Enable
input ENUM_TIMEFRAMES   TF_Timeframe1   = PERIOD_M15;     // Trend Filter - Timeframe 1
input ENUM_TIMEFRAMES   TF_Timeframe2   = PERIOD_H1;      // Trend Filter - Timeframe 2
input ENUM_TIMEFRAMES   TF_Timeframe3   = PERIOD_H4;      // Trend Filter - Timeframe 3
input int               TF_EMA_Period   = 50;             // Trend Filter - EMA Period
input int               TF_MinScore     = 2;              // Trend Filter - Min Score to Trade (1-3)

input group  "═══  ATR STOP LOSS  ═══"
input bool   ATR_Enable                  = true;      // ATR - Enable Module
input int    ATR_Period                  = 14;        // ATR - Period
input double ATR_Multiplier              = 1.5;       // ATR - Multiplier
input int    ATR_LookbackBars            = 100;       // ATR - Bars to Display
input color  ATR_LongColour              = clrAqua;   // ATR - Long Stop Colour
input color  ATR_ShortColour             = clrOrange; // ATR - Short Stop Colour

CFVGModule          *g_fvg    = NULL;
CATRStopModule      *g_atr    = NULL;
CTrendFilterModule  *g_trend  = NULL;
CIFVGModule         *g_ifvg   = NULL;

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

   if(TF_Enable)
   {
      TrendFilterSettings ts;
      ts.tf1        = TF_Timeframe1;
      ts.tf2        = TF_Timeframe2;
      ts.tf3        = TF_Timeframe3;
      ts.ema_period = TF_EMA_Period;
      ts.min_score  = TF_MinScore;
      g_trend = new CTrendFilterModule(ts);
      if(!g_trend.Init()) { delete g_trend; g_trend = NULL; }
   }

   if(IFVG_Enable)
   {
      IFVGSettings is;
      is.history_candles = IFVG_History_CandlesBack;
      is.colour          = IFVG_Zone_Colour;
      is.count           = IFVG_Zone_Count;
      is.invalidate      = IFVG_Invalidate;
      is.tp_multiplier   = IFVG_TP_Multiplier;
      is.sl_lookback     = IFVG_SL_LookbackBars;
      is.sl_buffer_pts   = IFVG_SL_BufferPoints;
      is.long_colour     = IFVG_Long_Colour;
      is.short_colour    = IFVG_Short_Colour;
      is.lot_size        = IFVG_LotSize;
      is.magic           = IFVG_Magic;
      is.sl_mode         = IFVG_SL_Mode;
      is.atr_period      = IFVG_ATR_Period;
      is.atr_multiplier  = IFVG_ATR_Multiplier;
      g_ifvg = new CIFVGModule(is);
      if(g_trend != NULL)
         g_ifvg.SetTrendFilter(g_trend);
      g_ifvg.Init();
   }

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_fvg   != NULL) { g_fvg.Deinit();   delete g_fvg;   g_fvg   = NULL; }
   if(g_atr   != NULL) { g_atr.Deinit();   delete g_atr;   g_atr   = NULL; }
   if(g_trend != NULL) { g_trend.Deinit(); delete g_trend; g_trend = NULL; }
   if(g_ifvg  != NULL) { g_ifvg.Deinit();  delete g_ifvg;  g_ifvg  = NULL; }
}

void OnTick()
{
   if(g_fvg   != NULL) g_fvg.Update();
   if(g_atr   != NULL) g_atr.Update();
   if(g_trend != NULL) g_trend.Update();
   if(g_ifvg  != NULL) g_ifvg.Update();
}
