//+------------------------------------------------------------------+
//|                                                TDI_RedGreen.mq5  |
//|                    Traders Dynamic Index - MT5 Version           |
//|                    Original by Dean Malone, www.compassfx.com    |
//|                    Converted to MT5 for SimpleSystem_TF15        |
//+------------------------------------------------------------------+
#property copyright "Original: Dean Malone | MT5 Conversion"
#property link      "https://www.forexfactory.com/thread/345586"
#property version   "1.00"
#property description "Traders Dynamic Index for MT5"
#property description "Green = RSI Price Line | Red = Trade Signal Line"
#property description "Yellow = Market Base Line | Blue = Volatility Bands"

#property indicator_separate_window
#property indicator_buffers 6
#property indicator_plots   5

//--- Plot settings
#property indicator_label1  "VB High"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

#property indicator_label2  "Market Base Line"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrYellow
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

#property indicator_label3  "VB Low"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrDodgerBlue
#property indicator_style3  STYLE_SOLID
#property indicator_width3  1

#property indicator_label4  "RSI Price Line (Green)"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrLime
#property indicator_style4  STYLE_SOLID
#property indicator_width4  2

#property indicator_label5  "Trade Signal Line (Red)"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrRed
#property indicator_style5  STYLE_SOLID
#property indicator_width5  2

//--- Indicator levels
#property indicator_level1  32
#property indicator_level2  50
#property indicator_level3  68
#property indicator_levelcolor clrDimGray
#property indicator_levelstyle STYLE_DOT

//--- Input parameters
input int    RSI_Period        = 13;      // RSI Period (8-25)
input ENUM_APPLIED_PRICE RSI_Price = PRICE_CLOSE; // RSI Applied Price
input int    Volatility_Band   = 34;      // Volatility Band Period (20-40)
input int    RSI_Price_Line    = 2;       // RSI Price Line Smoothing
input ENUM_MA_METHOD RSI_Price_Type = MODE_SMA; // RSI Price Line MA Type
input int    Trade_Signal_Line = 7;       // Trade Signal Line Period
input ENUM_MA_METHOD Trade_Signal_Type = MODE_SMA; // Trade Signal Line MA Type

//--- Indicator buffers
double RSIBuf[];
double UpZone[];
double MdZone[];
double DnZone[];
double MaBuf[];   // Green line - RSI Price Line
double MbBuf[];   // Red line - Trade Signal Line

//--- RSI handle
int rsiHandle;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Set indicator buffers
   SetIndexBuffer(0, UpZone, INDICATOR_DATA);
   SetIndexBuffer(1, MdZone, INDICATOR_DATA);
   SetIndexBuffer(2, DnZone, INDICATOR_DATA);
   SetIndexBuffer(3, MaBuf, INDICATOR_DATA);
   SetIndexBuffer(4, MbBuf, INDICATOR_DATA);
   SetIndexBuffer(5, RSIBuf, INDICATOR_CALCULATIONS);
   
   //--- Set arrays as series
   ArraySetAsSeries(RSIBuf, true);
   ArraySetAsSeries(UpZone, true);
   ArraySetAsSeries(MdZone, true);
   ArraySetAsSeries(DnZone, true);
   ArraySetAsSeries(MaBuf, true);
   ArraySetAsSeries(MbBuf, true);
   
   //--- Set indicator name
   IndicatorSetString(INDICATOR_SHORTNAME, "TDI(" + IntegerToString(RSI_Period) + ")");
   
   //--- Set indicator digits
   IndicatorSetInteger(INDICATOR_DIGITS, 2);
   
   //--- Create RSI handle
   rsiHandle = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, RSI_Price);
   if(rsiHandle == INVALID_HANDLE)
   {
      Print("Error creating RSI handle: ", GetLastError());
      return(INIT_FAILED);
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(rsiHandle != INVALID_HANDLE)
      IndicatorRelease(rsiHandle);
}

//+------------------------------------------------------------------+
//| Calculate Standard Deviation                                     |
//+------------------------------------------------------------------+
double StDev(double &Data[], int Per)
{
   double sum = 0.0, ssum = 0.0;
   for(int i = 0; i < Per; i++)
   {
      sum += Data[i];
      ssum += MathPow(Data[i], 2);
   }
   double variance = (ssum * Per - sum * sum) / (Per * (Per - 1));
   if(variance < 0) variance = 0;
   return MathSqrt(variance);
}

//+------------------------------------------------------------------+
//| Simple Moving Average on Array                                   |
//+------------------------------------------------------------------+
double iMAOnArray(double &array[], int period, int shift)
{
   double sum = 0.0;
   for(int i = shift; i < shift + period; i++)
   {
      if(i >= ArraySize(array)) return 0;
      sum += array[i];
   }
   return sum / period;
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
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
   //--- Check for minimum bars
   if(rates_total < Volatility_Band + RSI_Period + 10)
      return(0);
   
   //--- Calculate starting position
   int limit;
   if(prev_calculated == 0)
      limit = rates_total - Volatility_Band - RSI_Period - 1;
   else
      limit = rates_total - prev_calculated + 1;
   
   //--- Get RSI data
   double rsiTemp[];
   ArraySetAsSeries(rsiTemp, true);
   if(CopyBuffer(rsiHandle, 0, 0, rates_total, rsiTemp) <= 0)
      return(0);
   
   //--- Copy RSI to our buffer
   for(int i = 0; i < rates_total; i++)
      RSIBuf[i] = rsiTemp[i];
   
   //--- Calculate Volatility Bands and Market Base Line
   double RSI[];
   ArrayResize(RSI, Volatility_Band);
   
   for(int i = limit; i >= 0; i--)
   {
      double MA = 0;
      for(int x = i; x < i + Volatility_Band && x < rates_total; x++)
      {
         if(x - i < Volatility_Band)
            RSI[x - i] = RSIBuf[x];
         MA += RSIBuf[x] / Volatility_Band;
      }
      
      double stdev = StDev(RSI, Volatility_Band);
      UpZone[i] = MA + (1.6185 * stdev);
      DnZone[i] = MA - (1.6185 * stdev);
      MdZone[i] = (UpZone[i] + DnZone[i]) / 2;
   }
   
   //--- Calculate RSI Price Line (Green) and Trade Signal Line (Red)
   for(int i = limit - 1; i >= 0; i--)
   {
      MaBuf[i] = iMAOnArray(RSIBuf, RSI_Price_Line, i);
      MbBuf[i] = iMAOnArray(RSIBuf, Trade_Signal_Line, i);
   }
   
   return(rates_total);
}
//+------------------------------------------------------------------+
