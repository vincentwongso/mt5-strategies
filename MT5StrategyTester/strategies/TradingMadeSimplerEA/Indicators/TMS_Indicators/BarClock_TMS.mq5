//+------------------------------------------------------------------+
//|                                                  BarClock_TMS.mq5 |
//|                        Bar Clock for Trading Made Simple           |
//|                        Shows time remaining on current bar         |
//+------------------------------------------------------------------+
#property copyright "TMS Strategy"
#property link      "https://www.forexfactory.com/thread/917569"
#property version   "1.00"
#property description "Bar Clock - Shows time remaining on current bar"

#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//--- Input parameters
input color  InpTextColor   = clrDimGray;  // Text Color
input int    InpFontSize    = 10;          // Font Size
input string InpFontName    = "Arial";     // Font Name
input int    InpCorner      = 3;           // Corner (0-3)
input int    InpXOffset     = 10;          // X Offset
input int    InpYOffset     = 20;          // Y Offset
input bool   InpShowBarNum  = true;        // Show Bar Number

//--- Global variables
string objName = "TMS_BarClock";

//+------------------------------------------------------------------+
//| Custom indicator initialization function                          |
//+------------------------------------------------------------------+
int OnInit()
{
   // Set timer for updates
   EventSetMillisecondTimer(500);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Remove timer
   EventKillTimer();
   
   // Delete object
   ObjectDelete(0, objName);
   ObjectDelete(0, objName + "_bar");
}

//+------------------------------------------------------------------+
//| Timer function                                                    |
//+------------------------------------------------------------------+
void OnTimer()
{
   UpdateClock();
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
   UpdateClock();
   return rates_total;
}

//+------------------------------------------------------------------+
//| Update clock display                                              |
//+------------------------------------------------------------------+
void UpdateClock()
{
   // Calculate time remaining
   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   int periodSeconds = PeriodSeconds(PERIOD_CURRENT);
   datetime barEndTime = barTime + periodSeconds;
   datetime currentTime = TimeCurrent();
   
   int remainingSeconds = (int)(barEndTime - currentTime);
   if(remainingSeconds < 0) remainingSeconds = 0;
   
   // Format time string
   string timeStr;
   int hours = remainingSeconds / 3600;
   int minutes = (remainingSeconds % 3600) / 60;
   int seconds = remainingSeconds % 60;
   
   if(hours > 0)
      timeStr = StringFormat("%d:%02d:%02d", hours, minutes, seconds);
   else if(minutes > 0)
      timeStr = StringFormat("%d:%02d", minutes, seconds);
   else
      timeStr = StringFormat("0:%02d", seconds);
   
   // Create/update clock object
   if(ObjectFind(0, objName) < 0)
   {
      ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, objName, OBJPROP_CORNER, InpCorner);
      ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, InpXOffset);
      ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, InpYOffset);
      ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, InpFontSize);
      ObjectSetString(0, objName, OBJPROP_FONT, InpFontName);
      ObjectSetInteger(0, objName, OBJPROP_COLOR, InpTextColor);
      ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
   }
   
   ObjectSetString(0, objName, OBJPROP_TEXT, timeStr);
   
   // Show bar number if enabled
   if(InpShowBarNum)
   {
      int barNum = iBars(_Symbol, PERIOD_CURRENT);
      string barStr = "Bar: " + IntegerToString(barNum);
      
      if(ObjectFind(0, objName + "_bar") < 0)
      {
         ObjectCreate(0, objName + "_bar", OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, objName + "_bar", OBJPROP_CORNER, InpCorner);
         ObjectSetInteger(0, objName + "_bar", OBJPROP_XDISTANCE, InpXOffset);
         ObjectSetInteger(0, objName + "_bar", OBJPROP_YDISTANCE, InpYOffset + InpFontSize + 5);
         ObjectSetInteger(0, objName + "_bar", OBJPROP_FONTSIZE, InpFontSize - 2);
         ObjectSetString(0, objName + "_bar", OBJPROP_FONT, InpFontName);
         ObjectSetInteger(0, objName + "_bar", OBJPROP_COLOR, InpTextColor);
         ObjectSetInteger(0, objName + "_bar", OBJPROP_SELECTABLE, false);
      }
      
      ObjectSetString(0, objName + "_bar", OBJPROP_TEXT, barStr);
   }
   
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
