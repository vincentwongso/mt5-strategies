//+------------------------------------------------------------------+
//|                                      Magnified_Market_Price_TMS.mq5|
//|                        Magnified Market Price for TMS              |
//|                        Displays current price in large font        |
//+------------------------------------------------------------------+
#property copyright "TMS Strategy"
#property link      "https://www.forexfactory.com/thread/917569"
#property version   "1.00"
#property description "Magnified Market Price Display"

#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//--- Input parameters
input color  InpBullColor   = clrLime;     // Bullish Color (Price Up)
input color  InpBearColor   = clrRed;      // Bearish Color (Price Down)
input color  InpNeutralColor= clrGray;     // Neutral Color
input int    InpFontSize    = 14;          // Font Size
input string InpFontName    = "Arial Bold";// Font Name
input int    InpCorner      = 1;           // Corner (0=TopLeft, 1=TopRight, 2=BotLeft, 3=BotRight)
input int    InpXOffset     = 10;          // X Offset
input int    InpYOffset     = 20;          // Y Offset
input bool   InpShowSpread  = true;        // Show Spread
input bool   InpShowPips    = true;        // Show Daily Pips Change

//--- Global variables
string objPrice = "TMS_MagnifiedPrice";
string objSpread = "TMS_Spread";
string objPips = "TMS_DailyPips";

double lastPrice = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                          |
//+------------------------------------------------------------------+
int OnInit()
{
   // Set timer for updates
   EventSetMillisecondTimer(200);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   
   ObjectDelete(0, objPrice);
   ObjectDelete(0, objSpread);
   ObjectDelete(0, objPips);
}

//+------------------------------------------------------------------+
//| Timer function                                                    |
//+------------------------------------------------------------------+
void OnTimer()
{
   UpdateDisplay();
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
   UpdateDisplay();
   return rates_total;
}

//+------------------------------------------------------------------+
//| Update display                                                    |
//+------------------------------------------------------------------+
void UpdateDisplay()
{
   // Get current bid price
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   // Determine color based on price movement
   color priceColor;
   if(bid > lastPrice)
      priceColor = InpBullColor;
   else if(bid < lastPrice)
      priceColor = InpBearColor;
   else
      priceColor = InpNeutralColor;
   
   lastPrice = bid;
   
   // Format price string
   string priceStr = DoubleToString(bid, digits);
   
   // Create/update price object
   if(ObjectFind(0, objPrice) < 0)
   {
      ObjectCreate(0, objPrice, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, objPrice, OBJPROP_CORNER, InpCorner);
      ObjectSetInteger(0, objPrice, OBJPROP_XDISTANCE, InpXOffset);
      ObjectSetInteger(0, objPrice, OBJPROP_YDISTANCE, InpYOffset);
      ObjectSetInteger(0, objPrice, OBJPROP_FONTSIZE, InpFontSize);
      ObjectSetString(0, objPrice, OBJPROP_FONT, InpFontName);
      ObjectSetInteger(0, objPrice, OBJPROP_SELECTABLE, false);
   }
   
   ObjectSetString(0, objPrice, OBJPROP_TEXT, priceStr);
   ObjectSetInteger(0, objPrice, OBJPROP_COLOR, priceColor);
   
   int yOffset = InpYOffset;
   
   // Show spread
   if(InpShowSpread)
   {
      yOffset += InpFontSize + 5;
      double spread = (ask - bid) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      string spreadStr = "Spread: " + DoubleToString(spread, 1);
      
      if(ObjectFind(0, objSpread) < 0)
      {
         ObjectCreate(0, objSpread, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, objSpread, OBJPROP_CORNER, InpCorner);
         ObjectSetInteger(0, objSpread, OBJPROP_XDISTANCE, InpXOffset);
         ObjectSetInteger(0, objSpread, OBJPROP_FONTSIZE, InpFontSize - 4);
         ObjectSetString(0, objSpread, OBJPROP_FONT, InpFontName);
         ObjectSetInteger(0, objSpread, OBJPROP_COLOR, clrGray);
         ObjectSetInteger(0, objSpread, OBJPROP_SELECTABLE, false);
      }
      
      ObjectSetInteger(0, objSpread, OBJPROP_YDISTANCE, yOffset);
      ObjectSetString(0, objSpread, OBJPROP_TEXT, spreadStr);
   }
   
   // Show daily pips change
   if(InpShowPips)
   {
      yOffset += InpFontSize - 2;
      
      // Get daily open price
      double dailyOpen = iOpen(_Symbol, PERIOD_D1, 0);
      double dailyChange = (bid - dailyOpen) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      
      // Convert to pips
      double pipValue = digits == 3 || digits == 5 ? 10 : 1;
      double pipsChange = dailyChange / pipValue;
      
      string pipsStr = "Daily: " + (pipsChange >= 0 ? "+" : "") + DoubleToString(pipsChange, 1) + " pips";
      color pipsColor = pipsChange >= 0 ? InpBullColor : InpBearColor;
      
      if(ObjectFind(0, objPips) < 0)
      {
         ObjectCreate(0, objPips, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, objPips, OBJPROP_CORNER, InpCorner);
         ObjectSetInteger(0, objPips, OBJPROP_XDISTANCE, InpXOffset);
         ObjectSetInteger(0, objPips, OBJPROP_FONTSIZE, InpFontSize - 4);
         ObjectSetString(0, objPips, OBJPROP_FONT, InpFontName);
         ObjectSetInteger(0, objPips, OBJPROP_SELECTABLE, false);
      }
      
      ObjectSetInteger(0, objPips, OBJPROP_YDISTANCE, yOffset);
      ObjectSetString(0, objPips, OBJPROP_TEXT, pipsStr);
      ObjectSetInteger(0, objPips, OBJPROP_COLOR, pipsColor);
   }
   
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
