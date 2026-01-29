//+------------------------------------------------------------------+
//|                                           TDI_Bounce_EA_GBPUSD.mq5 |
//|                           Based on "Another Simple System - TF15" |
//|              GBPUSD Optimized Version with ATR & TDI Zone Filters |
//|                      v3.0 - Improved Trade Count & Trailing Stop  |
//+------------------------------------------------------------------+
#property copyright "TDI Bounce Trading System EA - GBPUSD Optimized"
#property link      ""
#property version   "3.00"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
// Trading Parameters - GBPUSD Optimized v3.0
input group "=== Trading Settings (GBPUSD v3.0) ==="
input double   RiskPercent            = 1.0;         // Risk Percentage per Trade
input double   StopLossPips           = 25.0;        // Stop Loss in Pips
input double   TakeProfitPips         = 25.0;        // Take Profit in Pips (0 = use trailing/TDI)
input double   BreakevenPips          = 16.0;        // Move SL to BE after X pips
input ulong    MagicNumber            = 123457;      // Magic Number (different from EURUSD)

// Session Filter (GMT-based with offset)
input group "=== Session Settings ==="
input int      ServerGMTOffset        = 2;           // Server GMT Offset (e.g., 2 for GMT+2)
input int      TradingStartHourGMT    = 8;           // Trading Start Hour (GMT) - London Open
input int      TradingEndHourGMT      = 17;          // Trading End Hour (GMT) - NY Afternoon

// EMA Parameters - Re-tuned for more trades in v3.0
input group "=== EMA Settings (v3.0 Re-tuned) ==="
input int      EMA_10_Period          = 10;          // Fast EMA Period
input int      EMA_200_Period         = 200;         // Main EMA Period (15M)
input int      EMA_800_Period         = 800;         // Long-term EMA Period (4H equivalent)
input int      MinDistanceFromEMA     = 6;           // Min pips away from 200 EMA (was 10, now 6)

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

// TDI Zone Filter - Relaxed for more trades in v3.0
input group "=== TDI Zone Filter (v3.0 Relaxed) ==="
input bool     UseTDIZoneFilter       = true;        // Enable TDI Zone Filter
input double   TDI_ZoneLower          = 40.0;        // Yellow line lower bound (was 45, now 40)
input double   TDI_ZoneUpper          = 60.0;        // Yellow line upper bound (was 55, now 60)
input double   TDI_GreenRedMinGap     = 1.0;         // Minimum gap Green-Red (was 2.0, now 1.0)

// ATR Volatility Filter - Relaxed for more trades in v3.0
input group "=== ATR Volatility Filter (v3.0 Relaxed) ==="
input bool     UseATRFilter           = true;        // Enable ATR Filter
input int      ATR_Period             = 14;          // ATR Period
input double   ATR_MaxMultiplier      = 2.0;         // Max ATR multiplier (was 1.5, now 2.0)
input int      ATR_AveragePeriod      = 50;          // Period to calculate average ATR

// ATR Trailing Stop - NEW in v3.0
input group "=== ATR Trailing Stop (NEW v3.0) ==="
input bool     UseTrailingStop        = true;        // Enable ATR-based Trailing Stop
input double   TrailActivationPips    = 15.0;        // Profit pips before trail starts
input double   TrailATRMultiplier     = 1.5;         // Trail distance = ATR x multiplier
input double   MinTrailStopPips       = 10.0;        // Minimum trail distance in pips
input double   MaxTrailStopPips       = 30.0;        // Maximum trail distance in pips
input bool     RemoveTPWhenTrailing   = true;        // Remove fixed TP when trailing starts

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
int     hATR;

// TDI Buffer Arrays
double TDI_RSI[];
double TDI_GreenLine[];     // Price Line
double TDI_RedLine[];       // Signal Line
double TDI_YellowLine[];    // Market Base Line

// ATR Buffer Arrays
double ATR_Values[];
double ATR_Average;

// For new bar detection
datetime lastBarTime = 0;

// Trade skip reasons (for logging)
string lastSkipReason = "";

// Trailing stop tracking
bool g_trailingActive = false;
double g_currentTrailDistance = 0;

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
   
   // Check if we're on GBPUSD
   if(StringFind(_Symbol, "GBPUSD") < 0)
   {
      Alert("This EA is optimized for GBPUSD only! Current: ", _Symbol);
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
   hATR = iATR(_Symbol, PERIOD_M15, ATR_Period);
   
   if(hRSI == INVALID_HANDLE || hEMA10 == INVALID_HANDLE || 
      hEMA200 == INVALID_HANDLE || hEMA800 == INVALID_HANDLE || hATR == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles");
      return(INIT_FAILED);
   }
   
   // Resize arrays
   ArraySetAsSeries(TDI_RSI, true);
   ArraySetAsSeries(TDI_GreenLine, true);
   ArraySetAsSeries(TDI_RedLine, true);
   ArraySetAsSeries(TDI_YellowLine, true);
   ArraySetAsSeries(ATR_Values, true);
   
   ArrayResize(TDI_RSI, 100);
   ArrayResize(TDI_GreenLine, 100);
   ArrayResize(TDI_RedLine, 100);
   ArrayResize(TDI_YellowLine, 100);
   ArrayResize(ATR_Values, ATR_AveragePeriod + 10);
   
   Print("==============================================");
   Print("TDI Bounce EA GBPUSD v3.0 Initialized");
   Print("Symbol: ", _Symbol, " Timeframe: ", EnumToString(Period()));
   Print("Point: ", g_point, " Digits: ", g_digits);
   Print("=== v3.0 Settings (More Trades + Trailing) ===");
   Print("- Stop Loss: ", StopLossPips, " pips");
   Print("- Breakeven: ", BreakevenPips, " pips");
   Print("- Min EMA Distance: ", MinDistanceFromEMA, " pips (relaxed)");
   Print("- ATR Filter: ", (UseATRFilter ? StringFormat("ON (max %.1fx avg)", ATR_MaxMultiplier) : "OFF"));
   Print("- TDI Zone: ", (UseTDIZoneFilter ? StringFormat("ON (%.0f-%.0f)", TDI_ZoneLower, TDI_ZoneUpper) : "OFF"));
   Print("- Trailing Stop: ", (UseTrailingStop ? StringFormat("ON (ATR x%.1f)", TrailATRMultiplier) : "OFF"));
   Print("Trading Hours: ", TradingStartHourGMT, ":00 - ", TradingEndHourGMT, ":00 GMT");
   Print("==============================================");
   
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
   if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
   
   Comment("");
}

//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
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
   
   // Reset skip reason
   lastSkipReason = "";
   
   // Check session filter
   if(!IsValidSession())
   {
      lastSkipReason = "Outside trading session";
      DisplayInfo(0, 0, 0, 0, 0, 0, 0, 0, 0);
      return;
   }
   
   // Check if we already have an open position
   if(HasOpenPosition())
   {
      lastSkipReason = "Position already open";
      return;
   }
   
   // Calculate TDI values
   if(!CalculateTDI())
   {
      lastSkipReason = "TDI calculation failed";
      return;
   }
   
   // Check ATR Filter - NEW
   if(UseATRFilter && !CheckATRFilter())
   {
      lastSkipReason = "ATR volatility too high";
      DisplayInfo(0, 0, 0, 0, 0, 0, 0, 0, 0);
      return;
   }
   
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
   
   // Get current ATR
   double currentATR = GetCurrentATR();
   
   // Display info
   DisplayInfo(close1, ema10_1, ema200_1, ema800_1, green1, red1, yellow1, distanceFrom200, currentATR);
   
   //+------------------------------------------------------------------+
   //| TDI Zone Filter Check - NEW                                      |
   //+------------------------------------------------------------------+
   if(UseTDIZoneFilter)
   {
      // Check if yellow line is in the neutral zone (45-55)
      if(yellow1 < TDI_ZoneLower || yellow1 > TDI_ZoneUpper)
      {
         lastSkipReason = StringFormat("TDI Yellow (%.2f) outside zone (%.0f-%.0f)", 
                                        yellow1, TDI_ZoneLower, TDI_ZoneUpper);
         return;
      }
      
      // Check minimum gap between Green and Red lines
      double greenRedGap = MathAbs(green1 - red1);
      if(greenRedGap < TDI_GreenRedMinGap)
      {
         lastSkipReason = StringFormat("Green-Red gap (%.2f) < minimum (%.1f)", 
                                        greenRedGap, TDI_GreenRedMinGap);
         return;
      }
   }
   
   //+------------------------------------------------------------------+
   //| BUY Signal Conditions                                            |
   //+------------------------------------------------------------------+
   // 1. Price is ABOVE 200 EMA (away from it)
   // 2. Price closed ABOVE 10 EMA
   // 3. TDI Green crosses above Yellow (Green above Red)
   // 4. Yellow line slope pointing upwards
   
   bool buySignal = false;
   
   if(close1 > ema200_1 &&                         // Price above 200 EMA
      distanceFrom200 >= MinDistanceFromEMA &&     // Min distance from 200 EMA (increased for GBPUSD)
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
      distanceFrom200 >= MinDistanceFromEMA &&     // Min distance from 200 EMA (increased for GBPUSD)
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
//| Check ATR Filter - NEW                                           |
//+------------------------------------------------------------------+
bool CheckATRFilter()
{
   // Get ATR values
   if(CopyBuffer(hATR, 0, 0, ATR_AveragePeriod + 5, ATR_Values) < ATR_AveragePeriod)
      return true; // If we can't get data, don't filter
   
   // Current ATR
   double currentATR = ATR_Values[1];
   
   // Calculate average ATR
   double sumATR = 0;
   for(int i = 1; i <= ATR_AveragePeriod; i++)
   {
      sumATR += ATR_Values[i];
   }
   ATR_Average = sumATR / ATR_AveragePeriod;
   
   // Check if current ATR exceeds threshold
   if(ATR_Average > 0 && currentATR > ATR_Average * ATR_MaxMultiplier)
   {
      Print("ATR Filter: Current ATR (", DoubleToString(currentATR / g_point, 1), 
            " pips) > ", DoubleToString(ATR_MaxMultiplier, 1), "x Average (", 
            DoubleToString(ATR_Average / g_point, 1), " pips) - Trade skipped");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Get Current ATR in raw value                                     |
//+------------------------------------------------------------------+
double GetCurrentATR()
{
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(hATR, 0, 0, 2, atr) >= 2)
      return atr[1];
   return 0;
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
//| Convert Server Time to GMT                                       |
//+------------------------------------------------------------------+
int GetCurrentGMTHour()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int serverHour = dt.hour;
   
   // Convert server hour to GMT (subtract the offset)
   int gmtHour = serverHour - ServerGMTOffset;
   
   // Handle wrap-around for negative hours
   if(gmtHour < 0)
      gmtHour += 24;
   else if(gmtHour >= 24)
      gmtHour -= 24;
   
   return gmtHour;
}

//+------------------------------------------------------------------+
//| Check if current time is within valid trading session            |
//+------------------------------------------------------------------+
bool IsValidSession()
{
   int gmtHour = GetCurrentGMTHour();
   
   // Single combined session: London Open to NY Afternoon (GMT)
   // Handle normal case (start < end)
   if(TradingStartHourGMT < TradingEndHourGMT)
   {
      return (gmtHour >= TradingStartHourGMT && gmtHour < TradingEndHourGMT);
   }
   // Handle overnight session (start > end, e.g., 22:00-06:00)
   else
   {
      return (gmtHour >= TradingStartHourGMT || gmtHour < TradingEndHourGMT);
   }
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
   string orderComment = "TDI Bounce GBPUSD";
   
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
         Print("  - ATR Filter: ", (UseATRFilter ? "Passed" : "Disabled"));
         Print("  - TDI Zone Filter: ", (UseTDIZoneFilter ? "Passed" : "Disabled"));
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
         Print("  - ATR Filter: ", (UseATRFilter ? "Passed" : "Disabled"));
         Print("  - TDI Zone Filter: ", (UseTDIZoneFilter ? "Passed" : "Disabled"));
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
//| Manage Existing Positions (Breakeven + Trailing)                 |
//+------------------------------------------------------------------+
void ManagePositions()
{
   // Reset trailing status
   g_trailingActive = false;
   g_currentTrailDistance = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == MagicNumber)
         {
            MoveToBreakeven();
            
            // Apply ATR trailing stop (runs after breakeven)
            if(UseTrailingStop)
               ApplyATRTrailingStop();
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
//| Apply ATR-based Trailing Stop - NEW in v3.0                      |
//+------------------------------------------------------------------+
void ApplyATRTrailingStop()
{
   double currentATR = GetCurrentATR();
   if(currentATR <= 0) return;
   
   // Calculate trail distance based on ATR
   double trailDistance = currentATR * TrailATRMultiplier;
   
   // Apply min/max bounds
   double minTrailPoints = MinTrailStopPips * g_point;
   double maxTrailPoints = MaxTrailStopPips * g_point;
   
   if(trailDistance < minTrailPoints) trailDistance = minTrailPoints;
   if(trailDistance > maxTrailPoints) trailDistance = maxTrailPoints;
   
   double openPrice = positionInfo.PriceOpen();
   double currentSL = positionInfo.StopLoss();
   double currentTP = positionInfo.TakeProfit();
   double activationPoints = TrailActivationPips * g_point;
   
   symbolInfo.RefreshRates();
   
   if(positionInfo.PositionType() == POSITION_TYPE_BUY)
   {
      double currentPrice = symbolInfo.Bid();
      double profit = currentPrice - openPrice;
      
      // Check if we should activate trailing
      if(profit >= activationPoints)
      {
         double newSL = NormalizeDouble(currentPrice - trailDistance, g_digits);
         
         // Only move SL if it would improve position (and beyond breakeven)
         if(newSL > currentSL && newSL > openPrice)
         {
            double newTP = RemoveTPWhenTrailing ? 0 : currentTP;
            if(trade.PositionModify(positionInfo.Ticket(), newSL, newTP))
            {
               g_trailingActive = true;
               g_currentTrailDistance = trailDistance / g_point;
               Print("BUY Trail: SL moved to ", newSL,
                     " (ATR Trail = ", DoubleToString(trailDistance/g_point, 1), " pips)");
            }
         }
         else if(newSL > openPrice)
         {
            // Trail is active but SL hasn't moved
            g_trailingActive = true;
            g_currentTrailDistance = trailDistance / g_point;
         }
      }
   }
   else if(positionInfo.PositionType() == POSITION_TYPE_SELL)
   {
      double currentPrice = symbolInfo.Ask();
      double profit = openPrice - currentPrice;
      
      // Check if we should activate trailing
      if(profit >= activationPoints)
      {
         double newSL = NormalizeDouble(currentPrice + trailDistance, g_digits);
         
         // Only move SL if it would improve position (and beyond breakeven)
         if((newSL < currentSL || currentSL == 0) && newSL < openPrice)
         {
            double newTP = RemoveTPWhenTrailing ? 0 : currentTP;
            if(trade.PositionModify(positionInfo.Ticket(), newSL, newTP))
            {
               g_trailingActive = true;
               g_currentTrailDistance = trailDistance / g_point;
               Print("SELL Trail: SL moved to ", newSL,
                     " (ATR Trail = ", DoubleToString(trailDistance/g_point, 1), " pips)");
            }
         }
         else if(newSL < openPrice)
         {
            // Trail is active but SL hasn't moved
            g_trailingActive = true;
            g_currentTrailDistance = trailDistance / g_point;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check TDI Exit Signal (when TP = 0 and no trailing)              |
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
   string msg = StringFormat("TDI Bounce GBPUSD %s: %s @ %.5f | SL: %.5f | TP: %.5f | Lots: %.2f",
                             orderType, _Symbol, price, sl, tp, lots);
   
   if(EnableAlerts)
      Alert(msg);
   
   if(EnablePushNotification)
      SendNotification(msg);
   
   if(EnableEmailAlert)
      SendMail("TDI Bounce GBPUSD Signal", msg);
}

//+------------------------------------------------------------------+
//| Display Information on Chart                                     |
//+------------------------------------------------------------------+
void DisplayInfo(double price, double ema10, double ema200, double ema800,
                 double green, double red, double yellow, double distance, double atr)
{
   int gmtHour = GetCurrentGMTHour();
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int serverHour = dt.hour;
   
   string session = "Inactive";
   if(IsValidSession())
   {
      session = StringFormat("Active (%02d:00-%02d:00 GMT)", TradingStartHourGMT, TradingEndHourGMT);
   }
   
   string pricePos = (price > ema200) ? "ABOVE" : "BELOW";
   string tdiSignal = (green > yellow) ? "BULLISH (Green > Yellow)" : "BEARISH (Green < Yellow)";
   
   // ATR status
   string atrStatus = "Disabled";
   if(UseATRFilter && ATR_Average > 0)
   {
      double atrPips = atr / g_point;
      double avgPips = ATR_Average / g_point;
      double ratio = atr / ATR_Average;
      atrStatus = StringFormat("%.1f pips (Avg: %.1f, Ratio: %.2f)", atrPips, avgPips, ratio);
      if(ratio > ATR_MaxMultiplier)
         atrStatus += " [FILTERED]";
      else
         atrStatus += " [OK]";
   }
   
   // TDI Zone status
   string zoneStatus = "Disabled";
   if(UseTDIZoneFilter)
   {
      if(yellow >= TDI_ZoneLower && yellow <= TDI_ZoneUpper)
         zoneStatus = StringFormat("%.1f [IN ZONE %.0f-%.0f]", yellow, TDI_ZoneLower, TDI_ZoneUpper);
      else
         zoneStatus = StringFormat("%.1f [OUT OF ZONE %.0f-%.0f]", yellow, TDI_ZoneLower, TDI_ZoneUpper);
   }
   
   // Trailing stop status
   string trailStatus = "Disabled";
   if(UseTrailingStop)
   {
      if(g_trailingActive)
         trailStatus = StringFormat("ACTIVE (%.1f pips)", g_currentTrailDistance);
      else if(CountOpenPositions() > 0)
         trailStatus = StringFormat("Waiting (+%.0f pips)", TrailActivationPips);
      else
         trailStatus = "Ready";
   }
   
   string info = StringFormat(
      "=== TDI Bounce EA GBPUSD v3.0 ===\n" +
      "Symbol: %s | TF: %s\n" +
      "Server Time: %02d:00 (GMT+%d)\n" +
      "GMT Time: %02d:00\n" +
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
      "=== v3.0 FILTERS & FEATURES ===\n" +
      "ATR Filter: %s\n" +
      "TDI Zone: %s\n" +
      "Green-Red Gap: %.2f (min: %.1f)\n" +
      "Trailing Stop: %s\n" +
      "-------------------\n" +
      "Open Positions: %d\n" +
      "Last Skip: %s",
      _Symbol, EnumToString(Period()),
      serverHour, ServerGMTOffset,
      gmtHour,
      session,
      price, ema10, ema200, ema800,
      distance, pricePos,
      green, red, yellow, tdiSignal,
      atrStatus,
      zoneStatus,
      MathAbs(green - red), TDI_GreenRedMinGap,
      trailStatus,
      CountOpenPositions(),
      (lastSkipReason != "") ? lastSkipReason : "None"
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
