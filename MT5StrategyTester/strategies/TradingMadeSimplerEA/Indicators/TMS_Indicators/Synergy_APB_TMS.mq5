//+------------------------------------------------------------------+
//|                                                 Synergy_APB_TMS.mq5|
//|                        Synergy APB for Trading Made Simple         |
//|                        Average Price Bar Indicator                 |
//+------------------------------------------------------------------+
#property copyright "TMS Strategy"
#property link      "https://www.forexfactory.com/thread/917569"
#property version   "1.00"
#property description "Synergy Average Price Bar Indicator"
#property description "Blue = Bullish, Red = Bearish"

#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots   4

// Bullish candles
#property indicator_label1  "Bull Shadow"
#property indicator_type1   DRAW_HISTOGRAM
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

#property indicator_label2  "Bull Body"
#property indicator_type2   DRAW_HISTOGRAM
#property indicator_color2  clrDodgerBlue
#property indicator_style2  STYLE_SOLID
#property indicator_width2  3

// Bearish candles
#property indicator_label3  "Bear Shadow"
#property indicator_type3   DRAW_HISTOGRAM
#property indicator_color3  clrRed
#property indicator_style3  STYLE_SOLID
#property indicator_width3  1

#property indicator_label4  "Bear Body"
#property indicator_type4   DRAW_HISTOGRAM
#property indicator_color4  clrMaroon
#property indicator_style4  STYLE_SOLID
#property indicator_width4  3

//--- Input parameters
input color InpBullColor1 = clrDodgerBlue;  // Bull Shadow Color
input color InpBullColor2 = clrBlue;        // Bull Body Color
input color InpBearColor1 = clrRed;         // Bear Shadow Color
input color InpBearColor2 = clrMaroon;      // Bear Body Color

//--- Indicator buffers
double BullShadowHigh[];
double BullShadowLow[];
double BullBodyOpen[];
double BullBodyClose[];
double BearShadowHigh[];
double BearShadowLow[];
double BearBodyOpen[];
double BearBodyClose[];

// APB calculation buffers
double APB_Open[];
double APB_High[];
double APB_Low[];
double APB_Close[];

//+------------------------------------------------------------------+
//| Custom indicator initialization function                          |
//+------------------------------------------------------------------+
int OnInit()
{
   // Set indicator buffers
   SetIndexBuffer(0, BullShadowHigh, INDICATOR_DATA);
   SetIndexBuffer(1, BullShadowLow, INDICATOR_DATA);
   SetIndexBuffer(2, BullBodyOpen, INDICATOR_DATA);
   SetIndexBuffer(3, BullBodyClose, INDICATOR_DATA);
   SetIndexBuffer(4, BearShadowHigh, INDICATOR_DATA);
   SetIndexBuffer(5, BearShadowLow, INDICATOR_DATA);
   SetIndexBuffer(6, BearBodyOpen, INDICATOR_DATA);
   SetIndexBuffer(7, BearBodyClose, INDICATOR_DATA);
   
   // Set as series
   ArraySetAsSeries(BullShadowHigh, true);
   ArraySetAsSeries(BullShadowLow, true);
   ArraySetAsSeries(BullBodyOpen, true);
   ArraySetAsSeries(BullBodyClose, true);
   ArraySetAsSeries(BearShadowHigh, true);
   ArraySetAsSeries(BearShadowLow, true);
   ArraySetAsSeries(BearBodyOpen, true);
   ArraySetAsSeries(BearBodyClose, true);
   
   // Configure plots for histogram display
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_HISTOGRAM2);
   PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_HISTOGRAM2);
   PlotIndexSetInteger(2, PLOT_DRAW_TYPE, DRAW_HISTOGRAM2);
   PlotIndexSetInteger(3, PLOT_DRAW_TYPE, DRAW_HISTOGRAM2);
   
   // Set colors
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpBullColor1);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, InpBullColor2);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, InpBearColor1);
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, InpBearColor2);
   
   // Set empty value
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   
   // Set indicator name
   IndicatorSetString(INDICATOR_SHORTNAME, "Synergy APB");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                               |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < 10)
      return 0;
   
   // Set arrays as series
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   
   // Resize APB buffers
   ArrayResize(APB_Open, rates_total);
   ArrayResize(APB_High, rates_total);
   ArrayResize(APB_Low, rates_total);
   ArrayResize(APB_Close, rates_total);
   ArraySetAsSeries(APB_Open, true);
   ArraySetAsSeries(APB_High, true);
   ArraySetAsSeries(APB_Low, true);
   ArraySetAsSeries(APB_Close, true);
   
   // Calculate limit
   int limit = prev_calculated == 0 ? rates_total - 2 : rates_total - prev_calculated + 1;
   
   // Calculate from oldest to newest
   for(int i = limit; i >= 0; i--)
   {
      // Calculate APB (Average Price Bar) - similar to Heiken Ashi but with EMA smoothing
      if(i == rates_total - 2)
      {
         APB_Open[i] = (open[i + 1] + close[i + 1]) / 2.0;
         APB_Close[i] = (open[i] + high[i] + low[i] + close[i]) / 4.0;
      }
      else
      {
         APB_Open[i] = (APB_Open[i + 1] + APB_Close[i + 1]) / 2.0;
         APB_Close[i] = (open[i] + high[i] + low[i] + close[i]) / 4.0;
      }
      
      APB_High[i] = MathMax(high[i], MathMax(APB_Open[i], APB_Close[i]));
      APB_Low[i] = MathMin(low[i], MathMin(APB_Open[i], APB_Close[i]));
      
      // Initialize all to empty
      BullShadowHigh[i] = EMPTY_VALUE;
      BullShadowLow[i] = EMPTY_VALUE;
      BullBodyOpen[i] = EMPTY_VALUE;
      BullBodyClose[i] = EMPTY_VALUE;
      BearShadowHigh[i] = EMPTY_VALUE;
      BearShadowLow[i] = EMPTY_VALUE;
      BearBodyOpen[i] = EMPTY_VALUE;
      BearBodyClose[i] = EMPTY_VALUE;
      
      // Determine if bullish or bearish
      if(APB_Close[i] > APB_Open[i]) // Bullish
      {
         BullShadowHigh[i] = APB_High[i];
         BullShadowLow[i] = APB_Low[i];
         BullBodyOpen[i] = APB_Open[i];
         BullBodyClose[i] = APB_Close[i];
      }
      else // Bearish
      {
         BearShadowHigh[i] = APB_High[i];
         BearShadowLow[i] = APB_Low[i];
         BearBodyOpen[i] = APB_Open[i];
         BearBodyClose[i] = APB_Close[i];
      }
   }
   
   return rates_total;
}

//+------------------------------------------------------------------+
//| Get APB direction                                                 |
//+------------------------------------------------------------------+
int GetAPBDirection(int bar)
{
   if(bar >= ArraySize(APB_Open) || bar >= ArraySize(APB_Close))
      return 0;
   
   if(APB_Close[bar] > APB_Open[bar])
      return 1;  // Bullish
   else if(APB_Close[bar] < APB_Open[bar])
      return -1; // Bearish
   
   return 0;
}

//+------------------------------------------------------------------+
