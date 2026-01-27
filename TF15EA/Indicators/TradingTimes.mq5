//+------------------------------------------------------------------+
//|                                               TradingTimes.mq5   |
//|                    Trading Session Marker - MT5 Version          |
//|                    For SimpleSystem_TF15 Strategy                |
//+------------------------------------------------------------------+
#property copyright "Original: TraderJF | MT5 Conversion"
#property link      "https://www.forexfactory.com/thread/345586"
#property version   "1.00"
#property description "Marks important trading sessions on the chart"
#property description "London, New York, Sydney, Tokyo sessions"

#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//--- Input parameters
input group "═══════════ GENERAL SETTINGS ═══════════"
input int    TradingDays       = 10;       // Days to show lines

input group "═══════════ LONDON SESSION ═══════════"
input bool   ShowLondon        = true;     // Show London Open
input string LondonOpenTime    = "08:00";  // London Open Time (Server)
input color  LondonColor       = clrOrangeRed; // London Line Color

input group "═══════════ NEW YORK SESSION ═══════════"
input bool   ShowNewYork       = true;     // Show New York Open
input string NYOpenTime        = "13:00";  // New York Open Time (Server)
input color  NYColor           = clrDarkGoldenrod; // NY Line Color

input group "═══════════ EUROPE SESSION ═══════════"
input bool   ShowEuropeOpen    = false;    // Show Europe Open
input string EuropeOpenTime    = "07:00";  // Europe Open Time (Server)
input color  EuropeOpenColor   = clrDarkOrange; // Europe Open Color
input bool   ShowEuropeClose   = false;    // Show Europe Close
input string EuropeCloseTime   = "17:00";  // Europe Close Time (Server)
input color  EuropeCloseColor  = clrMaroon; // Europe Close Color

input group "═══════════ SYDNEY SESSION ═══════════"
input bool   ShowSydney        = false;    // Show Sydney Open
input string SydneyOpenTime    = "22:00";  // Sydney Open Time (Server)
input color  SydneyColor       = clrDarkGreen; // Sydney Line Color

input group "═══════════ TOKYO SESSION ═══════════"
input bool   ShowTokyo         = false;    // Show Tokyo Open
input string TokyoOpenTime     = "00:00";  // Tokyo Open Time (Server)
input color  TokyoColor        = clrChocolate; // Tokyo Line Color

input group "═══════════ DISPLAY OPTIONS ═══════════"
input int    LineWidth         = 2;        // Line Width
input ENUM_LINE_STYLE LineStyle = STYLE_SOLID; // Line Style

//--- Global variables
string objPrefix = "TT_";

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Draw initial lines
   DrawTradingLines();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, objPrefix);
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
   //--- Redraw on new day
   static datetime lastDay = 0;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime currentDay = StringToTime(IntegerToString(dt.year) + "." + 
                                      IntegerToString(dt.mon) + "." + 
                                      IntegerToString(dt.day));
   
   if(currentDay != lastDay)
   {
      DrawTradingLines();
      lastDay = currentDay;
   }
   
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Draw all trading time lines                                      |
//+------------------------------------------------------------------+
void DrawTradingLines()
{
   //--- Delete old objects
   ObjectsDeleteAll(0, objPrefix);
   
   //--- Get current time
   datetime currentTime = TimeCurrent();
   
   //--- Draw lines for each day
   for(int day = 0; day < TradingDays; day++)
   {
      //--- Calculate day start
      MqlDateTime dt;
      TimeToStruct(currentTime - day * 86400, dt);
      
      //--- Skip weekends
      if(dt.day_of_week == 0 || dt.day_of_week == 6)
         continue;
      
      string dateStr = IntegerToString(dt.year) + "." + 
                       IntegerToString(dt.mon) + "." + 
                       IntegerToString(dt.day);
      
      //--- Draw session lines
      if(ShowLondon)
         DrawSessionLine("London_" + IntegerToString(day), dateStr, LondonOpenTime, LondonColor, "London Open");
      
      if(ShowNewYork)
         DrawSessionLine("NY_" + IntegerToString(day), dateStr, NYOpenTime, NYColor, "NY Open");
      
      if(ShowEuropeOpen)
         DrawSessionLine("EuropeOpen_" + IntegerToString(day), dateStr, EuropeOpenTime, EuropeOpenColor, "Europe Open");
      
      if(ShowEuropeClose)
         DrawSessionLine("EuropeClose_" + IntegerToString(day), dateStr, EuropeCloseTime, EuropeCloseColor, "Europe Close");
      
      if(ShowSydney)
         DrawSessionLine("Sydney_" + IntegerToString(day), dateStr, SydneyOpenTime, SydneyColor, "Sydney Open");
      
      if(ShowTokyo)
         DrawSessionLine("Tokyo_" + IntegerToString(day), dateStr, TokyoOpenTime, TokyoColor, "Tokyo Open");
   }
}

//+------------------------------------------------------------------+
//| Draw a session vertical line                                     |
//+------------------------------------------------------------------+
void DrawSessionLine(string name, string date, string time, color lineColor, string tooltip)
{
   string objName = objPrefix + name;
   datetime lineTime = StringToTime(date + " " + time);
   
   //--- Don't draw future lines
   if(lineTime > TimeCurrent())
      return;
   
   //--- Create vertical line
   ObjectCreate(0, objName, OBJ_VLINE, 0, lineTime, 0);
   ObjectSetInteger(0, objName, OBJPROP_COLOR, lineColor);
   ObjectSetInteger(0, objName, OBJPROP_STYLE, LineStyle);
   ObjectSetInteger(0, objName, OBJPROP_WIDTH, LineWidth);
   ObjectSetInteger(0, objName, OBJPROP_BACK, true);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, objName, OBJPROP_TOOLTIP, tooltip);
}
//+------------------------------------------------------------------+
