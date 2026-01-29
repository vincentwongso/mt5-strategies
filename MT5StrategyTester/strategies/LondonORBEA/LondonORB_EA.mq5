//+------------------------------------------------------------------+
//|                                              LondonORB_EA_v3.mq5 |
//|                         London Opening Range Breakout Strategy   |
//|                            Enhanced with Fakeout Filters         |
//+------------------------------------------------------------------+
#property copyright "Vincent Trading Systems"
#property link      ""
#property version   "3.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input group "=== Range Settings (SERVER TIME) ==="
input int      RangeStartHour     = 4;        // Range Start Hour (Server Time)
input int      RangeStartMinute   = 0;        // Range Start Minute  
input int      RangeEndHour       = 10;       // Range End Hour (Server Time)
input int      RangeEndMinute     = 0;        // Range End Minute
input int      TradeWindowEnd     = 14;       // Latest Entry Hour (prevents late entries)

input group "=== Entry Mode ==="
input bool     UseCandleCloseEntry = true;    // Wait for candle CLOSE outside range (filters fakeouts)
input bool     UseBreakoutRetest   = false;   // Wait for retest of range after breakout
input double   BufferPips          = 3.0;     // Entry Buffer (Pips)

input group "=== Range Filters ==="
input int      MinRangePips       = 15;       // Minimum Range Size (Pips)
input int      MaxRangePips       = 60;       // Maximum Range Size (Pips)
input bool     RequireMomentum    = false;    // Require candle close near range edge

input group "=== Risk Management ==="
input double   RiskPercent        = 1.0;      // Risk Per Trade (%)
input double   MaxDailyDD         = 3.0;      // Max Daily Drawdown (%)
input double   MaxTotalDD         = 10.0;     // Max Total Drawdown (%)

input group "=== Take Profit Settings ==="
input double   RiskRewardRatio    = 1.25;     // Primary TP Risk:Reward (reduced from 1.5)
input bool     UsePartialTP       = true;     // Take partial profits at TP1
input double   PartialTPRatio     = 1.0;      // Partial TP at 1:1 (if enabled)
input double   PartialTPPercent   = 50.0;     // Close this % at partial TP

input group "=== Exit Settings ==="
input int      HardExitHour       = 20;       // Hard Exit Hour (extended from 16:00)
input int      HardExitMinute     = 0;        // Hard Exit Minute
input bool     UseBreakeven       = true;     // Enable Breakeven
input double   BreakevenTrigger   = 0.75;     // Breakeven Trigger (x Risk) - earlier than 1.0
input bool     UseTrailingStop    = true;     // Enable Trailing Stop (after BE)
input double   TrailingStart      = 1.0;      // Start trailing at (x Risk)
input double   TrailingStep       = 10.0;     // Trailing Step (Pips)

input group "=== Day Filters ==="
input bool     TradeMonday        = false;    // Trade on Monday (often ranging)
input bool     TradeFriday        = true;     // Trade on Friday

input group "=== Trade Settings ==="
input int      MagicNumber        = 20240129; // Magic Number
input int      MaxSlippage        = 3;        // Max Slippage (Points)
input string   TradeComment       = "LondonORB_v3"; // Trade Comment

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  positionInfo;
COrderInfo     orderInfo;

// Range variables
double         g_rangeHigh        = 0;
double         g_rangeLow         = 0;
double         g_rangeSize        = 0;
double         g_rangeMidpoint    = 0;
bool           g_rangeCalculated  = false;
bool           g_ordersPlaced     = false;
bool           g_tradeTakenToday  = false;
bool           g_tradingAllowed   = true;
bool           g_partialTPTaken   = false;
int            g_breakoutDirection = 0;  // 1 = bullish, -1 = bearish, 0 = none
datetime       g_lastBarTime      = 0;
datetime       g_currentDay       = 0;
datetime       g_rangeStartTime   = 0;
datetime       g_rangeEndTime     = 0;
datetime       g_hardExitTime     = 0;
datetime       g_tradeWindowEndTime = 0;

// Position tracking
double         g_entryPrice       = 0;
double         g_originalSL       = 0;
double         g_originalTP       = 0;
double         g_originalLots     = 0;

// Risk tracking
double         g_highWaterMark    = 0;
string         g_gvPrefix         = "LondonORB3_";

// Symbol info
double         g_point;
double         g_tickValue;
double         g_tickSize;
double         g_minLot;
double         g_maxLot;
double         g_lotStep;
int            g_digits;
double         g_pipValue;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Validate inputs
   if(RangeStartHour >= RangeEndHour)
   {
      Print("ERROR: Range Start Hour must be less than Range End Hour");
      return(INIT_PARAMETERS_INCORRECT);
   }
   
   // Initialize trade object
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(MaxSlippage);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   trade.SetAsyncMode(false);
   
   // Get symbol info
   g_point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   g_tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   g_minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   g_maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   g_lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   g_digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   // Calculate pip value
   if(g_digits == 3 || g_digits == 5)
      g_pipValue = g_point * 10;
   else
      g_pipValue = g_point;
   
   // Initialize High Water Mark
   if(GlobalVariableCheck(g_gvPrefix + "HWM"))
      g_highWaterMark = GlobalVariableGet(g_gvPrefix + "HWM");
   else
   {
      g_highWaterMark = AccountInfoDouble(ACCOUNT_EQUITY);
      GlobalVariableSet(g_gvPrefix + "HWM", g_highWaterMark);
   }
   
   // Check kill switch
   if(GlobalVariableCheck(g_gvPrefix + "KillSwitch"))
   {
      if(GlobalVariableGet(g_gvPrefix + "KillSwitch") == 1)
      {
         Print("CRITICAL: Kill Switch is active. EA disabled.");
         g_tradingAllowed = false;
      }
   }
   
   ResetDailyVariables();
   
   Print("=================================================");
   Print("LondonORB EA v3.0 - Enhanced Edition");
   Print("Symbol: ", _Symbol, " | Timeframe: ", EnumToString(Period()));
   Print("Entry Mode: ", UseCandleCloseEntry ? "Candle Close Confirmation" : "Pending Orders");
   Print("R:R Target: 1:", DoubleToString(RiskRewardRatio, 2));
   Print("Partial TP: ", UsePartialTP ? "Enabled at 1:" + DoubleToString(PartialTPRatio, 1) : "Disabled");
   Print("=================================================");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
   if(reason == REASON_REMOVE)
      DeleteAllPendingOrders();
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!g_tradingAllowed)
   {
      DisplayStatus("KILL SWITCH ACTIVE");
      return;
   }
   
   CheckNewDay();
   
   if(!CheckRiskLimits())
   {
      CloseAllPositions();
      DeleteAllPendingOrders();
      DisplayStatus("RISK LIMIT BREACHED");
      return;
   }
   
   UpdateHighWaterMark();
   
   // Check day filter
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   
   if(timeStruct.day_of_week == 1 && !TradeMonday)
   {
      DisplayStatus("MONDAY - NO TRADING");
      return;
   }
   if(timeStruct.day_of_week == 5 && !TradeFriday)
   {
      DisplayStatus("FRIDAY - NO TRADING");
      return;
   }
   
   CalculateDailyTimes();
   
   datetime currentTime = TimeCurrent();
   int currentMinutes = timeStruct.hour * 60 + timeStruct.min;
   int rangeStartMinutes = RangeStartHour * 60 + RangeStartMinute;
   int rangeEndMinutes = RangeEndHour * 60 + RangeEndMinute;
   int hardExitMinutes = HardExitHour * 60 + HardExitMinute;
   int tradeWindowEndMinutes = TradeWindowEnd * 60;
   
   //--- PHASE 1: Before Range Start
   if(currentMinutes < rangeStartMinutes)
   {
      DisplayStatus("WAITING - Before range");
      return;
   }
   
   //--- PHASE 2: Range Formation
   if(currentMinutes >= rangeStartMinutes && currentMinutes < rangeEndMinutes)
   {
      if(IsNewBar())
         CalculateRange();
      DisplayStatus("RANGE FORMING");
      return;
   }
   
   //--- PHASE 3: Trading Window
   if(currentMinutes >= rangeEndMinutes && currentMinutes < hardExitMinutes)
   {
      // Finalize range if needed
      if(!g_rangeCalculated)
      {
         FinalizeRange();
         g_rangeCalculated = true;
         
         if(!ValidateRange())
         {
            Print("Range validation failed. No trade today.");
            g_tradeTakenToday = true;
         }
      }
      
      // Entry logic
      if(!g_tradeTakenToday && !HasOpenPosition() && g_rangeCalculated)
      {
         // Check if still within trade window
         if(currentMinutes < tradeWindowEndMinutes)
         {
            if(UseCandleCloseEntry)
               CheckCandleCloseBreakout();
            else if(!g_ordersPlaced)
            {
               PlaceBreakoutOrders();
               g_ordersPlaced = true;
            }
         }
         else
         {
            // Past trade window, delete any pending orders
            if(HasPendingOrders())
            {
               Print("Trade window closed. Deleting pending orders.");
               DeleteAllPendingOrders();
               g_tradeTakenToday = true;
            }
         }
      }
      
      // OCO Logic for pending orders
      if(g_ordersPlaced && !UseCandleCloseEntry)
         CheckOCOLogic();
      
      // Position management
      if(HasOpenPosition())
         ManageOpenPositions();
      
      DisplayStatus("TRADING PHASE");
   }
   
   //--- PHASE 4: Hard Exit
   if(currentMinutes >= hardExitMinutes)
   {
      if(HasOpenPosition() || HasPendingOrders())
      {
         Print("Hard Exit Time. Closing all.");
         CloseAllPositions();
         DeleteAllPendingOrders();
         g_tradeTakenToday = true;
      }
      DisplayStatus("SESSION ENDED");
   }
}

//+------------------------------------------------------------------+
//| Check for candle close breakout (filters fakeouts)               |
//+------------------------------------------------------------------+
void CheckCandleCloseBreakout()
{
   if(!IsNewBar()) return;
   
   // Get the last closed candle
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   if(CopyRates(_Symbol, PERIOD_M15, 1, 1, rates) < 1)
      return;
   
   double buffer = BufferPips * g_pipValue;
   double close = rates[0].close;
   double high = rates[0].high;
   double low = rates[0].low;
   
   // Check for bullish breakout - candle CLOSED above range high
   if(close > g_rangeHigh + buffer)
   {
      // Optional: require momentum (candle closed in upper portion)
      if(RequireMomentum)
      {
         double candleRange = high - low;
         if(candleRange > 0 && (close - low) / candleRange < 0.6)
            return; // Not enough bullish momentum
      }
      
      Print("BULLISH BREAKOUT CONFIRMED - Candle closed at ", close, " above range high ", g_rangeHigh);
      ExecuteBreakoutTrade(ORDER_TYPE_BUY, close);
      g_tradeTakenToday = true;
   }
   // Check for bearish breakout - candle CLOSED below range low
   else if(close < g_rangeLow - buffer)
   {
      if(RequireMomentum)
      {
         double candleRange = high - low;
         if(candleRange > 0 && (high - close) / candleRange < 0.6)
            return; // Not enough bearish momentum
      }
      
      Print("BEARISH BREAKOUT CONFIRMED - Candle closed at ", close, " below range low ", g_rangeLow);
      ExecuteBreakoutTrade(ORDER_TYPE_SELL, close);
      g_tradeTakenToday = true;
   }
}

//+------------------------------------------------------------------+
//| Execute breakout trade with market order                         |
//+------------------------------------------------------------------+
void ExecuteBreakoutTrade(ENUM_ORDER_TYPE orderType, double triggerPrice)
{
   double buffer = BufferPips * g_pipValue;
   double sl, tp, tp1;
   double entryPrice;
   
   if(orderType == ORDER_TYPE_BUY)
   {
      entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      sl = g_rangeLow - buffer;
      double slDistance = entryPrice - sl;
      tp = entryPrice + slDistance * RiskRewardRatio;
      tp1 = entryPrice + slDistance * PartialTPRatio;
   }
   else
   {
      entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl = g_rangeHigh + buffer;
      double slDistance = sl - entryPrice;
      tp = entryPrice - slDistance * RiskRewardRatio;
      tp1 = entryPrice - slDistance * PartialTPRatio;
   }
   
   // Normalize prices
   entryPrice = NormalizeDouble(entryPrice, g_digits);
   sl = NormalizeDouble(sl, g_digits);
   tp = NormalizeDouble(tp, g_digits);
   tp1 = NormalizeDouble(tp1, g_digits);
   
   // Calculate SL in pips
   double slPips = MathAbs(entryPrice - sl) / g_pipValue;
   double lots = CalculateLotSize(slPips);
   
   if(lots <= 0)
   {
      Print("Invalid lot size calculated. Trade skipped.");
      return;
   }
   
   // Store for position management
   g_entryPrice = entryPrice;
   g_originalSL = sl;
   g_originalTP = tp;
   g_originalLots = lots;
   g_partialTPTaken = false;
   
   // Execute trade
   bool success = false;
   if(orderType == ORDER_TYPE_BUY)
      success = trade.Buy(lots, _Symbol, entryPrice, sl, tp, TradeComment);
   else
      success = trade.Sell(lots, _Symbol, entryPrice, sl, tp, TradeComment);
   
   if(success)
   {
      Print(orderType == ORDER_TYPE_BUY ? "BUY" : "SELL", " executed at ", entryPrice);
      Print("SL: ", sl, " | TP: ", tp, " | Lots: ", lots);
      Print("Risk: ", DoubleToString(slPips, 1), " pips | Reward: ", DoubleToString(slPips * RiskRewardRatio, 1), " pips");
   }
   else
      Print("Trade execution failed. Error: ", GetLastError());
}

//+------------------------------------------------------------------+
//| Manage open positions                                            |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!positionInfo.SelectByIndex(i)) continue;
      if(positionInfo.Symbol() != _Symbol || positionInfo.Magic() != MagicNumber) continue;
      
      double openPrice = positionInfo.PriceOpen();
      double currentSL = positionInfo.StopLoss();
      double currentTP = positionInfo.TakeProfit();
      double currentVolume = positionInfo.Volume();
      ulong ticket = positionInfo.Ticket();
      ENUM_POSITION_TYPE posType = positionInfo.PositionType();
      
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double currentPrice = (posType == POSITION_TYPE_BUY) ? bid : ask;
      
      double riskDistance = MathAbs(openPrice - g_originalSL);
      if(riskDistance <= 0) riskDistance = MathAbs(openPrice - currentSL);
      
      //--- Partial TP Logic
      if(UsePartialTP && !g_partialTPTaken && currentVolume >= g_originalLots * 0.9)
      {
         double partialTPLevel;
         if(posType == POSITION_TYPE_BUY)
            partialTPLevel = openPrice + riskDistance * PartialTPRatio;
         else
            partialTPLevel = openPrice - riskDistance * PartialTPRatio;
         
         bool hitPartialTP = (posType == POSITION_TYPE_BUY && bid >= partialTPLevel) ||
                             (posType == POSITION_TYPE_SELL && ask <= partialTPLevel);
         
         if(hitPartialTP)
         {
            double closeVolume = NormalizeDouble(currentVolume * (PartialTPPercent / 100.0), 2);
            closeVolume = MathMax(closeVolume, g_minLot);
            
            if(closeVolume < currentVolume)
            {
               if(trade.PositionClosePartial(ticket, closeVolume))
               {
                  Print("Partial TP taken: ", closeVolume, " lots at 1:", PartialTPRatio);
                  g_partialTPTaken = true;
                  
                  // Move SL to breakeven for remaining position
                  double newSL = (posType == POSITION_TYPE_BUY) ? 
                                 openPrice + g_pipValue : openPrice - g_pipValue;
                  trade.PositionModify(ticket, NormalizeDouble(newSL, g_digits), currentTP);
                  Print("SL moved to breakeven after partial TP");
               }
            }
         }
      }
      
      //--- Breakeven Logic (if partial TP not enabled or already taken)
      if(UseBreakeven && (g_partialTPTaken || !UsePartialTP))
      {
         double beLevel = riskDistance * BreakevenTrigger;
         
         if(posType == POSITION_TYPE_BUY)
         {
            if(bid >= openPrice + beLevel && currentSL < openPrice)
            {
               double newSL = NormalizeDouble(openPrice + g_pipValue, g_digits);
               if(trade.PositionModify(ticket, newSL, currentTP))
                  Print("Breakeven activated at ", newSL);
            }
         }
         else
         {
            if(ask <= openPrice - beLevel && currentSL > openPrice)
            {
               double newSL = NormalizeDouble(openPrice - g_pipValue, g_digits);
               if(trade.PositionModify(ticket, newSL, currentTP))
                  Print("Breakeven activated at ", newSL);
            }
         }
      }
      
      //--- Trailing Stop Logic
      if(UseTrailingStop && currentSL != 0)
      {
         double trailDistance = TrailingStep * g_pipValue;
         double trailTrigger = riskDistance * TrailingStart;
         
         if(posType == POSITION_TYPE_BUY)
         {
            if(currentSL >= openPrice && bid >= openPrice + trailTrigger)
            {
               double newSL = NormalizeDouble(bid - trailDistance, g_digits);
               if(newSL > currentSL + g_pipValue)
               {
                  if(trade.PositionModify(ticket, newSL, currentTP))
                     Print("Trailing stop: ", newSL);
               }
            }
         }
         else
         {
            if(currentSL <= openPrice && ask <= openPrice - trailTrigger)
            {
               double newSL = NormalizeDouble(ask + trailDistance, g_digits);
               if(newSL < currentSL - g_pipValue)
               {
                  if(trade.PositionModify(ticket, newSL, currentTP))
                     Print("Trailing stop: ", newSL);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate daily times                                            |
//+------------------------------------------------------------------+
void CalculateDailyTimes()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   timeStruct.hour = 0;
   timeStruct.min = 0;
   timeStruct.sec = 0;
   datetime midnight = StructToTime(timeStruct);
   
   g_rangeStartTime = midnight + RangeStartHour * 3600 + RangeStartMinute * 60;
   g_rangeEndTime = midnight + RangeEndHour * 3600 + RangeEndMinute * 60;
   g_hardExitTime = midnight + HardExitHour * 3600 + HardExitMinute * 60;
   g_tradeWindowEndTime = midnight + TradeWindowEnd * 3600;
}

//+------------------------------------------------------------------+
//| Check for new day                                                |
//+------------------------------------------------------------------+
void CheckNewDay()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   timeStruct.hour = 0;
   timeStruct.min = 0;
   timeStruct.sec = 0;
   datetime today = StructToTime(timeStruct);
   
   if(today != g_currentDay)
   {
      g_currentDay = today;
      ResetDailyVariables();
      
      string dateStr = TimeToString(TimeCurrent(), TIME_DATE);
      GlobalVariableSet(g_gvPrefix + "DailyEquity_" + dateStr, AccountInfoDouble(ACCOUNT_EQUITY));
      
      Print("========== NEW DAY: ", dateStr, " ==========");
   }
}

//+------------------------------------------------------------------+
//| Reset daily variables                                            |
//+------------------------------------------------------------------+
void ResetDailyVariables()
{
   g_rangeHigh = 0;
   g_rangeLow = DBL_MAX;
   g_rangeSize = 0;
   g_rangeMidpoint = 0;
   g_rangeCalculated = false;
   g_ordersPlaced = false;
   g_tradeTakenToday = false;
   g_partialTPTaken = false;
   g_breakoutDirection = 0;
   g_entryPrice = 0;
   g_originalSL = 0;
   g_originalTP = 0;
   g_originalLots = 0;
   
   if(!GlobalVariableCheck(g_gvPrefix + "KillSwitch") || 
      GlobalVariableGet(g_gvPrefix + "KillSwitch") != 1)
      g_tradingAllowed = true;
}

//+------------------------------------------------------------------+
//| Check risk limits                                                |
//+------------------------------------------------------------------+
bool CheckRiskLimits()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   // Daily DD
   string dateStr = TimeToString(TimeCurrent(), TIME_DATE);
   double dailyStartEquity = GlobalVariableCheck(g_gvPrefix + "DailyEquity_" + dateStr) ?
                             GlobalVariableGet(g_gvPrefix + "DailyEquity_" + dateStr) : currentEquity;
   
   double dailyDD = (dailyStartEquity > 0) ? 
                    ((dailyStartEquity - currentEquity) / dailyStartEquity) * 100.0 : 0;
   
   if(dailyDD >= MaxDailyDD)
   {
      Print("DAILY DD LIMIT BREACHED: ", DoubleToString(dailyDD, 2), "%");
      g_tradingAllowed = false;
      return false;
   }
   
   // Total DD
   if(GlobalVariableCheck(g_gvPrefix + "HWM"))
      g_highWaterMark = GlobalVariableGet(g_gvPrefix + "HWM");
   
   double totalDD = (g_highWaterMark > 0) ?
                    ((g_highWaterMark - currentEquity) / g_highWaterMark) * 100.0 : 0;
   
   if(totalDD >= MaxTotalDD)
   {
      Print("TOTAL DD LIMIT BREACHED: ", DoubleToString(totalDD, 2), "%");
      GlobalVariableSet(g_gvPrefix + "KillSwitch", 1);
      g_tradingAllowed = false;
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Update High Water Mark                                           |
//+------------------------------------------------------------------+
void UpdateHighWaterMark()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(currentEquity > g_highWaterMark)
   {
      g_highWaterMark = currentEquity;
      GlobalVariableSet(g_gvPrefix + "HWM", g_highWaterMark);
   }
}

//+------------------------------------------------------------------+
//| Check for new bar                                                |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(_Symbol, PERIOD_M15, 0);
   if(currentBarTime != g_lastBarTime)
   {
      g_lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Calculate range                                                  |
//+------------------------------------------------------------------+
void CalculateRange()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   if(CopyRates(_Symbol, PERIOD_M15, 0, 50, rates) <= 0) return;
   
   g_rangeHigh = 0;
   g_rangeLow = DBL_MAX;
   
   for(int i = 0; i < ArraySize(rates); i++)
   {
      if(rates[i].time >= g_rangeStartTime && rates[i].time < g_rangeEndTime)
      {
         if(rates[i].high > g_rangeHigh) g_rangeHigh = rates[i].high;
         if(rates[i].low < g_rangeLow) g_rangeLow = rates[i].low;
      }
   }
   
   if(g_rangeHigh > 0 && g_rangeLow < DBL_MAX)
   {
      g_rangeSize = (g_rangeHigh - g_rangeLow) / g_pipValue;
      g_rangeMidpoint = (g_rangeHigh + g_rangeLow) / 2.0;
   }
}

//+------------------------------------------------------------------+
//| Finalize range                                                   |
//+------------------------------------------------------------------+
void FinalizeRange()
{
   CalculateRange();
   
   Print("======= RANGE FINALIZED =======");
   Print("High: ", DoubleToString(g_rangeHigh, g_digits));
   Print("Low: ", DoubleToString(g_rangeLow, g_digits));
   Print("Size: ", DoubleToString(g_rangeSize, 1), " pips");
   Print("Midpoint: ", DoubleToString(g_rangeMidpoint, g_digits));
}

//+------------------------------------------------------------------+
//| Validate range                                                   |
//+------------------------------------------------------------------+
bool ValidateRange()
{
   if(g_rangeHigh <= 0 || g_rangeLow <= 0 || g_rangeLow >= g_rangeHigh)
   {
      Print("Invalid range values");
      return false;
   }
   
   if(g_rangeSize < MinRangePips)
   {
      Print("Range too small: ", DoubleToString(g_rangeSize, 1), " pips");
      return false;
   }
   
   if(g_rangeSize > MaxRangePips)
   {
      Print("Range too large: ", DoubleToString(g_rangeSize, 1), " pips");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Calculate lot size                                               |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPips)
{
   if(slPips <= 0) return 0;
   
   double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmount = accountEquity * (RiskPercent / 100.0);
   double pipValuePerLot = g_tickValue / g_tickSize * g_pipValue;
   
   if(pipValuePerLot <= 0) return 0;
   
   double lotSize = riskAmount / (slPips * pipValuePerLot);
   lotSize = MathFloor(lotSize / g_lotStep) * g_lotStep;
   
   if(lotSize < g_minLot) return 0;
   if(lotSize > g_maxLot) lotSize = g_maxLot;
   
   return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
//| Place breakout orders (pending stop orders mode)                 |
//+------------------------------------------------------------------+
void PlaceBreakoutOrders()
{
   double buffer = BufferPips * g_pipValue;
   
   double buyEntry = NormalizeDouble(g_rangeHigh + buffer, g_digits);
   double sellEntry = NormalizeDouble(g_rangeLow - buffer, g_digits);
   double buySL = NormalizeDouble(g_rangeLow - buffer, g_digits);
   double sellSL = NormalizeDouble(g_rangeHigh + buffer, g_digits);
   
   double buySLPips = (buyEntry - buySL) / g_pipValue;
   double sellSLPips = (sellSL - sellEntry) / g_pipValue;
   
   double buyTP = NormalizeDouble(buyEntry + (buyEntry - buySL) * RiskRewardRatio, g_digits);
   double sellTP = NormalizeDouble(sellEntry - (sellSL - sellEntry) * RiskRewardRatio, g_digits);
   
   double buyLots = CalculateLotSize(buySLPips);
   double sellLots = CalculateLotSize(sellSLPips);
   
   datetime expiration = g_hardExitTime;
   
   if(buyLots > 0)
   {
      trade.BuyStop(buyLots, buyEntry, _Symbol, buySL, buyTP, ORDER_TIME_SPECIFIED, expiration, TradeComment + "_BUY");
      g_originalLots = buyLots;
   }
   
   if(sellLots > 0)
   {
      trade.SellStop(sellLots, sellEntry, _Symbol, sellSL, sellTP, ORDER_TIME_SPECIFIED, expiration, TradeComment + "_SELL");
      g_originalLots = sellLots;
   }
   
   Print("Pending orders placed");
}

//+------------------------------------------------------------------+
//| Check OCO logic                                                  |
//+------------------------------------------------------------------+
void CheckOCOLogic()
{
   if(!HasOpenPosition()) return;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!positionInfo.SelectByIndex(i)) continue;
      if(positionInfo.Symbol() != _Symbol || positionInfo.Magic() != MagicNumber) continue;
      
      // Delete opposite pending orders
      for(int j = OrdersTotal() - 1; j >= 0; j--)
      {
         if(!orderInfo.SelectByIndex(j)) continue;
         if(orderInfo.Symbol() != _Symbol || orderInfo.Magic() != MagicNumber) continue;
         
         trade.OrderDelete(orderInfo.Ticket());
         Print("OCO: Deleted pending order");
      }
      
      // Store entry info
      g_entryPrice = positionInfo.PriceOpen();
      g_originalSL = positionInfo.StopLoss();
      g_originalTP = positionInfo.TakeProfit();
      g_tradeTakenToday = true;
      break;
   }
}

//+------------------------------------------------------------------+
//| Check for open positions                                         |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == MagicNumber)
            return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check for pending orders                                         |
//+------------------------------------------------------------------+
bool HasPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(orderInfo.SelectByIndex(i))
         if(orderInfo.Symbol() == _Symbol && orderInfo.Magic() == MagicNumber)
            return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Close all positions                                              |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == MagicNumber)
            trade.PositionClose(positionInfo.Ticket());
   }
}

//+------------------------------------------------------------------+
//| Delete all pending orders                                        |
//+------------------------------------------------------------------+
void DeleteAllPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(orderInfo.SelectByIndex(i))
         if(orderInfo.Symbol() == _Symbol && orderInfo.Magic() == MagicNumber)
            trade.OrderDelete(orderInfo.Ticket());
   }
}

//+------------------------------------------------------------------+
//| Display status                                                   |
//+------------------------------------------------------------------+
void DisplayStatus(string phase = "")
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyDD = 0, totalDD = 0;
   
   string dateStr = TimeToString(TimeCurrent(), TIME_DATE);
   if(GlobalVariableCheck(g_gvPrefix + "DailyEquity_" + dateStr))
   {
      double dailyStart = GlobalVariableGet(g_gvPrefix + "DailyEquity_" + dateStr);
      if(dailyStart > 0) dailyDD = ((dailyStart - equity) / dailyStart) * 100.0;
   }
   
   if(g_highWaterMark > 0)
      totalDD = ((g_highWaterMark - equity) / g_highWaterMark) * 100.0;
   
   string status = "";
   status += "══════ LONDON ORB v3.0 ══════\n";
   status += "Phase: " + phase + "\n";
   status += "─────────────────────────────\n";
   status += "Entry Mode: " + (UseCandleCloseEntry ? "Candle Close" : "Pending Orders") + "\n";
   status += "Range: " + DoubleToString(g_rangeSize, 1) + " pips\n";
   status += "High: " + DoubleToString(g_rangeHigh, g_digits) + "\n";
   status += "Low: " + DoubleToString(g_rangeLow == DBL_MAX ? 0 : g_rangeLow, g_digits) + "\n";
   status += "─────────────────────────────\n";
   status += "Trade Taken: " + (g_tradeTakenToday ? "Yes" : "No") + "\n";
   status += "Partial TP: " + (g_partialTPTaken ? "Yes" : "No") + "\n";
   status += "─────────────────────────────\n";
   status += "Daily DD: " + DoubleToString(dailyDD, 2) + "%\n";
   status += "Total DD: " + DoubleToString(totalDD, 2) + "%\n";
   status += "═════════════════════════════";
   
   Comment(status);
}

//+------------------------------------------------------------------+
//| Reset kill switch                                                |
//+------------------------------------------------------------------+
void ResetKillSwitch()
{
   if(GlobalVariableCheck(g_gvPrefix + "KillSwitch"))
      GlobalVariableDel(g_gvPrefix + "KillSwitch");
   g_tradingAllowed = true;
   Print("Kill Switch reset.");
}
//+------------------------------------------------------------------+
