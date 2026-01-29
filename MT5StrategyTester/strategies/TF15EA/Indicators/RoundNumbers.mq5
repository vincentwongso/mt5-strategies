//+------------------------------------------------------------------+
//|                                              RoundNumbers.mq5    |
//|                    Round Number Grid Indicator - MT5 Version     |
//|                    For SimpleSystem_TF15 Strategy                |
//+------------------------------------------------------------------+
#property copyright "Original: 2Extreme4U | MT5 Conversion"
#property link      "https://www.forexfactory.com/thread/345586"
#property version   "1.00"
#property description "Draws horizontal lines at round price levels"
#property description "Useful for identifying support/resistance zones"

#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//--- Input parameters
input color  GridColor    = clrDarkBlue;   // Grid Line Color
input int    GridSpace    = 50;            // Grid Spacing (pips)
input ENUM_LINE_STYLE GridStyle = STYLE_DOT;  // Grid Line Style
input int    GridWidth    = 1;             // Grid Line Width
input bool   ShowLabels   = true;          // Show Price Labels

//--- Global variables
double pipMultiplier;
string objPrefix = "RN_Grid_";

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Calculate pip multiplier
   if(_Digits == 3 || _Digits == 5)
      pipMultiplier = MathPow(10, _Digits - 1);
   else
      pipMultiplier = MathPow(10, _Digits);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Delete all objects
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
   //--- Get visible price range
   double chartHigh = ChartGetDouble(0, CHART_PRICE_MAX, 0);
   double chartLow = ChartGetDouble(0, CHART_PRICE_MIN, 0);
   
   //--- Calculate grid step in price
   double gridStep;
   if(_Digits == 3 || _Digits == 5)
      gridStep = GridSpace * _Point * 10;  // 5-digit broker
   else
      gridStep = GridSpace * _Point;       // 4-digit broker
   
   //--- Round to nearest grid level
   double startLevel = MathFloor(chartLow / gridStep) * gridStep;
   double endLevel = MathCeil(chartHigh / gridStep) * gridStep;
   
   //--- Delete old objects and recreate
   ObjectsDeleteAll(0, objPrefix);
   
   //--- Draw grid lines
   int lineCount = 0;
   for(double level = startLevel; level <= endLevel; level += gridStep)
   {
      string objName = objPrefix + IntegerToString(lineCount);
      
      //--- Create horizontal line
      ObjectCreate(0, objName, OBJ_HLINE, 0, 0, level);
      ObjectSetInteger(0, objName, OBJPROP_COLOR, GridColor);
      ObjectSetInteger(0, objName, OBJPROP_STYLE, GridStyle);
      ObjectSetInteger(0, objName, OBJPROP_WIDTH, GridWidth);
      ObjectSetInteger(0, objName, OBJPROP_BACK, true);
      ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
      
      //--- Add price label
      if(ShowLabels)
      {
         ObjectSetString(0, objName, OBJPROP_TEXT, DoubleToString(level, _Digits));
      }
      
      lineCount++;
   }
   
   return(rates_total);
}
//+------------------------------------------------------------------+
