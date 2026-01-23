//+------------------------------------------------------------------+
//|                                              TDI_Indicator.mq5   |
//|                           Traders Dynamic Index (Dean Malone)    |
//|                             For use with TDI Bounce EA           |
//+------------------------------------------------------------------+
#property copyright "TDI Indicator"
#property link      ""
#property version   "1.00"
#property indicator_separate_window
#property indicator_buffers 6
#property indicator_plots   5
#property indicator_minimum 0
#property indicator_maximum 100

// Plot properties
#property indicator_label1  "TDI Green (Price)"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrLime
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

#property indicator_label2  "TDI Red (Signal)"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

#property indicator_label3  "TDI Yellow (Base)"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrYellow
#property indicator_style3  STYLE_SOLID
#property indicator_width3  2

#property indicator_label4  "Upper Band"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrDodgerBlue
#property indicator_style4  STYLE_DOT
#property indicator_width4  1

#property indicator_label5  "Lower Band"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrDodgerBlue
#property indicator_style5  STYLE_DOT
#property indicator_width5  1

// Levels
#property indicator_level1  32
#property indicator_level2  50
#property indicator_level3  68
#property indicator_levelcolor clrGray
#property indicator_levelstyle STYLE_DOT

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input group "=== TDI Settings ==="
input int      RSI_Period          = 13;          // RSI Period
input ENUM_APPLIED_PRICE RSI_Price = PRICE_CLOSE; // RSI Applied Price
input int      PriceLine_Period    = 2;           // Green Line (Price) Period
input ENUM_MA_METHOD PriceLine_MA  = MODE_SMA;    // Green Line MA Method
input int      SignalLine_Period   = 7;           // Red Line (Signal) Period
input ENUM_MA_METHOD SignalLine_MA = MODE_SMA;    // Red Line MA Method
input int      BaseLine_Period     = 34;          // Yellow Line (Base) Period
input ENUM_MA_METHOD BaseLine_MA   = MODE_SMA;    // Yellow Line MA Method
input int      Volatility_Band     = 34;          // Volatility Band Period
input double   StdDev_Multiplier   = 1.618;       // Std Deviation Multiplier

input group "=== Alert Settings ==="
input bool     EnableCrossAlerts   = true;        // Enable Cross Alerts
input bool     EnableSoundAlerts   = true;        // Enable Sound Alerts
input bool     EnablePushAlerts    = false;       // Enable Push Notifications

//+------------------------------------------------------------------+
//| Indicator Buffers                                                 |
//+------------------------------------------------------------------+
double GreenLineBuffer[];     // Price Line (SMA of RSI)
double RedLineBuffer[];       // Signal Line (SMA of Green)
double YellowLineBuffer[];    // Market Base Line (SMA of RSI)
double UpperBandBuffer[];     // Upper Volatility Band
double LowerBandBuffer[];     // Lower Volatility Band
double RSIBuffer[];           // Helper buffer for RSI

// Indicator handle
int hRSI;

// Alert tracking
datetime lastAlertTime = 0;

//+------------------------------------------------------------------+
//| Custom Indicator Initialization Function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   // Set up indicator buffers
   SetIndexBuffer(0, GreenLineBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, RedLineBuffer, INDICATOR_DATA);
   SetIndexBuffer(2, YellowLineBuffer, INDICATOR_DATA);
   SetIndexBuffer(3, UpperBandBuffer, INDICATOR_DATA);
   SetIndexBuffer(4, LowerBandBuffer, INDICATOR_DATA);
   SetIndexBuffer(5, RSIBuffer, INDICATOR_CALCULATIONS);
   
   // Set arrays as series
   ArraySetAsSeries(GreenLineBuffer, true);
   ArraySetAsSeries(RedLineBuffer, true);
   ArraySetAsSeries(YellowLineBuffer, true);
   ArraySetAsSeries(UpperBandBuffer, true);
   ArraySetAsSeries(LowerBandBuffer, true);
   ArraySetAsSeries(RSIBuffer, true);
   
   // Set up draw begin
   int maxPeriod = MathMax(MathMax(PriceLine_Period + SignalLine_Period, BaseLine_Period), Volatility_Band);
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, RSI_Period + PriceLine_Period);
   PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, RSI_Period + PriceLine_Period + SignalLine_Period);
   PlotIndexSetInteger(2, PLOT_DRAW_BEGIN, RSI_Period + BaseLine_Period);
   PlotIndexSetInteger(3, PLOT_DRAW_BEGIN, RSI_Period + Volatility_Band);
   PlotIndexSetInteger(4, PLOT_DRAW_BEGIN, RSI_Period + Volatility_Band);
   
   // Create RSI handle
   hRSI = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, RSI_Price);
   if(hRSI == INVALID_HANDLE)
   {
      Print("Failed to create RSI handle");
      return(INIT_FAILED);
   }
   
   // Short name
   string shortName = StringFormat("TDI(%d,%d,%d,%d)", 
                                   RSI_Period, PriceLine_Period, SignalLine_Period, BaseLine_Period);
   IndicatorSetString(INDICATOR_SHORTNAME, shortName);
   
   // Set indicator digits
   IndicatorSetInteger(INDICATOR_DIGITS, 2);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom Indicator Deinitialization Function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(hRSI != INVALID_HANDLE)
      IndicatorRelease(hRSI);
}

//+------------------------------------------------------------------+
//| Custom Indicator Iteration Function                              |
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
   // Check for minimum bars
   int minBars = RSI_Period + BaseLine_Period + Volatility_Band;
   if(rates_total < minBars)
      return(0);
   
   // Wait for RSI indicator to be ready
   if(BarsCalculated(hRSI) < rates_total)
      return(0);
   
   // Calculate start position
   int limit;
   if(prev_calculated == 0)
      limit = rates_total - RSI_Period - 1;
   else
      limit = rates_total - prev_calculated + 1;
   
   // Get RSI values
   double rsiTemp[];
   ArraySetAsSeries(rsiTemp, true);
   
   int copied = CopyBuffer(hRSI, 0, 0, rates_total, rsiTemp);
   if(copied < rates_total)
      return(0);
   
   // Copy RSI to buffer
   for(int i = 0; i < rates_total; i++)
      RSIBuffer[i] = rsiTemp[i];
   
   //+------------------------------------------------------------------+
   //| Calculate Green Line (Price Line) - SMA of RSI                   |
   //+------------------------------------------------------------------+
   for(int i = limit; i >= 0; i--)
   {
      if(i + PriceLine_Period > rates_total - 1)
      {
         GreenLineBuffer[i] = EMPTY_VALUE;
         continue;
      }
      
      double sum = 0;
      for(int j = 0; j < PriceLine_Period; j++)
      {
         sum += RSIBuffer[i + j];
      }
      GreenLineBuffer[i] = sum / PriceLine_Period;
   }
   
   //+------------------------------------------------------------------+
   //| Calculate Red Line (Signal Line) - SMA of Green Line             |
   //+------------------------------------------------------------------+
   for(int i = limit; i >= 0; i--)
   {
      if(i + SignalLine_Period > rates_total - 1 || GreenLineBuffer[i + SignalLine_Period - 1] == EMPTY_VALUE)
      {
         RedLineBuffer[i] = EMPTY_VALUE;
         continue;
      }
      
      double sum = 0;
      for(int j = 0; j < SignalLine_Period; j++)
      {
         if(GreenLineBuffer[i + j] == EMPTY_VALUE)
         {
            RedLineBuffer[i] = EMPTY_VALUE;
            break;
         }
         sum += GreenLineBuffer[i + j];
      }
      if(RedLineBuffer[i] != EMPTY_VALUE)
         RedLineBuffer[i] = sum / SignalLine_Period;
   }
   
   //+------------------------------------------------------------------+
   //| Calculate Yellow Line (Market Base Line) - SMA of RSI            |
   //+------------------------------------------------------------------+
   for(int i = limit; i >= 0; i--)
   {
      if(i + BaseLine_Period > rates_total - 1)
      {
         YellowLineBuffer[i] = EMPTY_VALUE;
         continue;
      }
      
      double sum = 0;
      for(int j = 0; j < BaseLine_Period; j++)
      {
         sum += RSIBuffer[i + j];
      }
      YellowLineBuffer[i] = sum / BaseLine_Period;
   }
   
   //+------------------------------------------------------------------+
   //| Calculate Volatility Bands (Bollinger Bands on RSI)              |
   //+------------------------------------------------------------------+
   for(int i = limit; i >= 0; i--)
   {
      if(i + Volatility_Band > rates_total - 1)
      {
         UpperBandBuffer[i] = EMPTY_VALUE;
         LowerBandBuffer[i] = EMPTY_VALUE;
         continue;
      }
      
      // Calculate middle band (SMA of RSI)
      double sum = 0;
      for(int j = 0; j < Volatility_Band; j++)
      {
         sum += RSIBuffer[i + j];
      }
      double middle = sum / Volatility_Band;
      
      // Calculate standard deviation
      double sumSquares = 0;
      for(int j = 0; j < Volatility_Band; j++)
      {
         double diff = RSIBuffer[i + j] - middle;
         sumSquares += diff * diff;
      }
      double stdDev = MathSqrt(sumSquares / Volatility_Band);
      
      // Calculate bands
      UpperBandBuffer[i] = middle + StdDev_Multiplier * stdDev;
      LowerBandBuffer[i] = middle - StdDev_Multiplier * stdDev;
   }
   
   //+------------------------------------------------------------------+
   //| Check for Alerts                                                 |
   //+------------------------------------------------------------------+
   ArraySetAsSeries(time, true);
   
   if(EnableCrossAlerts && rates_total > 3)
   {
      if(time[0] != lastAlertTime)
      {
         // Check Green/Yellow crossover on completed bar (main signal)
         if(GreenLineBuffer[2] != EMPTY_VALUE && YellowLineBuffer[2] != EMPTY_VALUE &&
            GreenLineBuffer[1] != EMPTY_VALUE && YellowLineBuffer[1] != EMPTY_VALUE)
         {
            if(GreenLineBuffer[2] <= YellowLineBuffer[2] && GreenLineBuffer[1] > YellowLineBuffer[1])
            {
               // Bullish crossover
               string msg = _Symbol + " " + EnumToString(Period()) + ": TDI Bullish - Green crossed above Yellow!";
               if(EnableSoundAlerts)
                  PlaySound("alert.wav");
               Alert(msg);
               if(EnablePushAlerts)
                  SendNotification(msg);
               lastAlertTime = time[0];
            }
            else if(GreenLineBuffer[2] >= YellowLineBuffer[2] && GreenLineBuffer[1] < YellowLineBuffer[1])
            {
               // Bearish crossover
               string msg = _Symbol + " " + EnumToString(Period()) + ": TDI Bearish - Green crossed below Yellow!";
               if(EnableSoundAlerts)
                  PlaySound("alert2.wav");
               Alert(msg);
               if(EnablePushAlerts)
                  SendNotification(msg);
               lastAlertTime = time[0];
            }
         }
      }
   }
   
   return(rates_total);
}
//+------------------------------------------------------------------+
