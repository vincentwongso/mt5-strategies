//+------------------------------------------------------------------+
//|                                                TDI_Bounce_EA.mq5 |
//|                           Based on "Another Simple System - TF15" |
//|                                  Original system from ForexFactory |
//+------------------------------------------------------------------+
#property copyright "TDI Bounce Trading System EA"
#property link      ""
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
// Trading Parameters
input group "=== Trading Settings ==="
input bool     TradeEURUSD            = true;        // Trade EURUSD
input bool     TradeGBPUSD            = true;        // Trade GBPUSD
input double   RiskPercent            = 2.0;         // Risk Percentage per Trade
input double   StopLossPips           = 20.0;        // Stop Loss in Pips
input double   TakeProfitPips         = 20.0;        // Take Profit in Pips (0 = use TDI exit)
input double   BreakevenPips          = 12.0;        // Move SL to BE after X pips
input ulong    MagicNumber            = 123456;      // Magic Number

// Session Filter
input group "=== Session Settings ==="
input bool     TradeLondonSession     = true;        // Trade London Session
input bool     TradeNewYorkSession    = true;        // Trade New York Session
input int      LondonStartHour        = 8;           // London Session Start (Server Time)
input int      LondonEndHour          = 12;          // London Session End
input int      NewYorkStartHour       = 13;          // NY Session Start (Server Time)
input int      NewYorkEndHour         = 17;          // NY Session End

// EMA Parameters
input group "=== EMA Settings ==="
input int      EMA_10_Period          = 10;          // Fast EMA Period
input int      EMA_200_Period         = 200;         // Main EMA Period (15M)
input int      EMA_800_Period         = 800;         // Long-term EMA Period (4H equivalent)
input int      MinDistanceFromEMA     = 5;           // Min pips away from 200 EMA

// TDI Parameters (Default Dean Malone Settings)
input group "=== TDI Settings ==="
input int      RSI_Period             = 13;          // RSI Period
input ENUM_APPLIED_PRICE RSI_Price    = PRICE_CLOSE; // RSI Applied Price
input int      PriceLine_Period       = 2;           // Green Line (Price) MA Period
input ENUM_MA_METHOD PriceLine_Type   = MODE_SMA;    // Green Line MA Type
input int      SignalLine_Period      = 7;           // Red Line (Signal) MA Period
input ENUM_MA_METHOD SignalLine_Type  = MODE_SMA;    // Red Line MA Type
input int      BaseLine_Period        = 34;          // Yellow Line (Base) MA Period
input ENUM_MA_METHOD BaseLine_Type    = MODE_SMA;    // Yellow Line MA Type

// Alert Settings
input group "=== Alert Settings ==="
input bool     EnableAlerts           = true;        // Enable Alerts
input bool     EnablePushNotification = false;       // Enable Push Notifications
input bool     EnableEmailAlert       = false;       // Enable Email Alerts

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  positionInfo;
CSymbolInfo    symbolInfo;

double  g_point;
int     g_digits;

// Indicator Handles
int     hRSI;
int     hEMA10;
int     hEMA200;
int     hEMA800;

// TDI Buffer Arrays
double TDI_RSI[];
double TDI_GreenLine[];     // Price Line
double TDI_RedLine[];       // Signal Line
double TDI_YellowLine[];    // Market Base Line

// For new bar detection
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Check if we're on 15-minute timeframe
   if(Period() != PERIOD_M15)
   {
      Alert("This EA is designed for 15-minute timeframe only! Current: ", EnumToString(Period()));
      return(INIT_FAILED);
   }
   
   // Initialize symbol info
   if(!symbolInfo.Name(_Symbol))
   {
      Print("Failed to initialize symbol info");
      return(INIT_FAILED);
   }
   
   // Set up point value for pip calculation
   g_digits = (int)symbolInfo.Digits();
   if(g_digits == 3 || g_digits == 5)
      g_point = symbolInfo.Point() * 10;
   else
      g_point = symbolInfo.Point();
   
   // Set up trade object
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   // Create indicator handles
   hRSI = iRSI(_Symbol, PERIOD_M15, RSI_Period, RSI_Price);
   hEMA10 = iMA(_Symbol, PERIOD_M15, EMA_10_Period, 0, MODE_EMA, PRICE_CLOSE);
   hEMA200 = iMA(_Symbol, PERIOD_M15, EMA_200_Period, 0, MODE_EMA, PRICE_CLOSE);
   hEMA800 = iMA(_Symbol, PERIOD_M15, EMA_800_Period, 0, MODE_EMA, PRICE_CLOSE);
   
   if(hRSI == INVALID_HANDLE || hEMA10 == INVALID_HANDLE || 
      hEMA200 == INVALID_HANDLE || hEMA800 == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles");
      return(INIT_FAILED);
   }
   
   // Resize arrays
   ArraySetAsSeries(TDI_RSI, true);
   ArraySetAsSeries(TDI_GreenLine, true);
   ArraySetAsSeries(TDI_RedLine, true);
   ArraySetAsSeries(TDI_YellowLine, true);
   
   ArrayResize(TDI_RSI, 100);
   ArrayResize(TDI_GreenLine, 100);
   ArrayResize(TDI_RedLine, 100);
   ArrayResize(TDI_YellowLine, 100);
   
   Print("TDI Bounce EA Initialized on ", _Symbol, " ", EnumToString(Period()));
   Print("Point: ", g_point, " Digits: ", g_digits);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert Deinitialization Function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   if(hRSI != INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hEMA10 != INVALID_HANDLE) IndicatorRelease(hEMA10);
   if(hEMA200 != INVALID_HANDLE) IndicatorRelease(hEMA200);
   if(hEMA800 != INVALID_HANDLE) IndicatorRelease(hEMA800);
   
   Comment("");
}

//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check symbol validity
   if(!IsValidSymbol())
      return;
   
   // Refresh symbol info
   symbolInfo.RefreshRates();
   
   // Manage existing positions (breakeven)
   ManagePositions();
   
   // Check for TDI exit signals
   if(TakeProfitPips == 0)
      CheckTDIExit();
   
   // Only check for new trades on new bar
   datetime currentBarTime = iTime(_Symbol, PERIOD_M15, 0);
   if(currentBarTime == lastBarTime)
      return;
   lastBarTime = currentBarTime;
   
   // Check session filter
   if(!IsValidSession())
      return;
   
   // Check if we already have an open position
   if(HasOpenPosition())
      return;
   
   // Calculate TDI values
   if(!CalculateTDI())
      return;
   
   // Get EMA values
   double ema10[], ema200[], ema800[];
   ArraySetAsSeries(ema10, true);
   ArraySetAsSeries(ema200, true);
   ArraySetAsSeries(ema800, true);
   
   if(CopyBuffer(hEMA10, 0, 0, 3, ema10) < 3) return;
   if(CopyBuffer(hEMA200, 0, 0, 3, ema200) < 3) return;
   if(CopyBuffer(hEMA800, 0, 0, 3, ema800) < 3) return;
   
   double ema10_1 = ema10[1];
   double ema10_2 = ema10[2];
   double ema200_1 = ema200[1];
   double ema800_1 = ema800[1];
   
   // Get price values
   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   double close2 = iClose(_Symbol, PERIOD_M15, 2);
   
   // Distance from 200 EMA in pips
   double distanceFrom200 = MathAbs(close1 - ema200_1) / g_point;
   
   // TDI values (bar 1 = last closed, bar 2 = previous)
   double green1 = TDI_GreenLine[1];
   double green2 = TDI_GreenLine[2];
   double red1 = TDI_RedLine[1];
   double red2 = TDI_RedLine[2];
   double yellow1 = TDI_YellowLine[1];
   double yellow2 = TDI_YellowLine[2];
   
   // Display info
   DisplayInfo(close1, ema10_1, ema200_1, ema800_1, green1, red1, yellow1, distanceFrom200);
   
   //+------------------------------------------------------------------+
   //| BUY Signal Conditions                                            |
   //+------------------------------------------------------------------+
   // 1. Price is ABOVE 200 EMA (away from it)
   // 2. Price closed ABOVE 10 EMA
   // 3. TDI Green crosses above Yellow (Green above Red)
   // 4. Yellow line slope pointing upwards
   
   bool buySignal = false;
   
   if(close1 > ema200_1 &&                         // Price above 200 EMA
      distanceFrom200 >= MinDistanceFromEMA &&     // Min distance from 200 EMA
      close1 > ema10_1 &&                          // Price closed above 10 EMA
      close2 <= ema10_2 &&                         // Previous close was at/below 10 EMA (confirmation)
      green1 > red1 &&                             // Green above Red
      green1 > yellow1 &&                          // Green above Yellow
      green2 <= yellow2 &&                         // Green was at/below Yellow (crossover)
      yellow1 > yellow2)                           // Yellow slope pointing up
   {
      buySignal = true;
   }
   
   //+------------------------------------------------------------------+
   //| SELL Signal Conditions                                           |
   //+------------------------------------------------------------------+
   // 1. Price is BELOW 200 EMA (away from it)
   // 2. Price closed BELOW 10 EMA
   // 3. TDI Green crosses below Yellow (Red above Green)
   // 4. Yellow line slope pointing downwards
   
   bool sellSignal = false;
   
   if(close1 < ema200_1 &&                         // Price below 200 EMA
      distanceFrom200 >= MinDistanceFromEMA &&     // Min distance from 200 EMA
      close1 < ema10_1 &&                          // Price closed below 10 EMA
      close2 >= ema10_2 &&                         // Previous close was at/above 10 EMA (confirmation)
      green1 < red1 &&                             // Red above Green
      green1 < yellow1 &&                          // Green below Yellow
      green2 >= yellow2 &&                         // Green was at/above Yellow (crossover)
      yellow1 < yellow2)                           // Yellow slope pointing down
   {
      sellSignal = true;
   }
   
   // Execute trades
   if(buySignal)
   {
      ExecuteTrade(ORDER_TYPE_BUY);
   }
   else if(sellSignal)
   {
      ExecuteTrade(ORDER_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
//| Calculate TDI Values                                             |
//+------------------------------------------------------------------+
bool CalculateTDI()
{
   // Get RSI values
   double rsiBuffer[];
   ArraySetAsSeries(rsiBuffer, true);
   
   if(CopyBuffer(hRSI, 0, 0, 100, rsiBuffer) < 100)
      return false;
   
   // Copy RSI to our buffer
   for(int i = 0; i < 100; i++)
      TDI_RSI[i] = rsiBuffer[i];
   
   // Calculate Green Line (Price Line) = SMA of RSI
   for(int i = 0; i < 95; i++)
   {
      double sum = 0;
      for(int j = 0; j < PriceLine_Period; j++)
      {
         sum += TDI_RSI[i + j];
      }
      TDI_GreenLine[i] = sum / PriceLine_Period;
   }
   
   // Calculate Red Line (Signal Line) = SMA of Green Line
   for(int i = 0; i < 90; i++)
   {
      double sum = 0;
      for(int j = 0; j < SignalLine_Period; j++)
      {
         sum += TDI_GreenLine[i + j];
      }
      TDI_RedLine[i] = sum / SignalLine_Period;
   }
   
   // Calculate Yellow Line (Market Base Line) = SMA of RSI
   for(int i = 0; i < 65; i++)
   {
      double sum = 0;
      for(int j = 0; j < BaseLine_Period; j++)
      {
         sum += TDI_RSI[i + j];
      }
      TDI_YellowLine[i] = sum / BaseLine_Period;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if current symbol is valid for trading                     |
//+------------------------------------------------------------------+
bool IsValidSymbol()
{
   string symbol = _Symbol;
   
   if(TradeEURUSD && StringFind(symbol, "EURUSD") >= 0)
      return true;
   if(TradeGBPUSD && StringFind(symbol, "GBPUSD") >= 0)
      return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| Check if current time is within valid trading session            |
//+------------------------------------------------------------------+
bool IsValidSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;
   
   // London Session
   if(TradeLondonSession && hour >= LondonStartHour && hour < LondonEndHour)
      return true;
   
   // New York Session
   if(TradeNewYorkSession && hour >= NewYorkStartHour && hour < NewYorkEndHour)
      return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| Check if we have an open position for this symbol                |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == MagicNumber)
         {
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Execute Trade                                                    |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE orderType)
{
   double lotSize = CalculateLotSize();
   double price, sl, tp;
   string orderComment = "TDI Bounce";
   
   symbolInfo.RefreshRates();
   
   if(orderType == ORDER_TYPE_BUY)
   {
      price = symbolInfo.Ask();
      sl = NormalizeDouble(price - StopLossPips * g_point, g_digits);
      tp = (TakeProfitPips > 0) ? NormalizeDouble(price + TakeProfitPips * g_point, g_digits) : 0;
      
      if(trade.Buy(lotSize, _Symbol, price, sl, tp, orderComment))
      {
         SendTradeNotification("BUY", price, sl, tp, lotSize);
         Print("BUY Order Opened: Price: ", price, " SL: ", sl, " TP: ", tp);
      }
      else
      {
         Print("BUY Order Failed! Error: ", GetLastError(), " - ", trade.ResultComment());
      }
   }
   else if(orderType == ORDER_TYPE_SELL)
   {
      price = symbolInfo.Bid();
      sl = NormalizeDouble(price + StopLossPips * g_point, g_digits);
      tp = (TakeProfitPips > 0) ? NormalizeDouble(price - TakeProfitPips * g_point, g_digits) : 0;
      
      if(trade.Sell(lotSize, _Symbol, price, sl, tp, orderComment))
      {
         SendTradeNotification("SELL", price, sl, tp, lotSize);
         Print("SELL Order Opened: Price: ", price, " SL: ", sl, " TP: ", tp);
      }
      else
      {
         Print("SELL Order Failed! Error: ", GetLastError(), " - ", trade.ResultComment());
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate Lot Size based on Risk Percentage                      |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (RiskPercent / 100.0);
   
   // Get tick value
   double tickValue = symbolInfo.TickValue();
   double tickSize = symbolInfo.TickSize();
   
   if(tickValue == 0 || tickSize == 0)
      return symbolInfo.LotsMin();
   
   // Calculate pip value per lot
   double pipValuePerLot = tickValue * (g_point / tickSize);
   
   if(pipValuePerLot == 0)
      return symbolInfo.LotsMin();
   
   double lots = riskAmount / (StopLossPips * pipValuePerLot);
   
   // Normalize lot size
   double minLot = symbolInfo.LotsMin();
   double maxLot = symbolInfo.LotsMax();
   double lotStep = symbolInfo.LotsStep();
   
   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Manage Existing Positions (Breakeven)                            |
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == MagicNumber)
         {
            MoveToBreakeven();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Move Stop Loss to Breakeven                                      |
//+------------------------------------------------------------------+
void MoveToBreakeven()
{
   if(BreakevenPips <= 0)
      return;
   
   double currentPrice;
   double openPrice = positionInfo.PriceOpen();
   double currentSL = positionInfo.StopLoss();
   double currentTP = positionInfo.TakeProfit();
   double breakeven = BreakevenPips * g_point;
   
   symbolInfo.RefreshRates();
   
   if(positionInfo.PositionType() == POSITION_TYPE_BUY)
   {
      currentPrice = symbolInfo.Bid();
      
      // If price has moved BE pips in profit and SL is not yet at breakeven
      if(currentPrice >= openPrice + breakeven && currentSL < openPrice)
      {
         double newSL = NormalizeDouble(openPrice + g_point, g_digits);
         if(trade.PositionModify(positionInfo.Ticket(), newSL, currentTP))
            Print("BUY Position moved to breakeven: Ticket #", positionInfo.Ticket());
      }
   }
   else if(positionInfo.PositionType() == POSITION_TYPE_SELL)
   {
      currentPrice = symbolInfo.Ask();
      
      // If price has moved BE pips in profit and SL is not yet at breakeven
      if(currentPrice <= openPrice - breakeven && (currentSL > openPrice || currentSL == 0))
      {
         double newSL = NormalizeDouble(openPrice - g_point, g_digits);
         if(trade.PositionModify(positionInfo.Ticket(), newSL, currentTP))
            Print("SELL Position moved to breakeven: Ticket #", positionInfo.Ticket());
      }
   }
}

//+------------------------------------------------------------------+
//| Check TDI Exit Signal (when TP = 0)                              |
//+------------------------------------------------------------------+
void CheckTDIExit()
{
   if(!CalculateTDI())
      return;
   
   double green1 = TDI_GreenLine[1];
   double green2 = TDI_GreenLine[2];
   double yellow1 = TDI_YellowLine[1];
   double yellow2 = TDI_YellowLine[2];
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == MagicNumber)
         {
            // BUY Exit: Green crosses below Yellow
            if(positionInfo.PositionType() == POSITION_TYPE_BUY)
            {
               if(green2 >= yellow2 && green1 < yellow1)
               {
                  if(trade.PositionClose(positionInfo.Ticket()))
                     Print("BUY Position closed on TDI exit signal");
               }
            }
            // SELL Exit: Green crosses above Yellow
            else if(positionInfo.PositionType() == POSITION_TYPE_SELL)
            {
               if(green2 <= yellow2 && green1 > yellow1)
               {
                  if(trade.PositionClose(positionInfo.Ticket()))
                     Print("SELL Position closed on TDI exit signal");
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Send Notification                                                |
//+------------------------------------------------------------------+
void SendTradeNotification(string orderType, double price, double sl, double tp, double lots)
{
   string msg = StringFormat("TDI Bounce %s: %s @ %.5f | SL: %.5f | TP: %.5f | Lots: %.2f",
                             orderType, _Symbol, price, sl, tp, lots);
   
   if(EnableAlerts)
      Alert(msg);
   
   if(EnablePushNotification)
      SendNotification(msg);
   
   if(EnableEmailAlert)
      SendMail("TDI Bounce Signal", msg);
}

//+------------------------------------------------------------------+
//| Display Information on Chart                                     |
//+------------------------------------------------------------------+
void DisplayInfo(double price, double ema10, double ema200, double ema800, 
                 double green, double red, double yellow, double distance)
{
   string session = "Inactive";
   if(IsValidSession())
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int hour = dt.hour;
      
      if(TradeLondonSession && hour >= LondonStartHour && hour < LondonEndHour)
         session = "London";
      else if(TradeNewYorkSession && hour >= NewYorkStartHour && hour < NewYorkEndHour)
         session = "New York";
   }
   
   string pricePos = (price > ema200) ? "ABOVE" : "BELOW";
   string tdiSignal = (green > yellow) ? "BULLISH (Green > Yellow)" : "BEARISH (Green < Yellow)";
   
   string info = StringFormat(
      "=== TDI Bounce EA (MT5) ===\n" +
      "Symbol: %s | TF: %s\n" +
      "Session: %s\n" +
      "-------------------\n" +
      "Price: %.5f\n" +
      "EMA 10: %.5f\n" +
      "EMA 200: %.5f\n" +
      "EMA 800: %.5f\n" +
      "Distance from 200: %.1f pips\n" +
      "Price vs 200: %s\n" +
      "-------------------\n" +
      "TDI Green: %.2f\n" +
      "TDI Red: %.2f\n" +
      "TDI Yellow: %.2f\n" +
      "TDI Signal: %s\n" +
      "-------------------\n" +
      "Open Positions: %d",
      _Symbol, EnumToString(Period()),
      session,
      price, ema10, ema200, ema800,
      distance, pricePos,
      green, red, yellow, tdiSignal,
      CountOpenPositions()
   );
   
   Comment(info);
}

//+------------------------------------------------------------------+
//| Count Open Positions                                             |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == MagicNumber)
            count++;
      }
   }
   return count;
}
//+------------------------------------------------------------------+
