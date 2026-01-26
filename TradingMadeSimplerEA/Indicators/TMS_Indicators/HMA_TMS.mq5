//+------------------------------------------------------------------+
//|                                                      HMA_TMS.mq5 |
//|                        Hull Moving Average for Trading Made Simple|
//|                        MT5 Implementation                         |
//+------------------------------------------------------------------+
#property copyright "TMS Strategy"
#property link      "https://www.forexfactory.com/thread/917569"
#property version   "1.00"
#property description "Hull Moving Average with Trend Colors"
#property description "Lime Green = Uptrend, Deep Pink = Downtrend"

#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   2

// Plot 0 - Uptrend (Lime)
#property indicator_label1  "HMA Up"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrLime
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

// Plot 1 - Downtrend (Deep Pink)
#property indicator_label2  "HMA Down"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrDeepPink
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

//--- Input parameters
input int                InpPeriod    = 12;           // HMA Period
input ENUM_MA_METHOD     InpMethod    = MODE_LWMA;    // MA Method
input ENUM_APPLIED_PRICE InpPrice     = PRICE_CLOSE;  // Applied Price
input bool               InpAlerts    = false;        // Enable Alerts
input string             InpSoundFile = "alert2.wav"; // Alert Sound

//--- Indicator buffers
double BufferUp[];
double BufferDown[];
double BufferMain[];
double BufferTrend[];

//--- Global variables
int handleWMA1;
int handleWMA2;
int sqrtPeriod;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                          |
//+------------------------------------------------------------------+
int OnInit()
{
   // Calculate sqrt of period
   sqrtPeriod = (int)MathSqrt(InpPeriod);
   if(sqrtPeriod < 1) sqrtPeriod = 1;
   
   // Set indicator buffers
   SetIndexBuffer(0, BufferUp, INDICATOR_DATA);
   SetIndexBuffer(1, BufferDown, INDICATOR_DATA);
   SetIndexBuffer(2, BufferMain, INDICATOR_CALCULATIONS);
   SetIndexBuffer(3, BufferTrend, INDICATOR_CALCULATIONS);
   
   // Set as series
   ArraySetAsSeries(BufferUp, true);
   ArraySetAsSeries(BufferDown, true);
   ArraySetAsSeries(BufferMain, true);
   ArraySetAsSeries(BufferTrend, true);
   
   // Create WMA handles
   handleWMA1 = iMA(_Symbol, PERIOD_CURRENT, InpPeriod / 2, 0, InpMethod, InpPrice);
   handleWMA2 = iMA(_Symbol, PERIOD_CURRENT, InpPeriod, 0, InpMethod, InpPrice);
   
   if(handleWMA1 == INVALID_HANDLE || handleWMA2 == INVALID_HANDLE)
   {
      Print("Failed to create WMA indicators");
      return INIT_FAILED;
   }
   
   // Set indicator name
   string shortName = "HMA(" + IntegerToString(InpPeriod) + ")";
   IndicatorSetString(INDICATOR_SHORTNAME, shortName);
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   
   // Set empty value
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleWMA1 != INVALID_HANDLE) IndicatorRelease(handleWMA1);
   if(handleWMA2 != INVALID_HANDLE) IndicatorRelease(handleWMA2);
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
   if(rates_total < InpPeriod + sqrtPeriod + 10)
      return 0;
   
   // Set arrays as series
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(close, true);
   
   // Get WMA values
   double wma1[], wma2[];
   ArraySetAsSeries(wma1, true);
   ArraySetAsSeries(wma2, true);
   
   int toCopy = rates_total - prev_calculated + 10;
   if(toCopy > rates_total) toCopy = rates_total;
   
   if(CopyBuffer(handleWMA1, 0, 0, toCopy, wma1) < toCopy)
      return 0;
   if(CopyBuffer(handleWMA2, 0, 0, toCopy, wma2) < toCopy)
      return 0;
   
   // Calculate raw HMA values
   double rawHMA[];
   ArrayResize(rawHMA, toCopy);
   ArraySetAsSeries(rawHMA, true);
   
   for(int i = 0; i < toCopy; i++)
   {
      rawHMA[i] = 2.0 * wma1[i] - wma2[i];
   }
   
   // Calculate final HMA (WMA of rawHMA)
   int limit = prev_calculated == 0 ? toCopy - sqrtPeriod - 1 : toCopy - 1;
   
   for(int i = limit; i >= 0; i--)
   {
      // Calculate WMA of rawHMA
      double sum = 0;
      double weightSum = 0;
      
      for(int j = 0; j < sqrtPeriod; j++)
      {
         if(i + j >= toCopy) break;
         
         double weight = sqrtPeriod - j;
         sum += rawHMA[i + j] * weight;
         weightSum += weight;
      }
      
      if(weightSum > 0)
         BufferMain[i] = sum / weightSum;
      else
         BufferMain[i] = rawHMA[i];
   }
   
   // Determine trend and set colors
   static int prevTrend = 0;
   
   for(int i = limit; i >= 0; i--)
   {
      BufferUp[i] = EMPTY_VALUE;
      BufferDown[i] = EMPTY_VALUE;
      
      // Determine trend
      int trend = 0;
      if(i < toCopy - 1)
      {
         if(BufferMain[i] > BufferMain[i + 1])
            trend = 1;  // Uptrend
         else if(BufferMain[i] < BufferMain[i + 1])
            trend = -1; // Downtrend
         else
            trend = (int)BufferTrend[i + 1]; // Carry previous trend
      }
      
      BufferTrend[i] = trend;
      
      // Set line color
      if(trend > 0)
      {
         BufferUp[i] = BufferMain[i];
         if(i < toCopy - 1 && BufferTrend[i + 1] <= 0)
            BufferUp[i + 1] = BufferMain[i + 1]; // Connect lines
      }
      else if(trend < 0)
      {
         BufferDown[i] = BufferMain[i];
         if(i < toCopy - 1 && BufferTrend[i + 1] >= 0)
            BufferDown[i + 1] = BufferMain[i + 1]; // Connect lines
      }
      
      // Check for alerts on bar 0
      if(i == 0 && InpAlerts && prev_calculated > 0)
      {
         if(trend != prevTrend && prevTrend != 0)
         {
            string message = _Symbol + " HMA Trend Change: " + (trend > 0 ? "BULLISH" : "BEARISH");
            Alert(message);
            if(InpSoundFile != "")
               PlaySound(InpSoundFile);
         }
         prevTrend = trend;
      }
   }
   
   return rates_total;
}

//+------------------------------------------------------------------+
