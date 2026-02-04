//+------------------------------------------------------------------+
//|                                   LondonBreakout_PropFirm_EA.mq5 |
//|                      Asian Range London Breakout - Prop Edition  |
//|                     Optimized for Funded Account Requirements    |
//+------------------------------------------------------------------+
#property copyright "Vincent Trading Systems"
#property link      ""
#property version   "2.00"
#property description "London Breakout Strategy optimized for prop firm trading"
#property description "Uses Asian session range with London session breakout"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//+------------------------------------------------------------------+
//| Input Parameters - Time Settings (GMT)                           |
//+------------------------------------------------------------------+
input group "=== Session Times (Broker Server Time) ==="
input int      AsianStartHour     = 0;        // Asian Range Start Hour
input int      AsianStartMinute   = 0;        // Asian Range Start Minute
input int      AsianEndHour       = 7;        // Asian Range End Hour (London Open)
input int      AsianEndMinute     = 0;        // Asian Range End Minute
input int      TradeWindowEndHour = 10;       // Stop placing new orders after (Hour) - Reduced window
input int      HardExitHour       = 15;       // Close all positions by (Hour) - Earlier exit
input int      HardExitMinute     = 0;        // Hard Exit Minute

input group "=== Range Filters ==="
input int      MinRangePips       = 20;       // Minimum Asian Range (Pips) - Increased for better setups
input int      MaxRangePips       = 45;       // Maximum Asian Range (Pips) - Reduced to avoid choppy markets
input double   BufferPips         = 3.0;      // Entry Buffer above/below range (Pips) - Reduced for earlier entries

input group "=== Market Structure Filters ==="
input bool     UseATRFilter       = true;     // Use ATR filter for volatility
input int      ATRPeriod          = 14;       // ATR Period
input double   ATRMultiplier      = 1.2;      // Minimum ATR multiplier for range
input bool     UseTrendFilter     = true;     // Use trend filter
input int      TrendMAPeriod      = 50;       // Trend MA Period
input bool     UseVolumeFilter    = true;     // Use volume filter
input double   MinVolumeRatio     = 1.1;      // Minimum volume ratio vs average

input group "=== Prop Firm Risk Management ==="
input double   RiskPercent        = 0.8;      // Risk Per Trade (%) - Slightly increased for better R:R
input double   MaxDailyDD         = 2.5;      // Max Daily Drawdown (%) - More conservative
input double   MaxTotalDD         = 6.0;      // Max Total Drawdown (%) - More conservative
input int      MaxTradesPerDay    = 3;        // Maximum trades per day - Increased for more opportunities

input group "=== Take Profit Settings ==="
input bool     UseScaledExit      = true;     // Use scaled exit (30% at TP1, 40% at TP2, trail rest)
input int      TP1_Pips           = 20;       // First Take Profit (Pips) - Reduced for quicker profits
input int      TP2_Pips           = 35;       // Second Take Profit (Pips)
input double   TP3_RiskMultiple   = 2.5;      // Final TP as multiple of risk (R:R)
input bool     UseTrailingStop    = true;     // Trail stop after TP2
input int      TrailingStopPips   = 12;       // Trailing Stop Distance (Pips)
input int      TrailingStartPips  = 25;       // Start trailing after X pips profit

input group "=== Stop Loss Management ==="
input bool     UseBreakevenStop   = true;     // Move SL to breakeven
input int      BreakevenTrigger   = 15;       // Move to BE after X pips profit
input int      BreakevenBuffer    = 2;        // BE buffer in pips

input group "=== Day Filters ==="
input bool     TradeMonday        = false;    // Trade on Monday - Often choppy
input bool     TradeTuesday       = true;     // Trade on Tuesday
input bool     TradeWednesday     = true;     // Trade on Wednesday
input bool     TradeThursday      = true;     // Trade on Thursday
input bool     TradeFriday        = false;    // Trade on Friday - Often unpredictable

input group "=== Trade Settings ==="
input int      MagicNumber        = 20250130; // Magic Number
input int      MaxSlippage        = 3;        // Max Slippage (Points)
input string   TradeComment       = "LondonBrkout"; // Trade Comment

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  positionInfo;
COrderInfo     orderInfo;

// Range variables
double         g_asianHigh        = 0;
double         g_asianLow         = 0;
double         g_rangeSize        = 0;
bool           g_rangeCalculated  = false;
bool           g_ordersPlaced     = false;
bool           g_tradeTakenToday  = false;
int            g_tradesToday      = 0;
bool           g_tradingAllowed   = true;
bool           g_partialTP1Taken  = false;
bool           g_partialTP2Taken  = false;
bool           g_breakevenMoved   = false;

// Time tracking
datetime       g_currentDay       = 0;
datetime       g_asianStartTime   = 0;
datetime       g_asianEndTime     = 0;
datetime       g_tradeWindowEnd   = 0;
datetime       g_hardExitTime     = 0;

// Position tracking
double         g_entryPrice       = 0;
double         g_originalSL       = 0;
double         g_originalTP       = 0;
double         g_originalLots     = 0;
ulong          g_positionTicket   = 0;

// Prop firm tracking
double         g_startingBalance  = 0;
double         g_dailyStartEquity = 0;
double         g_highWaterMark    = 0;
string         g_gvPrefix         = "LB_Prop_";

// Symbol info
double         g_point;
double         g_tickValue;
double         g_tickSize;
double         g_minLot;
double         g_maxLot;
double         g_lotStep;
int            g_digits;
double         g_pipValue;

// Market structure variables
double         g_currentATR       = 0;
double         g_trendMA          = 0;
double         g_avgVolume        = 0;
bool           g_isBullishTrend   = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Validate inputs
   if(AsianStartHour >= AsianEndHour)
   {
      Print("ERROR: Asian Start Hour must be before Asian End Hour");
      return(INIT_PARAMETERS_INCORRECT);
   }
   
   if(MaxDailyDD >= 5.0)
      Print("WARNING: MaxDailyDD set at ", MaxDailyDD, "% - prop firms typically allow 5%");
   
   if(MaxTotalDD >= 10.0)
      Print("WARNING: MaxTotalDD set at ", MaxTotalDD, "% - prop firms typically allow 10%");
   
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
   
   // Calculate pip value (5-digit vs 4-digit brokers)
   if(g_digits == 3 || g_digits == 5)
      g_pipValue = g_point * 10;
   else
      g_pipValue = g_point;
   
   // Initialize starting balance (for total DD calculation)
   if(GlobalVariableCheck(g_gvPrefix + "StartBalance"))
      g_startingBalance = GlobalVariableGet(g_gvPrefix + "StartBalance");
   else
   {
      g_startingBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      GlobalVariableSet(g_gvPrefix + "StartBalance", g_startingBalance);
   }
   
   // Initialize high water mark
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
         Print("CRITICAL: Kill Switch is active from previous session. EA disabled.");
         Print("To reset, delete Global Variable: ", g_gvPrefix, "KillSwitch");
         g_tradingAllowed = false;
      }
   }
   
   ResetDailyVariables();
   
   Print("==========================================================");
   Print("London Breakout EA - Prop Firm Edition v2.0");
   Print("==========================================================");
   Print("Symbol: ", _Symbol, " | Timeframe: ", EnumToString(Period()));
   Print("Asian Range: ", AsianStartHour, ":00 - ", AsianEndHour, ":00");
   Print("Risk Per Trade: ", RiskPercent, "% | Max Daily DD: ", MaxDailyDD, "%");
   Print("Starting Balance: $", DoubleToString(g_startingBalance, 2));
   Print("Market Filters: ATR=", UseATRFilter, " Trend=", UseTrendFilter, " Volume=", UseVolumeFilter);
   Print("==========================================================");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
   ObjectsDeleteAll(0, "LB_");
   
   if(reason == REASON_REMOVE)
   {
      DeleteAllPendingOrders();
      Print("EA removed. Pending orders deleted.");
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if trading is allowed
   if(!g_tradingAllowed)
   {
      DisplayStatus("KILL SWITCH ACTIVE - Check Global Variables");
      return;
   }
   
   // Check for new day
   CheckNewDay();
   
   // Check prop firm risk limits
   if(!CheckPropFirmLimits())
   {
      CloseAllPositions("Risk limit breach");
      DeleteAllPendingOrders();
      DisplayStatus("RISK LIMIT BREACHED - Trading stopped");
      return;
   }
   
   // Update high water mark
   UpdateHighWaterMark();
   
   // Check day filter
   if(!IsTradingDay())
   {
      DisplayStatus("NON-TRADING DAY");
      return;
   }
   
   // Calculate session times for today
   CalculateSessionTimes();
   
   datetime currentTime = TimeCurrent();
   
   //--- PHASE 1: Before Asian Session
   if(currentTime < g_asianStartTime)
   {
      DisplayStatus("WAITING - Before Asian session");
      return;
   }
   
   //--- PHASE 2: Asian Session (Range Formation)
   if(currentTime >= g_asianStartTime && currentTime < g_asianEndTime)
   {
      CalculateAsianRange();
      DisplayStatus("ASIAN SESSION - Range forming");
      return;
   }
   
   //--- PHASE 3: London Session (Trading Window)
   if(currentTime >= g_asianEndTime && currentTime < g_hardExitTime)
   {
      // Finalize range at London open
      if(!g_rangeCalculated)
      {
         FinalizeAsianRange();
         g_rangeCalculated = true;
         
         // Calculate market structure indicators
         CalculateMarketStructure();
         
         // Validate range and market conditions
         if(!ValidateRange() || !ValidateMarketConditions())
         {
            Print("Range or market validation failed. No trade today.");
            g_tradeTakenToday = true;
         }
         else
         {
            DrawRangeLines();
         }
      }
      
      // Place orders if valid setup
      if(!g_ordersPlaced && !g_tradeTakenToday && g_rangeCalculated && 
         currentTime < g_tradeWindowEnd && g_tradesToday < MaxTradesPerDay)
      {
         PlaceBreakoutOrders();
         g_ordersPlaced = true;
      }
      
      // Check OCO logic (cancel opposite order when one fills)
      if(g_ordersPlaced && !g_tradeTakenToday)
         CheckOCOLogic();
      
      // Manage open positions
      if(HasOpenPosition())
         ManageOpenPosition();
      
      // Cancel unfilled orders after trade window
      if(currentTime >= g_tradeWindowEnd && HasPendingOrders() && !HasOpenPosition())
      {
         Print("Trade window closed. Cancelling pending orders.");
         DeleteAllPendingOrders();
         g_tradeTakenToday = true;
      }
      
      DisplayStatus("LONDON SESSION - Trading active");
   }
   
   //--- PHASE 4: Hard Exit Time
   if(currentTime >= g_hardExitTime)
   {
      if(HasOpenPosition() || HasPendingOrders())
      {
         Print("Hard Exit Time reached. Closing all positions.");
         CloseAllPositions("Hard exit time");
         DeleteAllPendingOrders();
         g_tradeTakenToday = true;
      }
      DisplayStatus("SESSION ENDED - No overnight positions");
   }
}

//+------------------------------------------------------------------+
//| Calculate market structure indicators                             |
//+------------------------------------------------------------------+
void CalculateMarketStructure()
{
   // Calculate ATR
   if(UseATRFilter)
   {
      double atrArray[];
      ArraySetAsSeries(atrArray, true);
      int atrHandle = iATR(_Symbol, PERIOD_H1, ATRPeriod);
      if(CopyBuffer(atrHandle, 0, 0, 1, atrArray) > 0)
         g_currentATR = atrArray[0];
      IndicatorRelease(atrHandle);
   }
   
   // Calculate trend MA
   if(UseTrendFilter)
   {
      double maArray[];
      ArraySetAsSeries(maArray, true);
      int maHandle = iMA(_Symbol, PERIOD_H1, TrendMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(CopyBuffer(maHandle, 0, 0, 1, maArray) > 0)
      {
         g_trendMA = maArray[0];
         double currentPrice = (SymbolInfoDouble(_Symbol, SYMBOL_BID) + SymbolInfoDouble(_Symbol, SYMBOL_ASK)) / 2;
         g_isBullishTrend = currentPrice > g_trendMA;
      }
      IndicatorRelease(maHandle);
   }
   
   // Calculate average volume
   if(UseVolumeFilter)
   {
      long volumeArray[];
      ArraySetAsSeries(volumeArray, true);
      if(CopyTickVolume(_Symbol, PERIOD_H1, 0, 20, volumeArray) > 0)
      {
         long totalVolume = 0;
         for(int i = 1; i < ArraySize(volumeArray); i++) // Skip current bar
            totalVolume += volumeArray[i];
         g_avgVolume = (double)totalVolume / (ArraySize(volumeArray) - 1);
      }
   }
}

//+------------------------------------------------------------------+
//| Validate market conditions                                       |
//+------------------------------------------------------------------+
bool ValidateMarketConditions()
{
   // ATR Filter - ensure sufficient volatility
   if(UseATRFilter && g_currentATR > 0)
   {
      double minATRRange = g_currentATR * ATRMultiplier;
      double rangeInPrice = g_rangeSize * g_pipValue;
      if(rangeInPrice < minATRRange)
      {
         Print("ATR Filter failed: Range ", DoubleToString(rangeInPrice/g_pipValue, 1), 
               " pips < Required ", DoubleToString(minATRRange/g_pipValue, 1), " pips");
         return false;
      }
   }
   
   // Volume Filter - ensure above average volume
   if(UseVolumeFilter && g_avgVolume > 0)
   {
      long currentVolume[];
      ArraySetAsSeries(currentVolume, true);
      if(CopyTickVolume(_Symbol, PERIOD_H1, 0, 1, currentVolume) > 0)
      {
         if(currentVolume[0] < g_avgVolume * MinVolumeRatio)
         {
            Print("Volume Filter failed: Current volume below ", MinVolumeRatio, "x average");
            return false;
         }
      }
   }
   
   Print("Market conditions validated successfully");
   return true;
}

//+------------------------------------------------------------------+
//| Check prop firm risk limits                                       |
//+------------------------------------------------------------------+
bool CheckPropFirmLimits()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   //--- Daily Drawdown Check
   double dailyDD = 0;
   if(g_dailyStartEquity > 0)
      dailyDD = ((g_dailyStartEquity - currentEquity) / g_dailyStartEquity) * 100.0;
   
   if(dailyDD >= MaxDailyDD)
   {
      Print("=== DAILY DRAWDOWN LIMIT HIT ===");
      Print("Daily DD: ", DoubleToString(dailyDD, 2), "% (Limit: ", MaxDailyDD, "%)");
      Print("Trading stopped for today to protect account.");
      g_tradingAllowed = false;
      return false;
   }
   
   //--- Total Drawdown Check (from starting balance)
   double totalDD = 0;
   if(g_startingBalance > 0)
      totalDD = ((g_startingBalance - currentEquity) / g_startingBalance) * 100.0;
   
   if(totalDD >= MaxTotalDD)
   {
      Print("=== TOTAL DRAWDOWN LIMIT HIT ===");
      Print("Total DD: ", DoubleToString(totalDD, 2), "% (Limit: ", MaxTotalDD, "%)");
      Print("KILL SWITCH ACTIVATED - Manual reset required.");
      GlobalVariableSet(g_gvPrefix + "KillSwitch", 1);
      g_tradingAllowed = false;
      return false;
   }
   
   //--- Warning at 80% of limits
   if(dailyDD >= MaxDailyDD * 0.8)
      Print("WARNING: Daily DD at ", DoubleToString(dailyDD, 2), "% - approaching limit");
   
   if(totalDD >= MaxTotalDD * 0.8)
      Print("WARNING: Total DD at ", DoubleToString(totalDD, 2), "% - approaching limit");
   
   return true;
}

//+------------------------------------------------------------------+
//| Calculate session times                                           |
//+------------------------------------------------------------------+
void CalculateSessionTimes()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   timeStruct.hour = 0;
   timeStruct.min = 0;
   timeStruct.sec = 0;
   datetime midnight = StructToTime(timeStruct);
   
   g_asianStartTime = midnight + AsianStartHour * 3600 + AsianStartMinute * 60;
   g_asianEndTime = midnight + AsianEndHour * 3600 + AsianEndMinute * 60;
   g_tradeWindowEnd = midnight + TradeWindowEndHour * 3600;
   g_hardExitTime = midnight + HardExitHour * 3600 + HardExitMinute * 60;
}

//+------------------------------------------------------------------+
//| Check if today is a trading day                                  |
//+------------------------------------------------------------------+
bool IsTradingDay()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   
   switch(timeStruct.day_of_week)
   {
      case 0: return false;  // Sunday
      case 1: return TradeMonday;
      case 2: return TradeTuesday;
      case 3: return TradeWednesday;
      case 4: return TradeThursday;
      case 5: return TradeFriday;
      case 6: return false;  // Saturday
   }
   return false;
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
      
      // Store daily start equity
      g_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      string dateStr = TimeToString(TimeCurrent(), TIME_DATE);
      GlobalVariableSet(g_gvPrefix + "DailyEquity_" + dateStr, g_dailyStartEquity);
      
      // Reset kill switch if not triggered by total DD
      if(!GlobalVariableCheck(g_gvPrefix + "KillSwitch") || 
         GlobalVariableGet(g_gvPrefix + "KillSwitch") != 1)
         g_tradingAllowed = true;
      
      Print("========== NEW TRADING DAY: ", dateStr, " ==========");
      Print("Daily Start Equity: $", DoubleToString(g_dailyStartEquity, 2));
   }
}

//+------------------------------------------------------------------+
//| Reset daily variables                                            |
//+------------------------------------------------------------------+
void ResetDailyVariables()
{
   g_asianHigh = 0;
   g_asianLow = DBL_MAX;
   g_rangeSize = 0;
   g_rangeCalculated = false;
   g_ordersPlaced = false;
   g_tradeTakenToday = false;
   g_tradesToday = 0;
   g_partialTP1Taken = false;
   g_partialTP2Taken = false;
   g_breakevenMoved = false;
   g_entryPrice = 0;
   g_originalSL = 0;
   g_originalTP = 0;
   g_originalLots = 0;
   g_positionTicket = 0;
   
   // Clean up previous day's chart objects
   ObjectsDeleteAll(0, "LB_");
}

//+------------------------------------------------------------------+
//| Calculate Asian session range                                     |
//+------------------------------------------------------------------+
void CalculateAsianRange()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   // Get bars since Asian session start
   int barsToCheck = Bars(_Symbol, PERIOD_M15, g_asianStartTime, TimeCurrent());
   if(barsToCheck <= 0) return;
   
   if(CopyRates(_Symbol, PERIOD_M15, 0, barsToCheck + 5, rates) <= 0) return;
   
   g_asianHigh = 0;
   g_asianLow = DBL_MAX;
   
   for(int i = 0; i < ArraySize(rates); i++)
   {
      if(rates[i].time >= g_asianStartTime && rates[i].time < g_asianEndTime)
      {
         if(rates[i].high > g_asianHigh) g_asianHigh = rates[i].high;
         if(rates[i].low < g_asianLow) g_asianLow = rates[i].low;
      }
   }
   
   if(g_asianHigh > 0 && g_asianLow < DBL_MAX)
      g_rangeSize = (g_asianHigh - g_asianLow) / g_pipValue;
}

//+------------------------------------------------------------------+
//| Finalize Asian range at London open                              |
//+------------------------------------------------------------------+
void FinalizeAsianRange()
{
   CalculateAsianRange();
   
   Print("======= ASIAN RANGE FINALIZED =======");
   Print("High: ", DoubleToString(g_asianHigh, g_digits));
   Print("Low: ", DoubleToString(g_asianLow, g_digits));
   Print("Size: ", DoubleToString(g_rangeSize, 1), " pips");
}

//+------------------------------------------------------------------+
//| Validate range meets criteria                                    |
//+------------------------------------------------------------------+
bool ValidateRange()
{
   if(g_asianHigh <= 0 || g_asianLow <= 0 || g_asianLow >= g_asianHigh)
   {
      Print("Invalid range values");
      return false;
   }
   
   if(g_rangeSize < MinRangePips)
   {
      Print("Range too small: ", DoubleToString(g_rangeSize, 1), " pips (min: ", MinRangePips, ")");
      return false;
   }
   
   if(g_rangeSize > MaxRangePips)
   {
      Print("Range too large: ", DoubleToString(g_rangeSize, 1), " pips (max: ", MaxRangePips, ")");
      return false;
   }
   
   Print("Range validated: ", DoubleToString(g_rangeSize, 1), " pips");
   return true;
}

//+------------------------------------------------------------------+
//| Place breakout orders                                            |
//+------------------------------------------------------------------+
void PlaceBreakoutOrders()
{
   double buffer = BufferPips * g_pipValue;
   
   // Calculate entry levels
   double buyEntry = NormalizeDouble(g_asianHigh + buffer, g_digits);
   double sellEntry = NormalizeDouble(g_asianLow - buffer, g_digits);
   
   // Stop loss is opposite side of range with buffer
   double buySL = NormalizeDouble(g_asianLow - buffer, g_digits);
   double sellSL = NormalizeDouble(g_asianHigh + buffer, g_digits);
   
   // Calculate SL distance in pips
   double buySLPips = (buyEntry - buySL) / g_pipValue;
   double sellSLPips = (sellSL - sellEntry) / g_pipValue;
   
   // Calculate TP levels - using TP1 for initial order
   double buyTP = NormalizeDouble(buyEntry + TP1_Pips * g_pipValue, g_digits);
   double sellTP = NormalizeDouble(sellEntry - TP1_Pips * g_pipValue, g_digits);
   
   // Calculate lot sizes
   double buyLots = CalculateLotSize(buySLPips);
   double sellLots = CalculateLotSize(sellSLPips);
   
   if(buyLots <= 0 || sellLots <= 0)
   {
      Print("Invalid lot size. Cannot place orders.");
      return;
   }
   
   // Set expiration to hard exit time
   datetime expiration = g_hardExitTime;
   
   // Only place order in trend direction if trend filter is enabled
   bool placeBuy = true, placeSell = true;
   if(UseTrendFilter)
   {
      placeBuy = g_isBullishTrend;
      placeSell = !g_isBullishTrend;
      Print("Trend Filter: ", g_isBullishTrend ? "Bullish - Buy only" : "Bearish - Sell only");
   }
   
   // Place Buy Stop
   if(placeBuy && trade.BuyStop(buyLots, buyEntry, _Symbol, buySL, buyTP, ORDER_TIME_SPECIFIED, expiration, TradeComment + "_BUY"))
   {
      Print("Buy Stop placed: Entry=", buyEntry, " SL=", buySL, " TP=", buyTP, " Lots=", buyLots);
      g_originalLots = buyLots;
   }
   else if(placeBuy)
      Print("Failed to place Buy Stop. Error: ", GetLastError());
   
   // Place Sell Stop
   if(placeSell && trade.SellStop(sellLots, sellEntry, _Symbol, sellSL, sellTP, ORDER_TIME_SPECIFIED, expiration, TradeComment + "_SELL"))
   {
      Print("Sell Stop placed: Entry=", sellEntry, " SL=", sellSL, " TP=", sellTP, " Lots=", sellLots);
      g_originalLots = sellLots;
   }
   else if(placeSell)
      Print("Failed to place Sell Stop. Error: ", GetLastError());
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                 |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPips)
{
   if(slPips <= 0) return 0;
   
   double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmount = accountEquity * (RiskPercent / 100.0);
   
   // Pip value per standard lot
   double pipValuePerLot = g_tickValue / g_tickSize * g_pipValue;
   if(pipValuePerLot <= 0) return 0;
   
   double lotSize = riskAmount / (slPips * pipValuePerLot);
   
   // Round down to lot step
   lotSize = MathFloor(lotSize / g_lotStep) * g_lotStep;
   
   // Apply limits
   if(lotSize < g_minLot) return 0;
   if(lotSize > g_maxLot) lotSize = g_maxLot;
   
   return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
//| Check OCO (One Cancels Other) logic                              |
//+------------------------------------------------------------------+
void CheckOCOLogic()
{
   // If we have an open position, cancel all pending orders
   if(!HasOpenPosition()) return;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!positionInfo.SelectByIndex(i)) continue;
      if(positionInfo.Symbol() != _Symbol || positionInfo.Magic() != MagicNumber) continue;
      
      // Found our position - delete all pending orders
      DeleteAllPendingOrders();
      
      // Store position details
      g_entryPrice = positionInfo.PriceOpen();
      g_originalSL = positionInfo.StopLoss();
      g_originalTP = positionInfo.TakeProfit();
      g_positionTicket = positionInfo.Ticket();
      g_tradeTakenToday = true;
      g_tradesToday++;
      
      Print("Position opened. Entry: ", g_entryPrice, " Opposite order cancelled (OCO).");
      break;
   }
}

//+------------------------------------------------------------------+
//| Manage open position                                             |
//+------------------------------------------------------------------+
void ManageOpenPosition()
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
      
      // Calculate current profit in pips
      double profitPips = 0;
      if(posType == POSITION_TYPE_BUY)
         profitPips = (bid - openPrice) / g_pipValue;
      else
         profitPips = (openPrice - ask) / g_pipValue;
      
      //--- Move to breakeven
      if(UseBreakevenStop && !g_breakevenMoved && profitPips >= BreakevenTrigger)
      {
         double newSL = 0;
         if(posType == POSITION_TYPE_BUY)
            newSL = NormalizeDouble(openPrice + BreakevenBuffer * g_pipValue, g_digits);
         else
            newSL = NormalizeDouble(openPrice - BreakevenBuffer * g_pipValue, g_digits);
         
         if(trade.PositionModify(ticket, newSL, currentTP))
         {
            Print("Stop moved to breakeven + ", BreakevenBuffer, " pips");
            g_breakevenMoved = true;
         }
      }
      
      //--- Scaled Exit: Take partial profit at TP1 (30%)
      if(UseScaledExit && !g_partialTP1Taken && profitPips >= TP1_Pips)
      {
         double closeVolume = NormalizeDouble(g_originalLots * 0.3, 2);
         closeVolume = MathMax(closeVolume, g_minLot);
         
         if(closeVolume < currentVolume)
         {
            if(trade.PositionClosePartial(ticket, closeVolume))
            {
               Print("Partial TP1 taken: ", closeVolume, " lots (30%) at ", TP1_Pips, " pips");
               g_partialTP1Taken = true;
            }
         }
      }
      
      //--- Scaled Exit: Take partial profit at TP2 (40% of original)
      if(UseScaledExit && g_partialTP1Taken && !g_partialTP2Taken && profitPips >= TP2_Pips)
      {
         double closeVolume = NormalizeDouble(g_originalLots * 0.4, 2);
         closeVolume = MathMax(closeVolume, g_minLot);
         
         if(closeVolume < currentVolume)
         {
            if(trade.PositionClosePartial(ticket, closeVolume))
            {
               Print("Partial TP2 taken: ", closeVolume, " lots (40%) at ", TP2_Pips, " pips");
               g_partialTP2Taken = true;
               
               // Update TP to final target for remaining position
               double riskDistance = MathAbs(openPrice - g_originalSL);
               double newTP = (posType == POSITION_TYPE_BUY) ?
                              openPrice + riskDistance * TP3_RiskMultiple :
                              openPrice - riskDistance * TP3_RiskMultiple;
               
               trade.PositionModify(ticket, currentSL, NormalizeDouble(newTP, g_digits));
               Print("Final TP set to ", DoubleToString(newTP, g_digits), " for remaining 30%");
            }
         }
      }
      
      //--- Trailing Stop (after TP2 taken and profit above threshold)
      if(UseTrailingStop && g_partialTP2Taken && profitPips >= TrailingStartPips)
      {
         double trailDistance = TrailingStopPips * g_pipValue;
         
         if(posType == POSITION_TYPE_BUY)
         {
            double newSL = NormalizeDouble(bid - trailDistance, g_digits);
            if(newSL > currentSL + g_pipValue)
            {
               if(trade.PositionModify(ticket, newSL, currentTP))
                  Print("Trailing stop updated to ", newSL);
            }
         }
         else
         {
            double newSL = NormalizeDouble(ask + trailDistance, g_digits);
            if(newSL < currentSL - g_pipValue)
            {
               if(trade.PositionModify(ticket, newSL, currentTP))
                  Print("Trailing stop updated to ", newSL);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Update high water mark                                           |
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
void CloseAllPositions(string reason = "")
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == MagicNumber)
         {
            if(trade.PositionClose(positionInfo.Ticket()))
               Print("Position closed. Reason: ", reason);
         }
      }
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
      {
         if(orderInfo.Symbol() == _Symbol && orderInfo.Magic() == MagicNumber)
            trade.OrderDelete(orderInfo.Ticket());
      }
   }
}

//+------------------------------------------------------------------+
//| Draw range lines on chart                                        |
//+------------------------------------------------------------------+
void DrawRangeLines()
{
   datetime startTime = g_asianStartTime;
   datetime endTime = g_hardExitTime;
   
   // Asian High line
   ObjectCreate(0, "LB_High", OBJ_TREND, 0, startTime, g_asianHigh, endTime, g_asianHigh);
   ObjectSetInteger(0, "LB_High", OBJPROP_COLOR, clrDodgerBlue);
   ObjectSetInteger(0, "LB_High", OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, "LB_High", OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, "LB_High", OBJPROP_RAY_RIGHT, false);
   
   // Asian Low line
   ObjectCreate(0, "LB_Low", OBJ_TREND, 0, startTime, g_asianLow, endTime, g_asianLow);
   ObjectSetInteger(0, "LB_Low", OBJPROP_COLOR, clrOrangeRed);
   ObjectSetInteger(0, "LB_Low", OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, "LB_Low", OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, "LB_Low", OBJPROP_RAY_RIGHT, false);
   
   // Buy entry level
   double buyEntry = g_asianHigh + BufferPips * g_pipValue;
   ObjectCreate(0, "LB_BuyEntry", OBJ_TREND, 0, g_asianEndTime, buyEntry, endTime, buyEntry);
   ObjectSetInteger(0, "LB_BuyEntry", OBJPROP_COLOR, clrLime);
   ObjectSetInteger(0, "LB_BuyEntry", OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, "LB_BuyEntry", OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, "LB_BuyEntry", OBJPROP_RAY_RIGHT, false);
   
   // Sell entry level
   double sellEntry = g_asianLow - BufferPips * g_pipValue;
   ObjectCreate(0, "LB_SellEntry", OBJ_TREND, 0, g_asianEndTime, sellEntry, endTime, sellEntry);
   ObjectSetInteger(0, "LB_SellEntry", OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, "LB_SellEntry", OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, "LB_SellEntry", OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, "LB_SellEntry", OBJPROP_RAY_RIGHT, false);
}

//+------------------------------------------------------------------+
//| Display status on chart                                          |
//+------------------------------------------------------------------+
void DisplayStatus(string phase = "")
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   // Calculate drawdowns
   double dailyDD = 0, totalDD = 0;
   if(g_dailyStartEquity > 0)
      dailyDD = ((g_dailyStartEquity - equity) / g_dailyStartEquity) * 100.0;
   if(g_startingBalance > 0)
      totalDD = ((g_startingBalance - equity) / g_startingBalance) * 100.0;
   
   // Build status string
   string status = "";
   status += "═══════ LONDON BREAKOUT - PROP EDITION v2.0 ═══════\n";
   status += "Phase: " + phase + "\n";
   status += "────────────────────────────────────────────\n";
   status += "Asian Range: " + DoubleToString(g_rangeSize, 1) + " pips\n";
   status += "High: " + DoubleToString(g_asianHigh, g_digits) + "\n";
   status += "Low: " + DoubleToString(g_asianLow == DBL_MAX ? 0 : g_asianLow, g_digits) + "\n";
   status += "────────────────────────────────────────────\n";
   status += "Market Filters: ATR=" + (UseATRFilter ? "ON" : "OFF") + 
             " | Trend=" + (UseTrendFilter ? (g_isBullishTrend ? "BULL" : "BEAR") : "OFF") + 
             " | Vol=" + (UseVolumeFilter ? "ON" : "OFF") + "\n";
   status += "────────────────────────────────────────────\n";
   status += "Trades Today: " + IntegerToString(g_tradesToday) + "/" + IntegerToString(MaxTradesPerDay) + "\n";
   status += "TP1: " + (g_partialTP1Taken ? "✓" : "✗") + " | TP2: " + (g_partialTP2Taken ? "✓" : "✗") + " | BE: " + (g_breakevenMoved ? "✓" : "✗") + "\n";
   status += "────────────────────────────────────────────\n";
   status += "Balance: $" + DoubleToString(balance, 2) + "\n";
   status += "Equity: $" + DoubleToString(equity, 2) + "\n";
   status += "────────────────────────────────────────────\n";
   status += "Daily DD: " + DoubleToString(dailyDD, 2) + "% / " + DoubleToString(MaxDailyDD, 1) + "%\n";
   status += "Total DD: " + DoubleToString(totalDD, 2) + "% / " + DoubleToString(MaxTotalDD, 1) + "%\n";
   status += "═════════════════════════════════════════════";
   
   Comment(status);
}

//+------------------------------------------------------------------+
//| Reset starting balance (call manually if needed)                  |
//+------------------------------------------------------------------+
void ResetStartingBalance()
{
   g_startingBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   GlobalVariableSet(g_gvPrefix + "StartBalance", g_startingBalance);
   Print("Starting balance reset to: $", DoubleToString(g_startingBalance, 2));
}

//+------------------------------------------------------------------+
//| Reset kill switch (call manually if needed)                       |
//+------------------------------------------------------------------+
void ResetKillSwitch()
{
   if(GlobalVariableCheck(g_gvPrefix + "KillSwitch"))
      GlobalVariableDel(g_gvPrefix + "KillSwitch");
   g_tradingAllowed = true;
   Print("Kill Switch has been reset. Trading enabled.");
}
//+------------------------------------------------------------------+