//+------------------------------------------------------------------+
//|                                               Heiken_Ashi_TMS.mq5 |
//|                        Heiken Ashi for Trading Made Simple         |
//|                        MT5 Implementation                          |
//+------------------------------------------------------------------+
#property copyright "TMS Strategy"
#property link      "https://www.forexfactory.com/thread/917569"
#property version   "1.00"
#property description "Heiken Ashi Candles"
#property description "Blue = Bullish, Maroon = Bearish"

#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   2

// High-Low (shadow/wick)
#property indicator_label1  "HA Low/High"
#property indicator_type1   DRAW_HISTOGRAM2
#property indicator_color1  clrMaroon
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

#property indicator_label2  "HA High/Low"
#property indicator_type2   DRAW_HISTOGRAM2
#property indicator_color2  clrBlue
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

//--- Input parameters
input color InpBullShadow = clrBlue;    // Bullish Shadow Color
input color InpBullBody   = clrBlue;    // Bullish Body Color
input color InpBearShadow = clrMaroon;  // Bearish Shadow Color
input color InpBearBody   = clrMaroon;  // Bearish Body Color

//--- Indicator buffers
double ExtLowHighBuffer[];
double ExtHighLowBuffer[];
double ExtOpenBuffer[];
double ExtCloseBuffer[];

//+------------------------------------------------------------------+
//| Custom indicator initialization function                          |
//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "Heiken Ashi TMS");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   
   // Set index buffers
   SetIndexBuffer(0, ExtLowHighBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, ExtHighLowBuffer, INDICATOR_DATA);
   SetIndexBuffer(2, ExtOpenBuffer, INDICATOR_DATA);
   SetIndexBuffer(3, ExtCloseBuffer, INDICATOR_DATA);
   
   // Set as series
   ArraySetAsSeries(ExtLowHighBuffer, true);
   ArraySetAsSeries(ExtHighLowBuffer, true);
   ArraySetAsSeries(ExtOpenBuffer, true);
   ArraySetAsSeries(ExtCloseBuffer, true);
   
   // Set plot draw types
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_HISTOGRAM2);
   PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_HISTOGRAM2);
   
   // Set line widths for body effect
   PlotIndexSetInteger(0, PLOT_LINE_WIDTH, 1);
   PlotIndexSetInteger(1, PLOT_LINE_WIDTH, 3);
   
   // Set colors
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 0, InpBearShadow);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 1, InpBearBody);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, 0, InpBullShadow);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, 1, InpBullBody);
   
   // Set labels
   PlotIndexSetString(0, PLOT_LABEL, "HA Open;HA High");
   PlotIndexSetString(1, PLOT_LABEL, "HA Close;HA Low");
   
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
   if(rates_total <= 10)
      return 0;
   
   // Set arrays as series (not series - calculate from old to new)
   ArraySetAsSeries(open, false);
   ArraySetAsSeries(high, false);
   ArraySetAsSeries(low, false);
   ArraySetAsSeries(close, false);
   ArraySetAsSeries(ExtLowHighBuffer, false);
   ArraySetAsSeries(ExtHighLowBuffer, false);
   ArraySetAsSeries(ExtOpenBuffer, false);
   ArraySetAsSeries(ExtCloseBuffer, false);
   
   // Calculate starting position
   int pos;
   if(prev_calculated > 1)
      pos = prev_calculated - 1;
   else
   {
      // First candle
      if(open[0] < close[0])
      {
         ExtLowHighBuffer[0] = low[0];
         ExtHighLowBuffer[0] = high[0];
      }
      else
      {
         ExtLowHighBuffer[0] = high[0];
         ExtHighLowBuffer[0] = low[0];
      }
      ExtOpenBuffer[0] = open[0];
      ExtCloseBuffer[0] = close[0];
      pos = 1;
   }
   
   // Main calculation loop
   for(int i = pos; i < rates_total; i++)
   {
      double haOpen = (ExtOpenBuffer[i - 1] + ExtCloseBuffer[i - 1]) / 2.0;
      double haClose = (open[i] + high[i] + low[i] + close[i]) / 4.0;
      double haHigh = MathMax(high[i], MathMax(haOpen, haClose));
      double haLow = MathMin(low[i], MathMin(haOpen, haClose));
      
      if(haOpen < haClose) // Bullish
      {
         ExtLowHighBuffer[i] = haLow;
         ExtHighLowBuffer[i] = haHigh;
      }
      else // Bearish
      {
         ExtLowHighBuffer[i] = haHigh;
         ExtHighLowBuffer[i] = haLow;
      }
      
      ExtOpenBuffer[i] = haOpen;
      ExtCloseBuffer[i] = haClose;
   }
   
   return rates_total;
}

//+------------------------------------------------------------------+
//| Get Heiken Ashi direction                                         |
//+------------------------------------------------------------------+
int GetHADirection(int bar)
{
   // Convert bar index (0 = current) to buffer index
   int bufferSize = ArraySize(ExtOpenBuffer);
   int idx = bufferSize - 1 - bar;
   
   if(idx < 0 || idx >= bufferSize)
      return 0;
   
   if(ExtCloseBuffer[idx] > ExtOpenBuffer[idx])
      return 1;  // Bullish
   else if(ExtCloseBuffer[idx] < ExtOpenBuffer[idx])
      return -1; // Bearish
   
   return 0;
}

//+------------------------------------------------------------------+
