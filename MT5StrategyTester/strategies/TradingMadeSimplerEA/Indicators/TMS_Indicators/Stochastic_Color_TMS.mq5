//+------------------------------------------------------------------+
//|                                          Stochastic_Color_TMS.mq5 |
//|                        Color Stochastic for Trading Made Simple    |
//|                        MT5 Implementation                          |
//+------------------------------------------------------------------+
#property copyright "TMS Strategy"
#property link      "https://www.forexfactory.com/thread/917569"
#property version   "1.00"
#property description "Color Stochastic Indicator"
#property description "Colors change based on overbought/oversold levels"

#property indicator_separate_window
#property indicator_buffers 6
#property indicator_plots   4

#property indicator_minimum 0
#property indicator_maximum 100

// Main line (changes color)
#property indicator_label1  "Stochastic"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrSlateGray
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

// Signal line
#property indicator_label2  "Signal"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrDimGray
#property indicator_style2  STYLE_DOT
#property indicator_width2  1

// Overbought
#property indicator_label3  "Overbought"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrLime
#property indicator_style3  STYLE_SOLID
#property indicator_width3  2

// Oversold
#property indicator_label4  "Oversold"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrGold
#property indicator_style4  STYLE_SOLID
#property indicator_width4  2

// Level lines
#property indicator_level1  80
#property indicator_level2  50
#property indicator_level3  20
#property indicator_levelcolor clrDarkSlateGray
#property indicator_levelstyle STYLE_DOT

//--- Input parameters
input int                 InpKPeriod     = 14;           // K Period
input int                 InpDPeriod     = 3;            // D Period
input int                 InpSlowing     = 3;            // Slowing
input ENUM_MA_METHOD      InpMAMethod    = MODE_SMA;     // MA Method
input ENUM_STO_PRICE      InpPriceField  = STO_LOWHIGH;  // Price Field
input int                 InpOverbought  = 80;           // Overbought Level
input int                 InpOversold    = 20;           // Oversold Level
input color               InpMainColor   = clrSlateGray; // Main Line Color
input color               InpSignalColor = clrDimGray;   // Signal Line Color
input color               InpUpColor     = clrLime;      // Above 50 Color
input color               InpDownColor   = clrGold;      // Below 50 Color
input bool                InpAlerts      = false;        // Enable Alerts

//--- Indicator buffers
double KFull[];
double DFull[];
double Upper[];
double Lower[];
double ColorUp[];
double ColorDown[];

//+------------------------------------------------------------------+
//| Custom indicator initialization function                          |
//+------------------------------------------------------------------+
int OnInit()
{
   // Set index buffers
   SetIndexBuffer(0, KFull, INDICATOR_DATA);
   SetIndexBuffer(1, DFull, INDICATOR_DATA);
   SetIndexBuffer(2, Upper, INDICATOR_DATA);
   SetIndexBuffer(3, Lower, INDICATOR_DATA);
   SetIndexBuffer(4, ColorUp, INDICATOR_CALCULATIONS);
   SetIndexBuffer(5, ColorDown, INDICATOR_CALCULATIONS);
   
   // Set as series
   ArraySetAsSeries(KFull, true);
   ArraySetAsSeries(DFull, true);
   ArraySetAsSeries(Upper, true);
   ArraySetAsSeries(Lower, true);
   ArraySetAsSeries(ColorUp, true);
   ArraySetAsSeries(ColorDown, true);
   
   // Set colors
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpMainColor);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, InpSignalColor);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, InpUpColor);
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, InpDownColor);
   
   // Set empty values
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   
   // Set indicator name
   string shortName = "Stoch(" + IntegerToString(InpKPeriod) + "," + 
                      IntegerToString(InpDPeriod) + "," + 
                      IntegerToString(InpSlowing) + ")";
   IndicatorSetString(INDICATOR_SHORTNAME, shortName);
   
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
   if(rates_total < InpKPeriod + InpSlowing + InpDPeriod)
      return 0;
   
   // Set arrays as series
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   
   int limit = prev_calculated == 0 ? rates_total - InpKPeriod - InpSlowing - 1 : rates_total - prev_calculated + 1;
   
   // Calculate Raw Stochastic %K
   double rawK[];
   ArrayResize(rawK, rates_total);
   ArraySetAsSeries(rawK, true);
   
   for(int i = limit; i >= 0; i--)
   {
      double highestHigh = high[i];
      double lowestLow = low[i];
      
      for(int j = 0; j < InpKPeriod; j++)
      {
         if(i + j >= rates_total) break;
         
         if(high[i + j] > highestHigh) highestHigh = high[i + j];
         if(low[i + j] < lowestLow) lowestLow = low[i + j];
      }
      
      double range = highestHigh - lowestLow;
      if(range > 0)
         rawK[i] = 100.0 * (close[i] - lowestLow) / range;
      else
         rawK[i] = 50.0;
   }
   
   // Calculate %K with slowing (SMA of rawK)
   for(int i = limit; i >= 0; i--)
   {
      double sum = 0;
      int count = 0;
      
      for(int j = 0; j < InpSlowing; j++)
      {
         if(i + j >= rates_total) break;
         sum += rawK[i + j];
         count++;
      }
      
      KFull[i] = count > 0 ? sum / count : rawK[i];
   }
   
   // Calculate %D (SMA of %K)
   for(int i = limit; i >= 0; i--)
   {
      double sum = 0;
      int count = 0;
      
      for(int j = 0; j < InpDPeriod; j++)
      {
         if(i + j >= rates_total) break;
         sum += KFull[i + j];
         count++;
      }
      
      DFull[i] = count > 0 ? sum / count : KFull[i];
   }
   
   // Set colors based on levels
   for(int i = limit; i >= 0; i--)
   {
      Upper[i] = EMPTY_VALUE;
      Lower[i] = EMPTY_VALUE;
      
      if(KFull[i] > InpOverbought)
      {
         Upper[i] = KFull[i];
         if(i < rates_total - 1 && KFull[i + 1] <= InpOverbought)
            Upper[i + 1] = KFull[i + 1];
      }
      else if(KFull[i] < InpOversold)
      {
         Lower[i] = KFull[i];
         if(i < rates_total - 1 && KFull[i + 1] >= InpOversold)
            Lower[i + 1] = KFull[i + 1];
      }
   }
   
   // Check for alerts
   if(InpAlerts && prev_calculated > 0)
   {
      // Overbought reversal
      if(KFull[0] < InpOverbought && KFull[1] > InpOverbought)
      {
         Alert(_Symbol + " Stochastic: Overbought Reversal (Sell Signal)");
      }
      // Oversold reversal
      if(KFull[0] > InpOversold && KFull[1] < InpOversold)
      {
         Alert(_Symbol + " Stochastic: Oversold Reversal (Buy Signal)");
      }
      // Cross above 50
      if(KFull[0] > 50 && KFull[1] <= 50)
      {
         Alert(_Symbol + " Stochastic: Crossed above 50");
      }
      // Cross below 50
      if(KFull[0] < 50 && KFull[1] >= 50)
      {
         Alert(_Symbol + " Stochastic: Crossed below 50");
      }
   }
   
   return rates_total;
}

//+------------------------------------------------------------------+
