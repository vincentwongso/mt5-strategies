//+------------------------------------------------------------------+
//|                                         GoldSilverScalper_M15.mq5 |
//|                                        M15 EMA Trend Scalper      |
//|                                  Gold (XAUUSD) & Silver (XAGUSD)  |
//+------------------------------------------------------------------+
#property copyright "Vincent Trading Systems"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input group "=== Risk Management ==="
input double   InpRiskPercent        = 0.25;    // Risk per trade (%)
input double   InpMaxDailyDrawdown   = 3.0;     // Max daily drawdown (%)
input int      InpMaxTotalPositions  = 5;       // Max total positions (both symbols)
input int      InpMaxPositionsSymbol = 3;       // Max positions per symbol

input group "=== Trade Parameters ==="
input double   InpRiskRewardRatio    = 1.5;     // Risk:Reward ratio (1:X)
input double   InpATRMultiplierSL    = 1.5;     // ATR multiplier for Stop Loss
input int      InpATRPeriod          = 14;      // ATR period
input int      InpMinATRPeriod       = 20;      // Period for minimum ATR filter
input double   InpMinATRMultiplier   = 0.7;     // Min ATR threshold (X * average ATR)

input group "=== EMA Settings ==="
input int      InpEMAFast            = 20;      // Fast EMA period
input int      InpEMAMedium          = 50;      // Medium EMA period
input int      InpEMASlow            = 200;     // Slow EMA period

input group "=== Session Filter (UTC) ==="
input int      InpSessionStartHour   = 14;      // Session start hour (UTC)
input int      InpSessionStartMin    = 30;      // Session start minute
input int      InpSessionEndHour     = 18;      // Session end hour (UTC)
input int      InpSessionEndMin      = 0;       // Session end minute
input int      InpNoEntryBeforeEnd   = 30;      // No new entries X min before session end

input group "=== News Filter ==="
input bool     InpUseNewsFilter      = true;    // Enable news filter
input int      InpNewsMinutesBefore  = 15;      // Minutes before news to avoid
input int      InpNewsMinutesAfter   = 15;      // Minutes after news to avoid
input string   InpNewsCountries      = "USD";   // News countries to monitor (comma separated)

input group "=== Exit Management ==="
input double   InpBreakevenTrigger   = 1.0;     // Move to BE at X times risk (R)
input double   InpTrailingDistance   = 1.0;     // Trailing stop distance (in R)
input bool     InpUseReversalExit    = true;    // Use 2-candle reversal exit
input bool     InpUsePartialClose    = false;   // Use partial close at 1R
input double   InpPartialClosePercent= 50.0;    // Partial close percentage

input group "=== Price Action Patterns ==="
input bool     InpUsePinBar          = true;    // Use pin bar entries
input double   InpPinBarWickRatio    = 2.0;     // Pin bar wick to body ratio
input bool     InpUseEngulfing       = true;    // Use engulfing pattern entries
input double   InpEngulfingMinSize   = 0.5;     // Min engulfing size (X * ATR)

input group "=== General ==="
input int      InpMagicNumber        = 20240115;// Magic number
input string   InpTradeComment       = "GS_M15";// Trade comment
input int      InpSlippage           = 30;      // Max slippage (points)

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  positionInfo;
CAccountInfo   accountInfo;
CSymbolInfo    symbolInfo;

// Indicator handles
int handleEMAFast;
int handleEMAMedium;
int handleEMASlow;
int handleATR;

// Buffers
double bufferEMAFast[];
double bufferEMAMedium[];
double bufferEMASlow[];
double bufferATR[];

// Daily tracking
double dailyStartBalance;
datetime lastDayChecked;
bool dailyDrawdownBreached;

// Reversal tracking per position
struct PositionTracker {
   ulong  ticket;
   bool   firstReversalCandle;
   double entryPrice;
   double stopLoss;
   double takeProfit;
   double initialRisk;
   bool   breakEvenSet;
   bool   partialClosed;
};
PositionTracker positionTrackers[];

// News events cache
struct NewsEvent {
   datetime time;
   string   currency;
   string   name;
};
NewsEvent newsEvents[];
datetime lastNewsUpdate;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Validate symbol
   string symbol = _Symbol;
   if(StringFind(symbol, "XAU") < 0 && StringFind(symbol, "XAG") < 0 &&
      StringFind(symbol, "GOLD") < 0 && StringFind(symbol, "SILVER") < 0)
   {
      Print("Warning: This EA is designed for Gold (XAUUSD) or Silver (XAGUSD)");
   }
   
   // Validate timeframe
   if(_Period != PERIOD_M15)
   {
      Print("Warning: This EA is designed for M15 timeframe. Current: ", EnumToString(_Period));
   }
   
   // Initialize trade object
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   trade.SetAsyncMode(false);
   
   // Initialize symbol info
   if(!symbolInfo.Name(_Symbol))
   {
      Print("Error initializing symbol info");
      return INIT_FAILED;
   }
   
   // Create indicator handles
   handleEMAFast = iMA(_Symbol, PERIOD_M15, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   handleEMAMedium = iMA(_Symbol, PERIOD_M15, InpEMAMedium, 0, MODE_EMA, PRICE_CLOSE);
   handleEMASlow = iMA(_Symbol, PERIOD_M15, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
   handleATR = iATR(_Symbol, PERIOD_M15, InpATRPeriod);
   
   if(handleEMAFast == INVALID_HANDLE || handleEMAMedium == INVALID_HANDLE ||
      handleEMASlow == INVALID_HANDLE || handleATR == INVALID_HANDLE)
   {
      Print("Error creating indicator handles");
      return INIT_FAILED;
   }
   
   // Set buffer directions
   ArraySetAsSeries(bufferEMAFast, true);
   ArraySetAsSeries(bufferEMAMedium, true);
   ArraySetAsSeries(bufferEMASlow, true);
   ArraySetAsSeries(bufferATR, true);
   
   // Initialize daily tracking
   dailyStartBalance = accountInfo.Balance();
   lastDayChecked = 0;
   dailyDrawdownBreached = false;
   
   // Initialize news cache
   lastNewsUpdate = 0;
   
   Print("GoldSilverScalper M15 initialized successfully");
   Print("Symbol: ", _Symbol, " | Timeframe: M15");
   Print("Risk: ", InpRiskPercent, "% | R:R 1:", InpRiskRewardRatio);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   if(handleEMAFast != INVALID_HANDLE) IndicatorRelease(handleEMAFast);
   if(handleEMAMedium != INVALID_HANDLE) IndicatorRelease(handleEMAMedium);
   if(handleEMASlow != INVALID_HANDLE) IndicatorRelease(handleEMASlow);
   if(handleATR != INVALID_HANDLE) IndicatorRelease(handleATR);
   
   Print("GoldSilverScalper M15 deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new day - reset daily tracking
   CheckNewDay();
   
   // Check daily drawdown
   if(CheckDailyDrawdown())
   {
      ManageOpenPositions();
      return; // Stop trading if drawdown breached
   }
   
   // Update indicator values
   if(!UpdateIndicators())
      return;
   
   // Manage existing positions (trailing, BE, reversal exits)
   ManageOpenPositions();
   
   // Check if new bar formed
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, PERIOD_M15, 0);
   
   if(lastBarTime == currentBarTime)
      return; // Only process on new bar
   
   lastBarTime = currentBarTime;
   
   // Check session filter
   if(!IsWithinSession())
      return;
   
   // Check news filter
   if(InpUseNewsFilter && IsNearNews())
      return;
   
   // Check position limits
   if(!CanOpenNewPosition())
      return;
   
   // Check for entry signals
   CheckEntrySignals();
}

//+------------------------------------------------------------------+
//| Check for new trading day                                         |
//+------------------------------------------------------------------+
void CheckNewDay()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", 
                                  timeStruct.year, timeStruct.mon, timeStruct.day));
   
   if(today != lastDayChecked)
   {
      lastDayChecked = today;
      dailyStartBalance = accountInfo.Balance();
      dailyDrawdownBreached = false;
      Print("New trading day. Starting balance: ", dailyStartBalance);
   }
}

//+------------------------------------------------------------------+
//| Check daily drawdown limit                                        |
//+------------------------------------------------------------------+
bool CheckDailyDrawdown()
{
   if(dailyDrawdownBreached)
      return true;
   
   double currentEquity = accountInfo.Equity();
   double drawdownPercent = ((dailyStartBalance - currentEquity) / dailyStartBalance) * 100;
   
   if(drawdownPercent >= InpMaxDailyDrawdown)
   {
      dailyDrawdownBreached = true;
      Print("DAILY DRAWDOWN LIMIT REACHED: ", DoubleToString(drawdownPercent, 2), "%");
      Print("Trading halted for today. Will resume tomorrow.");
      
      // Optionally close all positions
      // CloseAllPositions();
      
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Update indicator buffers                                          |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
   int copied;
   
   copied = CopyBuffer(handleEMAFast, 0, 0, 10, bufferEMAFast);
   if(copied < 10) return false;
   
   copied = CopyBuffer(handleEMAMedium, 0, 0, 10, bufferEMAMedium);
   if(copied < 10) return false;
   
   copied = CopyBuffer(handleEMASlow, 0, 0, 10, bufferEMASlow);
   if(copied < 10) return false;
   
   copied = CopyBuffer(handleATR, 0, 0, InpMinATRPeriod + 5, bufferATR);
   if(copied < InpMinATRPeriod + 5) return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if within trading session (UTC based)                       |
//+------------------------------------------------------------------+
bool IsWithinSession()
{
   datetime serverTime = TimeCurrent();
   
   // Get broker's GMT offset
   int gmtOffset = GetBrokerGMTOffset();
   datetime utcTime = serverTime - gmtOffset * 3600;
   
   MqlDateTime timeStruct;
   TimeToStruct(utcTime, timeStruct);
   
   int currentMinutes = timeStruct.hour * 60 + timeStruct.min;
   int sessionStart = InpSessionStartHour * 60 + InpSessionStartMin;
   int sessionEnd = InpSessionEndHour * 60 + InpSessionEndMin;
   int noEntryTime = sessionEnd - InpNoEntryBeforeEnd;
   
   // Check if within session
   if(currentMinutes < sessionStart || currentMinutes >= sessionEnd)
      return false;
   
   // Check if too close to session end for new entries
   if(currentMinutes >= noEntryTime)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Get broker GMT offset (approximate)                               |
//+------------------------------------------------------------------+
int GetBrokerGMTOffset()
{
   // This is a simplified approach - you may need to adjust for your broker
   // Most brokers use GMT+2 or GMT+3 (with DST)
   datetime serverTime = TimeCurrent();
   datetime gmtTime = TimeGMT();
   
   int offsetSeconds = (int)(serverTime - gmtTime);
   int offsetHours = offsetSeconds / 3600;
   
   return offsetHours;
}

//+------------------------------------------------------------------+
//| Check if near high-impact news                                    |
//+------------------------------------------------------------------+
bool IsNearNews()
{
   if(!InpUseNewsFilter)
      return false;
   
   datetime currentTime = TimeCurrent();
   
   // Update news cache every hour
   if(currentTime - lastNewsUpdate > 3600)
   {
      UpdateNewsCache();
      lastNewsUpdate = currentTime;
   }
   
   // Check if current time is within news avoidance window
   for(int i = 0; i < ArraySize(newsEvents); i++)
   {
      datetime newsTime = newsEvents[i].time;
      datetime avoidStart = newsTime - InpNewsMinutesBefore * 60;
      datetime avoidEnd = newsTime + InpNewsMinutesAfter * 60;
      
      if(currentTime >= avoidStart && currentTime <= avoidEnd)
      {
         Print("Avoiding trade due to news: ", newsEvents[i].name, 
               " at ", TimeToString(newsTime));
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Update news events cache using MQL5 Calendar                      |
//+------------------------------------------------------------------+
void UpdateNewsCache()
{
   ArrayResize(newsEvents, 0);
   
   datetime fromTime = TimeCurrent() - 3600; // 1 hour ago
   datetime toTime = TimeCurrent() + 24 * 3600; // 24 hours ahead
   
   // Parse countries to monitor
   string countries[];
   int numCountries = StringSplit(InpNewsCountries, ',', countries);
   
   MqlCalendarValue values[];
   
   // Get calendar events
   int totalEvents = CalendarValueHistory(values, fromTime, toTime, NULL, NULL);
   
   if(totalEvents <= 0)
      return;
   
   for(int i = 0; i < totalEvents; i++)
   {
      MqlCalendarEvent event;
      if(!CalendarEventById(values[i].event_id, event))
         continue;
      
      // Check if high impact
      if(event.importance != CALENDAR_IMPORTANCE_HIGH)
         continue;
      
      MqlCalendarCountry country;
      if(!CalendarCountryById(event.country_id, country))
         continue;
      
      // Check if currency is in our watch list
      bool relevant = false;
      for(int j = 0; j < numCountries; j++)
      {
         StringTrimLeft(countries[j]);
         StringTrimRight(countries[j]);
         if(StringFind(country.currency, countries[j]) >= 0 ||
            StringFind(_Symbol, countries[j]) >= 0)
         {
            relevant = true;
            break;
         }
      }
      
      // For Gold/Silver, always monitor USD
      if(StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "XAG") >= 0 ||
         StringFind(_Symbol, "GOLD") >= 0 || StringFind(_Symbol, "SILVER") >= 0)
      {
         if(country.currency == "USD")
            relevant = true;
      }
      
      if(!relevant)
         continue;
      
      // Add to cache
      int size = ArraySize(newsEvents);
      ArrayResize(newsEvents, size + 1);
      newsEvents[size].time = values[i].time;
      newsEvents[size].currency = country.currency;
      newsEvents[size].name = event.name;
   }
   
   Print("News cache updated. ", ArraySize(newsEvents), " high-impact events in window.");
}

//+------------------------------------------------------------------+
//| Check if can open new position                                    |
//+------------------------------------------------------------------+
bool CanOpenNewPosition()
{
   int totalPositions = 0;
   int symbolPositions = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Magic() == InpMagicNumber)
         {
            totalPositions++;
            if(positionInfo.Symbol() == _Symbol)
               symbolPositions++;
         }
      }
   }
   
   if(totalPositions >= InpMaxTotalPositions)
   {
      return false;
   }
   
   if(symbolPositions >= InpMaxPositionsSymbol)
   {
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Get trend direction based on EMA alignment                        |
//+------------------------------------------------------------------+
int GetTrendDirection()
{
   // Check EMA stacking on completed bar (index 1)
   double emaFast = bufferEMAFast[1];
   double emaMedium = bufferEMAMedium[1];
   double emaSlow = bufferEMASlow[1];
   
   double close = iClose(_Symbol, PERIOD_M15, 1);
   
   // Strong uptrend: Price > 20 > 50 > 200
   if(close > emaFast && emaFast > emaMedium && emaMedium > emaSlow)
      return 1; // Bullish
   
   // Strong downtrend: Price < 20 < 50 < 200
   if(close < emaFast && emaFast < emaMedium && emaMedium < emaSlow)
      return -1; // Bearish
   
   // Check for indecision (price between EMAs)
   double highestEMA = MathMax(emaFast, MathMax(emaMedium, emaSlow));
   double lowestEMA = MathMin(emaFast, MathMin(emaMedium, emaSlow));
   
   if(close > lowestEMA && close < highestEMA)
      return 0; // Consolidation - avoid
   
   return 0; // No clear trend
}

//+------------------------------------------------------------------+
//| Check for EMA crossover warning                                   |
//+------------------------------------------------------------------+
bool IsEMACrossoverWarning()
{
   // Check if 20 and 50 have crossed but 200 hasn't confirmed
   double emaFast_1 = bufferEMAFast[1];
   double emaFast_2 = bufferEMAFast[2];
   double emaMedium_1 = bufferEMAMedium[1];
   double emaMedium_2 = bufferEMAMedium[2];
   double emaSlow_1 = bufferEMASlow[1];
   
   // Bullish cross of 20/50 but 50 still below 200
   if(emaFast_1 > emaMedium_1 && emaFast_2 <= emaMedium_2 && emaMedium_1 < emaSlow_1)
      return true;
   
   // Bearish cross of 20/50 but 50 still above 200
   if(emaFast_1 < emaMedium_1 && emaFast_2 >= emaMedium_2 && emaMedium_1 > emaSlow_1)
      return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| Check minimum ATR filter                                          |
//+------------------------------------------------------------------+
bool PassesATRFilter()
{
   // Calculate average ATR over the filter period
   double sumATR = 0;
   for(int i = 1; i <= InpMinATRPeriod; i++)
   {
      sumATR += bufferATR[i];
   }
   double avgATR = sumATR / InpMinATRPeriod;
   
   double currentATR = bufferATR[1];
   double minATR = avgATR * InpMinATRMultiplier;
   
   if(currentATR < minATR)
   {
      return false; // Low volatility - avoid
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check for entry signals                                           |
//+------------------------------------------------------------------+
void CheckEntrySignals()
{
   int trend = GetTrendDirection();
   
   if(trend == 0)
      return; // No clear trend
   
   // Check for EMA crossover warning
   if(IsEMACrossoverWarning())
      return; // Potential trend change - avoid new entries
   
   // Check ATR filter
   if(!PassesATRFilter())
      return;
   
   // Get candle data
   double open1 = iOpen(_Symbol, PERIOD_M15, 1);
   double high1 = iHigh(_Symbol, PERIOD_M15, 1);
   double low1 = iLow(_Symbol, PERIOD_M15, 1);
   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   
   double emaFast = bufferEMAFast[1];
   double emaMedium = bufferEMAMedium[1];
   
   bool entrySignal = false;
   ENUM_ORDER_TYPE orderType = ORDER_TYPE_BUY;
   string signalType = "";
   
   if(trend == 1) // Bullish
   {
      // Primary: EMA touch entry
      if(low1 <= emaFast && close1 > emaFast)
      {
         entrySignal = true;
         signalType = "EMA20 Touch";
      }
      // Secondary: Pin bar at EMA
      else if(InpUsePinBar && IsBullishPinBar(1, emaFast, emaMedium))
      {
         entrySignal = true;
         signalType = "Bullish Pin Bar";
      }
      // Secondary: Bullish engulfing at EMA
      else if(InpUseEngulfing && IsBullishEngulfing(1, emaFast, emaMedium))
      {
         entrySignal = true;
         signalType = "Bullish Engulfing";
      }
      
      orderType = ORDER_TYPE_BUY;
   }
   else if(trend == -1) // Bearish
   {
      // Primary: EMA touch entry
      if(high1 >= emaFast && close1 < emaFast)
      {
         entrySignal = true;
         signalType = "EMA20 Touch";
      }
      // Secondary: Pin bar at EMA
      else if(InpUsePinBar && IsBearishPinBar(1, emaFast, emaMedium))
      {
         entrySignal = true;
         signalType = "Bearish Pin Bar";
      }
      // Secondary: Bearish engulfing at EMA
      else if(InpUseEngulfing && IsBearishEngulfing(1, emaFast, emaMedium))
      {
         entrySignal = true;
         signalType = "Bearish Engulfing";
      }
      
      orderType = ORDER_TYPE_SELL;
   }
   
   if(entrySignal)
   {
      ExecuteTrade(orderType, signalType);
   }
}

//+------------------------------------------------------------------+
//| Check for bullish pin bar                                         |
//+------------------------------------------------------------------+
bool IsBullishPinBar(int shift, double emaFast, double emaMedium)
{
   double open = iOpen(_Symbol, PERIOD_M15, shift);
   double high = iHigh(_Symbol, PERIOD_M15, shift);
   double low = iLow(_Symbol, PERIOD_M15, shift);
   double close = iClose(_Symbol, PERIOD_M15, shift);
   
   double body = MathAbs(close - open);
   double lowerWick = MathMin(open, close) - low;
   double upperWick = high - MathMax(open, close);
   
   // Pin bar: lower wick significantly larger than body and upper wick
   if(body == 0) body = symbolInfo.Point();
   
   if(lowerWick >= body * InpPinBarWickRatio && lowerWick > upperWick * 2)
   {
      // Must be near EMA
      if(low <= emaFast * 1.001 || low <= emaMedium * 1.001)
      {
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check for bearish pin bar                                         |
//+------------------------------------------------------------------+
bool IsBearishPinBar(int shift, double emaFast, double emaMedium)
{
   double open = iOpen(_Symbol, PERIOD_M15, shift);
   double high = iHigh(_Symbol, PERIOD_M15, shift);
   double low = iLow(_Symbol, PERIOD_M15, shift);
   double close = iClose(_Symbol, PERIOD_M15, shift);
   
   double body = MathAbs(close - open);
   double lowerWick = MathMin(open, close) - low;
   double upperWick = high - MathMax(open, close);
   
   // Pin bar: upper wick significantly larger than body and lower wick
   if(body == 0) body = symbolInfo.Point();
   
   if(upperWick >= body * InpPinBarWickRatio && upperWick > lowerWick * 2)
   {
      // Must be near EMA
      if(high >= emaFast * 0.999 || high >= emaMedium * 0.999)
      {
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check for bullish engulfing                                       |
//+------------------------------------------------------------------+
bool IsBullishEngulfing(int shift, double emaFast, double emaMedium)
{
   double open1 = iOpen(_Symbol, PERIOD_M15, shift);
   double close1 = iClose(_Symbol, PERIOD_M15, shift);
   double open2 = iOpen(_Symbol, PERIOD_M15, shift + 1);
   double close2 = iClose(_Symbol, PERIOD_M15, shift + 1);
   double low1 = iLow(_Symbol, PERIOD_M15, shift);
   
   double atr = bufferATR[shift];
   double minSize = atr * InpEngulfingMinSize;
   
   // Previous candle bearish, current candle bullish and engulfs
   if(close2 < open2 && close1 > open1)
   {
      if(close1 > open2 && open1 < close2)
      {
         double body = close1 - open1;
         if(body >= minSize)
         {
            // Must be near EMA
            if(low1 <= emaFast * 1.002 || low1 <= emaMedium * 1.002)
            {
               return true;
            }
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check for bearish engulfing                                       |
//+------------------------------------------------------------------+
bool IsBearishEngulfing(int shift, double emaFast, double emaMedium)
{
   double open1 = iOpen(_Symbol, PERIOD_M15, shift);
   double close1 = iClose(_Symbol, PERIOD_M15, shift);
   double open2 = iOpen(_Symbol, PERIOD_M15, shift + 1);
   double close2 = iClose(_Symbol, PERIOD_M15, shift + 1);
   double high1 = iHigh(_Symbol, PERIOD_M15, shift);
   
   double atr = bufferATR[shift];
   double minSize = atr * InpEngulfingMinSize;
   
   // Previous candle bullish, current candle bearish and engulfs
   if(close2 > open2 && close1 < open1)
   {
      if(close1 < open2 && open1 > close2)
      {
         double body = open1 - close1;
         if(body >= minSize)
         {
            // Must be near EMA
            if(high1 >= emaFast * 0.998 || high1 >= emaMedium * 0.998)
            {
               return true;
            }
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Execute trade                                                     |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE orderType, string signalType)
{
   symbolInfo.RefreshRates();
   
   double price, sl, tp;
   double atr = bufferATR[1];
   double slDistance = atr * InpATRMultiplierSL;
   double tpDistance = slDistance * InpRiskRewardRatio;
   
   if(orderType == ORDER_TYPE_BUY)
   {
      price = symbolInfo.Ask();
      sl = price - slDistance;
      tp = price + tpDistance;
   }
   else
   {
      price = symbolInfo.Bid();
      sl = price + slDistance;
      tp = price - tpDistance;
   }
   
   // Calculate position size
   double lotSize = CalculateLotSize(slDistance);
   
   if(lotSize <= 0)
   {
      Print("Invalid lot size calculated");
      return;
   }
   
   // Normalize values
   sl = NormalizeDouble(sl, symbolInfo.Digits());
   tp = NormalizeDouble(tp, symbolInfo.Digits());
   
   string comment = InpTradeComment + "_" + signalType;
   
   if(trade.PositionOpen(_Symbol, orderType, lotSize, price, sl, tp, comment))
   {
      Print("Trade opened: ", signalType, " | Type: ", EnumToString(orderType),
            " | Lots: ", lotSize, " | SL: ", sl, " | TP: ", tp);
      
      // Add to position tracker
      AddPositionTracker(trade.ResultOrder(), price, sl, tp, slDistance);
   }
   else
   {
      Print("Trade failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                  |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance)
{
   double accountBalance = accountInfo.Balance();
   double riskAmount = accountBalance * (InpRiskPercent / 100);
   
   // Get tick value
   double tickValue = symbolInfo.TickValue();
   double tickSize = symbolInfo.TickSize();
   
   if(tickSize == 0) return 0;
   
   // Calculate value per lot for the SL distance
   double slTicks = slDistance / tickSize;
   double valuePerLot = slTicks * tickValue;
   
   if(valuePerLot == 0) return 0;
   
   double lotSize = riskAmount / valuePerLot;
   
   // Normalize to lot step
   double lotStep = symbolInfo.LotsStep();
   double minLot = symbolInfo.LotsMin();
   double maxLot = symbolInfo.LotsMax();
   
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   
   return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
//| Add position to tracker                                           |
//+------------------------------------------------------------------+
void AddPositionTracker(ulong ticket, double entry, double sl, double tp, double risk)
{
   int size = ArraySize(positionTrackers);
   ArrayResize(positionTrackers, size + 1);
   
   positionTrackers[size].ticket = ticket;
   positionTrackers[size].entryPrice = entry;
   positionTrackers[size].stopLoss = sl;
   positionTrackers[size].takeProfit = tp;
   positionTrackers[size].initialRisk = risk;
   positionTrackers[size].firstReversalCandle = false;
   positionTrackers[size].breakEvenSet = false;
   positionTrackers[size].partialClosed = false;
}

//+------------------------------------------------------------------+
//| Get position tracker index                                        |
//+------------------------------------------------------------------+
int GetTrackerIndex(ulong ticket)
{
   for(int i = 0; i < ArraySize(positionTrackers); i++)
   {
      if(positionTrackers[i].ticket == ticket)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Remove position tracker                                           |
//+------------------------------------------------------------------+
void RemovePositionTracker(ulong ticket)
{
   int index = GetTrackerIndex(ticket);
   if(index < 0) return;
   
   int lastIndex = ArraySize(positionTrackers) - 1;
   if(index != lastIndex)
   {
      positionTrackers[index] = positionTrackers[lastIndex];
   }
   ArrayResize(positionTrackers, lastIndex);
}

//+------------------------------------------------------------------+
//| Manage open positions                                             |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!positionInfo.SelectByIndex(i))
         continue;
      
      if(positionInfo.Magic() != InpMagicNumber)
         continue;
      
      if(positionInfo.Symbol() != _Symbol)
         continue;
      
      ulong ticket = positionInfo.Ticket();
      int trackerIdx = GetTrackerIndex(ticket);
      
      if(trackerIdx < 0)
      {
         // Position not in tracker - add it
         double risk = MathAbs(positionInfo.PriceOpen() - positionInfo.StopLoss());
         AddPositionTracker(ticket, positionInfo.PriceOpen(), 
                           positionInfo.StopLoss(), positionInfo.TakeProfit(), risk);
         trackerIdx = ArraySize(positionTrackers) - 1;
      }
      
      // Check reversal exit
      if(InpUseReversalExit && CheckReversalExit(trackerIdx))
      {
         ClosePosition(ticket, "Reversal Exit");
         continue;
      }
      
      // Check partial close
      if(InpUsePartialClose && !positionTrackers[trackerIdx].partialClosed)
      {
         CheckPartialClose(trackerIdx);
      }
      
      // Check breakeven
      if(!positionTrackers[trackerIdx].breakEvenSet)
      {
         CheckBreakeven(trackerIdx);
      }
      
      // Check trailing stop
      if(positionTrackers[trackerIdx].breakEvenSet)
      {
         CheckTrailingStop(trackerIdx);
      }
   }
   
   // Clean up trackers for closed positions
   CleanupTrackers();
}

//+------------------------------------------------------------------+
//| Check reversal exit (2-candle confirmation)                       |
//+------------------------------------------------------------------+
bool CheckReversalExit(int trackerIdx)
{
   if(trackerIdx < 0 || trackerIdx >= ArraySize(positionTrackers))
      return false;
   
   if(!positionInfo.SelectByTicket(positionTrackers[trackerIdx].ticket))
      return false;
   
   double emaFast = bufferEMAFast[1];
   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   
   bool reversalCandle = false;
   
   if(positionInfo.PositionType() == POSITION_TYPE_BUY)
   {
      // For long: close below 20 EMA is reversal signal
      reversalCandle = (close1 < emaFast);
   }
   else
   {
      // For short: close above 20 EMA is reversal signal
      reversalCandle = (close1 > emaFast);
   }
   
   if(reversalCandle)
   {
      if(positionTrackers[trackerIdx].firstReversalCandle)
      {
         // Second candle confirms reversal - exit
         return true;
      }
      else
      {
         // First reversal candle - mark it
         positionTrackers[trackerIdx].firstReversalCandle = true;
      }
   }
   else
   {
      // Price back in trend - reset
      positionTrackers[trackerIdx].firstReversalCandle = false;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check and execute partial close                                   |
//+------------------------------------------------------------------+
void CheckPartialClose(int trackerIdx)
{
   if(trackerIdx < 0 || trackerIdx >= ArraySize(positionTrackers))
      return;
   
   if(!positionInfo.SelectByTicket(positionTrackers[trackerIdx].ticket))
      return;
   
   double currentPrice = (positionInfo.PositionType() == POSITION_TYPE_BUY) ?
                         symbolInfo.Bid() : symbolInfo.Ask();
   double entryPrice = positionTrackers[trackerIdx].entryPrice;
   double initialRisk = positionTrackers[trackerIdx].initialRisk;
   
   double profitDistance = 0;
   
   if(positionInfo.PositionType() == POSITION_TYPE_BUY)
   {
      profitDistance = currentPrice - entryPrice;
   }
   else
   {
      profitDistance = entryPrice - currentPrice;
   }
   
   // Check if profit >= 1R
   if(profitDistance >= initialRisk)
   {
      double volume = positionInfo.Volume();
      double closeVolume = NormalizeDouble(volume * (InpPartialClosePercent / 100), 2);
      closeVolume = MathMax(closeVolume, symbolInfo.LotsMin());
      
      if(closeVolume < volume && closeVolume >= symbolInfo.LotsMin())
      {
         if(trade.PositionClosePartial(positionTrackers[trackerIdx].ticket, closeVolume))
         {
            Print("Partial close executed: ", closeVolume, " lots at 1R profit");
            positionTrackers[trackerIdx].partialClosed = true;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check and set breakeven                                           |
//+------------------------------------------------------------------+
void CheckBreakeven(int trackerIdx)
{
   if(trackerIdx < 0 || trackerIdx >= ArraySize(positionTrackers))
      return;
   
   if(!positionInfo.SelectByTicket(positionTrackers[trackerIdx].ticket))
      return;
   
   double currentPrice = (positionInfo.PositionType() == POSITION_TYPE_BUY) ?
                         symbolInfo.Bid() : symbolInfo.Ask();
   double entryPrice = positionTrackers[trackerIdx].entryPrice;
   double initialRisk = positionTrackers[trackerIdx].initialRisk;
   double triggerDistance = initialRisk * InpBreakevenTrigger;
   
   double profitDistance = 0;
   
   if(positionInfo.PositionType() == POSITION_TYPE_BUY)
   {
      profitDistance = currentPrice - entryPrice;
   }
   else
   {
      profitDistance = entryPrice - currentPrice;
   }
   
   // Check if profit >= trigger
   if(profitDistance >= triggerDistance)
   {
      double newSL = entryPrice;
      
      // Add small buffer to ensure breakeven
      if(positionInfo.PositionType() == POSITION_TYPE_BUY)
      {
         newSL = entryPrice + symbolInfo.Spread() * symbolInfo.Point();
      }
      else
      {
         newSL = entryPrice - symbolInfo.Spread() * symbolInfo.Point();
      }
      
      newSL = NormalizeDouble(newSL, symbolInfo.Digits());
      
      if(trade.PositionModify(positionTrackers[trackerIdx].ticket, newSL, positionInfo.TakeProfit()))
      {
         Print("Breakeven set for ticket: ", positionTrackers[trackerIdx].ticket);
         positionTrackers[trackerIdx].breakEvenSet = true;
         positionTrackers[trackerIdx].stopLoss = newSL;
      }
   }
}

//+------------------------------------------------------------------+
//| Check and update trailing stop                                    |
//+------------------------------------------------------------------+
void CheckTrailingStop(int trackerIdx)
{
   if(trackerIdx < 0 || trackerIdx >= ArraySize(positionTrackers))
      return;
   
   if(!positionInfo.SelectByTicket(positionTrackers[trackerIdx].ticket))
      return;
   
   double currentSL = positionInfo.StopLoss();
   double initialRisk = positionTrackers[trackerIdx].initialRisk;
   double trailDistance = initialRisk * InpTrailingDistance;
   double newSL;
   
   symbolInfo.RefreshRates();
   
   if(positionInfo.PositionType() == POSITION_TYPE_BUY)
   {
      newSL = symbolInfo.Bid() - trailDistance;
      newSL = NormalizeDouble(newSL, symbolInfo.Digits());
      
      // Only move SL up, never down
      if(newSL > currentSL)
      {
         if(trade.PositionModify(positionTrackers[trackerIdx].ticket, newSL, positionInfo.TakeProfit()))
         {
            positionTrackers[trackerIdx].stopLoss = newSL;
         }
      }
   }
   else
   {
      newSL = symbolInfo.Ask() + trailDistance;
      newSL = NormalizeDouble(newSL, symbolInfo.Digits());
      
      // Only move SL down, never up
      if(newSL < currentSL)
      {
         if(trade.PositionModify(positionTrackers[trackerIdx].ticket, newSL, positionInfo.TakeProfit()))
         {
            positionTrackers[trackerIdx].stopLoss = newSL;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Close position                                                    |
//+------------------------------------------------------------------+
void ClosePosition(ulong ticket, string reason)
{
   if(trade.PositionClose(ticket))
   {
      Print("Position closed: ", ticket, " | Reason: ", reason);
      RemovePositionTracker(ticket);
   }
   else
   {
      Print("Failed to close position: ", ticket, " | Error: ", trade.ResultRetcode());
   }
}

//+------------------------------------------------------------------+
//| Close all positions                                               |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Magic() == InpMagicNumber && positionInfo.Symbol() == _Symbol)
         {
            ClosePosition(positionInfo.Ticket(), "Close All");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Cleanup trackers for closed positions                             |
//+------------------------------------------------------------------+
void CleanupTrackers()
{
   for(int i = ArraySize(positionTrackers) - 1; i >= 0; i--)
   {
      bool found = false;
      for(int j = PositionsTotal() - 1; j >= 0; j--)
      {
         if(positionInfo.SelectByIndex(j))
         {
            if(positionInfo.Ticket() == positionTrackers[i].ticket)
            {
               found = true;
               break;
            }
         }
      }
      
      if(!found)
      {
         RemovePositionTracker(positionTrackers[i].ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| OnTimer - for periodic tasks                                      |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Can be used for periodic news cache updates
}

//+------------------------------------------------------------------+
