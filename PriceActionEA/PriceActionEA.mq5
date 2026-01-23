//+------------------------------------------------------------------+
//|                                              PriceActionEA.mq5   |
//|                       Price Action Trading System with S/R       |
//|                  Candlestick Patterns + Support/Resistance       |
//+------------------------------------------------------------------+
#property copyright "Price Action EA"
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
input double   RiskPercent         = 0.5;      // Risk per trade (%)
input int      MaxOpenTrades       = 3;        // Maximum open trades
input double   RiskRewardRatio     = 2.0;      // Risk:Reward Ratio for final TP

input group "=== Trade Quality Filters ==="
input double   MinimumRRFilter     = 0.0;      // Minimum R:R ratio before entry (0 = disabled)
input double   MinATRFilter        = 0.0;      // Minimum ATR as % of price (0 = disabled)
input int      MaxConsecutiveLosses = 0;       // Pause trading after N consecutive losses (0 = disabled)
input int      PauseBarsAfterLosses = 20;      // Bars to pause after max consecutive losses reached
input bool     UseADXFilter        = true;     // Use ADX filter to avoid ranging markets
input int      ADXPeriod           = 14;       // ADX indicator period
input double   MinADXForTrend      = 20.0;     // Minimum ADX value to confirm trend (0 = disabled)
input double   StopLossBufferATR   = 0.3;      // Stop loss buffer as ATR multiple
input double   MinBodyATRRatio     = 0.3;      // Minimum candle body size as ATR ratio

input group "=== Trade Management ==="
input double   FirstTPMultiplier   = 1.5;      // First TP at R multiple
input double   PartialClosePercent = 33.0;     // Partial close percentage at 1R
input double   TrailingStopR       = 1.0;      // Move SL every R multiple

input group "=== Pattern Settings ==="
input bool     UseEngulfing        = true;     // Use Engulfing Pattern
input bool     UsePinBar           = true;     // Use Pin Bar Pattern
input bool     UseMorningStar      = true;     // Use Morning/Evening Star
input bool     UseInsideBar        = true;     // Use Inside Bar Pattern
input double   PinBarRatio         = 2.5;      // Pin bar wick/body ratio
input double   EngulfingMinRatio   = 1.5;      // Engulfing minimum body ratio

input group "=== Support/Resistance Settings ==="
input int      SwingLookback       = 20;       // Bars for swing detection
input int      SwingStrength       = 3;        // Bars on each side for swing
input double   SRZoneATRMultiple   = 0.5;      // S/R zone width (ATR multiple)
input int      MinTouchesForSR     = 2;        // Minimum touches for valid S/R

input group "=== Trend Filter ==="
input bool     UseTrendFilter      = true;     // Use trend filter
input int      TrendEMAPeriod      = 50;       // EMA period for trend
input int      FastEMAPeriod       = 20;       // Fast EMA for trend confirmation

input group "=== Time Filter ==="
input bool     UseTimeFilter       = true;     // Use time filter
input int      StartHour           = 8;        // Trading start hour (server time)
input int      EndHour             = 18;       // Trading end hour (server time)
input bool     TradeFriday         = true;     // Trade on Friday

input group "=== Weekend Protection ==="
input bool     CloseBeforeWeekend  = true;     // Close all positions before weekend
input int      FridayCloseHour     = 20;       // Hour to close positions on Friday (server time)
input int      FridayCloseMinute   = 0;        // Minute to close positions on Friday

input group "=== General Settings ==="
input int      MagicNumber         = 123456;   // Magic number
input int      Slippage            = 10;       // Maximum slippage
input string   TradeComment        = "PA_EA";  // Trade comment

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  positionInfo;
CAccountInfo   accountInfo;
CSymbolInfo    symbolInfo;

// Handles for indicators
int handleEMA50;
int handleEMA20;
int handleATR;
int handleADX;

// Arrays for S/R levels
double SupportLevels[];
double ResistanceLevels[];
datetime SRTimestamps[];

// Trade tracking
struct TradeInfo {
   ulong    ticket;
   double   entryPrice;
   double   stopLoss;
   double   takeProfit1;
   double   originalLots;
   double   riskAmount;
   bool     partialClosed;
   int      trailingRLevel;
};

TradeInfo activeTradesInfo[];

// Consecutive loss tracking
int g_consecutiveLosses = 0;               // Track consecutive losing trades
datetime g_pauseUntilTime = 0;             // Time when trading can resume after pause

// Pattern detection results
enum ENUM_PATTERN {
   PATTERN_NONE = 0,
   PATTERN_BULLISH_ENGULFING,
   PATTERN_BEARISH_ENGULFING,
   PATTERN_BULLISH_PINBAR,
   PATTERN_BEARISH_PINBAR,
   PATTERN_MORNING_STAR,
   PATTERN_EVENING_STAR,
   PATTERN_BULLISH_INSIDE,
   PATTERN_BEARISH_INSIDE
};

// Trend direction
enum ENUM_TREND {
   TREND_NONE = 0,
   TREND_UP,
   TREND_DOWN
};

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize symbol info
   if(!symbolInfo.Name(_Symbol))
   {
      Print("Failed to initialize symbol info");
      return INIT_FAILED;
   }
   
   // Initialize trade object
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   // Create indicator handles
   handleEMA50 = iMA(_Symbol, PERIOD_CURRENT, TrendEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA20 = iMA(_Symbol, PERIOD_CURRENT, FastEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   handleATR = iATR(_Symbol, PERIOD_CURRENT, 14);
   handleADX = iADX(_Symbol, PERIOD_CURRENT, ADXPeriod);
   
   if(handleEMA50 == INVALID_HANDLE || handleEMA20 == INVALID_HANDLE || handleATR == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles");
      return INIT_FAILED;
   }
   
   if(UseADXFilter && handleADX == INVALID_HANDLE)
   {
      Print("Failed to create ADX indicator handle");
      return INIT_FAILED;
   }
   
   // Initialize arrays
   ArrayResize(SupportLevels, 0);
   ArrayResize(ResistanceLevels, 0);
   ArrayResize(activeTradesInfo, 0);
   
   Print("Price Action EA initialized successfully");
   Print("Risk: ", RiskPercent, "% | Max Trades: ", MaxOpenTrades);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleEMA50 != INVALID_HANDLE) IndicatorRelease(handleEMA50);
   if(handleEMA20 != INVALID_HANDLE) IndicatorRelease(handleEMA20);
   if(handleATR != INVALID_HANDLE) IndicatorRelease(handleATR);
   if(handleADX != INVALID_HANDLE) IndicatorRelease(handleADX);
   
   Print("Price Action EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for weekend position closure first (runs every tick)
   if(CloseBeforeWeekend && CheckWeekendClose())
   {
      return; // Don't process anything else while closing for weekend
   }
   
   // Check for new bar
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   
   if(currentBarTime == lastBarTime)
   {
      // Manage existing trades on every tick
      ManageOpenTrades();
      return;
   }
   lastBarTime = currentBarTime;
   
   // New bar logic
   symbolInfo.RefreshRates();
   
   // Update S/R levels
   UpdateSupportResistanceLevels();
   
   // Check time filter
   if(UseTimeFilter && !IsWithinTradingHours())
      return;
   
   // Check if trading is paused due to consecutive losses
   if(IsTradingPaused())
      return;
   
   // Check minimum volatility filter
   if(!CheckMinATR())
      return;
   
   // Check ADX filter for ranging markets
   if(!CheckADXFilter())
      return;
   
   // Check max trades
   if(CountOpenTrades() >= MaxOpenTrades)
      return;
   
   // Get current trend
   ENUM_TREND currentTrend = GetTrendDirection();
   
   // Detect patterns on completed bar (index 1)
   ENUM_PATTERN pattern = DetectCandlestickPattern(1);
   
   if(pattern == PATTERN_NONE)
      return;
   
   // Check if pattern aligns with trend and S/R
   if(ShouldTakeTrade(pattern, currentTrend))
   {
      ExecuteTrade(pattern);
   }
}

//+------------------------------------------------------------------+
//| Candlestick Pattern Detection                                     |
//+------------------------------------------------------------------+
ENUM_PATTERN DetectCandlestickPattern(int shift)
{
   ENUM_PATTERN pattern = PATTERN_NONE;
   
   // Get candle data
   double open1 = iOpen(_Symbol, PERIOD_CURRENT, shift);
   double close1 = iClose(_Symbol, PERIOD_CURRENT, shift);
   double high1 = iHigh(_Symbol, PERIOD_CURRENT, shift);
   double low1 = iLow(_Symbol, PERIOD_CURRENT, shift);
   
   double open2 = iOpen(_Symbol, PERIOD_CURRENT, shift + 1);
   double close2 = iClose(_Symbol, PERIOD_CURRENT, shift + 1);
   double high2 = iHigh(_Symbol, PERIOD_CURRENT, shift + 1);
   double low2 = iLow(_Symbol, PERIOD_CURRENT, shift + 1);
   
   double open3 = iOpen(_Symbol, PERIOD_CURRENT, shift + 2);
   double close3 = iClose(_Symbol, PERIOD_CURRENT, shift + 2);
   double high3 = iHigh(_Symbol, PERIOD_CURRENT, shift + 2);
   double low3 = iLow(_Symbol, PERIOD_CURRENT, shift + 2);
   
   // Calculate body and wick sizes
   double body1 = MathAbs(close1 - open1);
   double body2 = MathAbs(close2 - open2);
   double upperWick1 = high1 - MathMax(open1, close1);
   double lowerWick1 = MathMin(open1, close1) - low1;
   double range1 = high1 - low1;
   
   // Get ATR for minimum body size filter
   double atr[];
   ArraySetAsSeries(atr, true);
   double minBody = symbolInfo.Point() * 5;  // Fallback minimum
   
   if(CopyBuffer(handleATR, 0, 0, 1, atr) >= 1)
   {
      // Minimum body must be MinBodyATRRatio * ATR
      double minBodyATR = atr[0] * MinBodyATRRatio;
      if(minBodyATR > minBody)
         minBody = minBodyATR;
   }
   
   // Early exit: if signal candle body is too small relative to ATR, skip
   if(MinBodyATRRatio > 0 && body1 < minBody)
   {
      return PATTERN_NONE;  // Candle too small - likely noise
   }
   
   //--- Engulfing Pattern Detection ---
   if(UseEngulfing)
   {
      // Bullish Engulfing: Previous bearish, current bullish that engulfs
      if(close2 < open2 && close1 > open1) // Previous red, current green
      {
         if(open1 <= close2 && close1 >= open2) // Current body engulfs previous
         {
            if(body1 > body2 * EngulfingMinRatio && body1 > minBody)
            {
               pattern = PATTERN_BULLISH_ENGULFING;
               Print("Bullish Engulfing detected at bar ", shift);
            }
         }
      }
      
      // Bearish Engulfing: Previous bullish, current bearish that engulfs
      if(close2 > open2 && close1 < open1) // Previous green, current red
      {
         if(open1 >= close2 && close1 <= open2) // Current body engulfs previous
         {
            if(body1 > body2 * EngulfingMinRatio && body1 > minBody)
            {
               pattern = PATTERN_BEARISH_ENGULFING;
               Print("Bearish Engulfing detected at bar ", shift);
            }
         }
      }
   }
   
   //--- Pin Bar Detection ---
   if(UsePinBar && pattern == PATTERN_NONE)
   {
      if(range1 > minBody * 2) // Ensure candle has reasonable range
      {
         // Bullish Pin Bar: Long lower wick, small body at top
         if(lowerWick1 > body1 * PinBarRatio && upperWick1 < body1)
         {
            if(MathMax(open1, close1) > low1 + range1 * 0.7)
            {
               pattern = PATTERN_BULLISH_PINBAR;
               Print("Bullish Pin Bar detected at bar ", shift);
            }
         }
         
         // Bearish Pin Bar: Long upper wick, small body at bottom
         if(upperWick1 > body1 * PinBarRatio && lowerWick1 < body1)
         {
            if(MathMin(open1, close1) < high1 - range1 * 0.7)
            {
               pattern = PATTERN_BEARISH_PINBAR;
               Print("Bearish Pin Bar detected at bar ", shift);
            }
         }
      }
   }
   
   //--- Morning/Evening Star Detection ---
   if(UseMorningStar && pattern == PATTERN_NONE)
   {
      double body3 = MathAbs(close3 - open3);
      double minStarBody = body3 * 0.3;
      
      // Morning Star: Bearish -> Small body -> Bullish
      if(close3 < open3 && body3 > minBody) // First is bearish
      {
         if(body2 < minStarBody) // Middle is small (doji-like)
         {
            if(close1 > open1 && body1 > minBody) // Third is bullish
            {
               if(close1 > (open3 + close3) / 2) // Closes above midpoint of first
               {
                  if(high2 < low3 || low2 < low3) // Gap or lower
                  {
                     pattern = PATTERN_MORNING_STAR;
                     Print("Morning Star detected at bar ", shift);
                  }
               }
            }
         }
      }
      
      // Evening Star: Bullish -> Small body -> Bearish
      if(close3 > open3 && body3 > minBody) // First is bullish
      {
         if(body2 < minStarBody) // Middle is small
         {
            if(close1 < open1 && body1 > minBody) // Third is bearish
            {
               if(close1 < (open3 + close3) / 2) // Closes below midpoint of first
               {
                  if(low2 > high3 || high2 > high3) // Gap or higher
                  {
                     pattern = PATTERN_EVENING_STAR;
                     Print("Evening Star detected at bar ", shift);
                  }
               }
            }
         }
      }
   }
   
   //--- Inside Bar Detection ---
   if(UseInsideBar && pattern == PATTERN_NONE)
   {
      // Inside bar: Current candle is completely within previous candle
      if(high1 < high2 && low1 > low2)
      {
         // Determine direction based on close relative to range
         double midPoint = (high2 + low2) / 2;
         
         if(close1 > midPoint && body1 > minBody)
         {
            pattern = PATTERN_BULLISH_INSIDE;
            Print("Bullish Inside Bar detected at bar ", shift);
         }
         else if(close1 < midPoint && body1 > minBody)
         {
            pattern = PATTERN_BEARISH_INSIDE;
            Print("Bearish Inside Bar detected at bar ", shift);
         }
      }
   }
   
   return pattern;
}

//+------------------------------------------------------------------+
//| Support/Resistance Level Detection                                |
//+------------------------------------------------------------------+
void UpdateSupportResistanceLevels()
{
   ArrayResize(SupportLevels, 0);
   ArrayResize(ResistanceLevels, 0);
   
   // Get ATR for zone width
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(handleATR, 0, 0, 1, atr) < 1) return;
   
   double zoneWidth = atr[0] * SRZoneATRMultiple;
   
   // Find swing highs and lows
   double swingHighs[];
   double swingLows[];
   ArrayResize(swingHighs, 0);
   ArrayResize(swingLows, 0);
   
   for(int i = SwingStrength; i < SwingLookback; i++)
   {
      if(IsSwingHigh(i, SwingStrength))
      {
         double high = iHigh(_Symbol, PERIOD_CURRENT, i);
         int size = ArraySize(swingHighs);
         ArrayResize(swingHighs, size + 1);
         swingHighs[size] = high;
      }
      
      if(IsSwingLow(i, SwingStrength))
      {
         double low = iLow(_Symbol, PERIOD_CURRENT, i);
         int size = ArraySize(swingLows);
         ArrayResize(swingLows, size + 1);
         swingLows[size] = low;
      }
   }
   
   // Group nearby levels and count touches
   ProcessSRLevels(swingHighs, ResistanceLevels, zoneWidth);
   ProcessSRLevels(swingLows, SupportLevels, zoneWidth);
}

//+------------------------------------------------------------------+
//| Process and group S/R levels                                      |
//+------------------------------------------------------------------+
void ProcessSRLevels(double &swingPoints[], double &levels[], double zoneWidth)
{
   int count = ArraySize(swingPoints);
   if(count == 0) return;
   
   // Sort levels
   ArraySort(swingPoints);
   
   // Group nearby levels
   double currentLevel = swingPoints[0];
   int touches = 1;
   
   for(int i = 1; i < count; i++)
   {
      if(MathAbs(swingPoints[i] - currentLevel) <= zoneWidth)
      {
         // Same zone - average the levels and increment touches
         currentLevel = (currentLevel * touches + swingPoints[i]) / (touches + 1);
         touches++;
      }
      else
      {
         // Different zone - save previous if valid
         if(touches >= MinTouchesForSR)
         {
            int size = ArraySize(levels);
            ArrayResize(levels, size + 1);
            levels[size] = currentLevel;
         }
         currentLevel = swingPoints[i];
         touches = 1;
      }
   }
   
   // Don't forget the last group
   if(touches >= MinTouchesForSR)
   {
      int size = ArraySize(levels);
      ArrayResize(levels, size + 1);
      levels[size] = currentLevel;
   }
}

//+------------------------------------------------------------------+
//| Check if bar is a swing high                                      |
//+------------------------------------------------------------------+
bool IsSwingHigh(int bar, int strength)
{
   double high = iHigh(_Symbol, PERIOD_CURRENT, bar);
   
   for(int i = 1; i <= strength; i++)
   {
      if(iHigh(_Symbol, PERIOD_CURRENT, bar - i) >= high) return false;
      if(iHigh(_Symbol, PERIOD_CURRENT, bar + i) >= high) return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if bar is a swing low                                       |
//+------------------------------------------------------------------+
bool IsSwingLow(int bar, int strength)
{
   double low = iLow(_Symbol, PERIOD_CURRENT, bar);
   
   for(int i = 1; i <= strength; i++)
   {
      if(iLow(_Symbol, PERIOD_CURRENT, bar - i) <= low) return false;
      if(iLow(_Symbol, PERIOD_CURRENT, bar + i) <= low) return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Get current trend direction                                       |
//+------------------------------------------------------------------+
ENUM_TREND GetTrendDirection()
{
   if(!UseTrendFilter) return TREND_NONE;
   
   double ema50[], ema20[];
   ArraySetAsSeries(ema50, true);
   ArraySetAsSeries(ema20, true);
   
   if(CopyBuffer(handleEMA50, 0, 0, 3, ema50) < 3) return TREND_NONE;
   if(CopyBuffer(handleEMA20, 0, 0, 3, ema20) < 3) return TREND_NONE;
   
   double currentPrice = symbolInfo.Bid();
   
   // Strong uptrend: Price above both EMAs, fast EMA above slow EMA
   if(currentPrice > ema50[1] && currentPrice > ema20[1] && ema20[1] > ema50[1])
   {
      // Check EMA slopes
      if(ema50[0] > ema50[2] && ema20[0] > ema20[2])
         return TREND_UP;
   }
   
   // Strong downtrend: Price below both EMAs, fast EMA below slow EMA
   if(currentPrice < ema50[1] && currentPrice < ema20[1] && ema20[1] < ema50[1])
   {
      // Check EMA slopes
      if(ema50[0] < ema50[2] && ema20[0] < ema20[2])
         return TREND_DOWN;
   }
   
   return TREND_NONE;
}

//+------------------------------------------------------------------+
//| Check if price is near support level                              |
//+------------------------------------------------------------------+
bool IsNearSupport(double price, double &nearestLevel)
{
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(handleATR, 0, 0, 1, atr) < 1) return false;
   
   double tolerance = atr[0] * SRZoneATRMultiple;
   
   for(int i = 0; i < ArraySize(SupportLevels); i++)
   {
      if(MathAbs(price - SupportLevels[i]) <= tolerance)
      {
         nearestLevel = SupportLevels[i];
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check if price is near resistance level                           |
//+------------------------------------------------------------------+
bool IsNearResistance(double price, double &nearestLevel)
{
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(handleATR, 0, 0, 1, atr) < 1) return false;
   
   double tolerance = atr[0] * SRZoneATRMultiple;
   
   for(int i = 0; i < ArraySize(ResistanceLevels); i++)
   {
      if(MathAbs(price - ResistanceLevels[i]) <= tolerance)
      {
         nearestLevel = ResistanceLevels[i];
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check if potential R:R meets minimum requirement                  |
//+------------------------------------------------------------------+
bool CheckMinimumRR(double entryPrice, double stopLoss, bool isBuy)
{
    if(MinimumRRFilter <= 0)
        return true;  // Filter disabled
    
    double stopDistance = MathAbs(entryPrice - stopLoss);
    if(stopDistance == 0)
        return false;
    
    // Calculate distance to nearest opposite S/R zone
    double targetDistance = 0;
    
    if(isBuy)
    {
        // Find nearest resistance zone above entry
        for(int i = 0; i < ArraySize(ResistanceLevels); i++)
        {
            if(ResistanceLevels[i] > entryPrice)
            {
                targetDistance = ResistanceLevels[i] - entryPrice;
                break;
            }
        }
        // If no resistance found, use default R:R target
        if(targetDistance == 0)
            targetDistance = stopDistance * RiskRewardRatio;
    }
    else
    {
        // Find nearest support zone below entry
        for(int i = ArraySize(SupportLevels) - 1; i >= 0; i--)
        {
            if(SupportLevels[i] < entryPrice)
            {
                targetDistance = entryPrice - SupportLevels[i];
                break;
            }
        }
        // If no support found, use default R:R target
        if(targetDistance == 0)
            targetDistance = stopDistance * RiskRewardRatio;
    }
    
    double actualRR = targetDistance / stopDistance;
    
    if(actualRR < MinimumRRFilter)
    {
        Print("Trade skipped: Actual R:R ", DoubleToString(actualRR, 2),
              " below minimum ", DoubleToString(MinimumRRFilter, 2));
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check if current volatility meets minimum requirement             |
//+------------------------------------------------------------------+
bool CheckMinATR()
{
    if(MinATRFilter <= 0)
        return true;  // Filter disabled
    
    double atr[];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(handleATR, 0, 0, 1, atr) < 1)
        return false;
    
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double atrPercent = (atr[0] / currentPrice) * 100;
    
    if(atrPercent < MinATRFilter)
    {
        Print("Trade skipped: ATR ", DoubleToString(atrPercent, 3),
              "% below minimum ", DoubleToString(MinATRFilter, 3), "%");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check if ADX indicates trending market                             |
//+------------------------------------------------------------------+
bool CheckADXFilter()
{
    if(!UseADXFilter || MinADXForTrend <= 0)
        return true;  // Filter disabled
    
    if(handleADX == INVALID_HANDLE)
        return true;  // ADX not available
    
    double adxMain[];
    ArraySetAsSeries(adxMain, true);
    
    // ADX main line is buffer 0
    if(CopyBuffer(handleADX, 0, 0, 1, adxMain) < 1)
    {
        Print("Failed to copy ADX buffer");
        return true;  // Allow trade if we can't read ADX
    }
    
    if(adxMain[0] < MinADXForTrend)
    {
        Print("Trade skipped: ADX ", DoubleToString(adxMain[0], 2),
              " below minimum ", DoubleToString(MinADXForTrend, 2), " (ranging market)");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check if trading is paused due to consecutive losses              |
//+------------------------------------------------------------------+
bool IsTradingPaused()
{
    if(MaxConsecutiveLosses <= 0)
        return false;  // Feature disabled
    
    if(g_pauseUntilTime > 0 && TimeCurrent() < g_pauseUntilTime)
    {
        // Still in pause period
        return true;
    }
    
    // Reset pause if time has passed
    if(g_pauseUntilTime > 0 && TimeCurrent() >= g_pauseUntilTime)
    {
        g_pauseUntilTime = 0;
        g_consecutiveLosses = 0;
        Print("Trading resumed after consecutive loss pause");
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Update consecutive loss counter after trade closes                |
//+------------------------------------------------------------------+
void UpdateConsecutiveLosses(double profit)
{
    if(MaxConsecutiveLosses <= 0)
        return;  // Feature disabled
    
    if(profit < 0)
    {
        g_consecutiveLosses++;
        Print("Consecutive losses: ", g_consecutiveLosses);
        
        if(g_consecutiveLosses >= MaxConsecutiveLosses)
        {
            g_pauseUntilTime = TimeCurrent() + PauseBarsAfterLosses * PeriodSeconds();
            Print("Max consecutive losses reached. Trading paused until ",
                  TimeToString(g_pauseUntilTime));
        }
    }
    else if(profit > 0)
    {
        g_consecutiveLosses = 0;  // Reset on winning trade
    }
}

//+------------------------------------------------------------------+
//| Should take trade based on pattern, trend, and S/R                |
//+------------------------------------------------------------------+
bool ShouldTakeTrade(ENUM_PATTERN pattern, ENUM_TREND trend)
{
   double currentPrice = symbolInfo.Bid();
   double nearestLevel = 0;
   
   // Bullish patterns
   if(pattern == PATTERN_BULLISH_ENGULFING || pattern == PATTERN_BULLISH_PINBAR || 
      pattern == PATTERN_MORNING_STAR || pattern == PATTERN_BULLISH_INSIDE)
   {
      // Must be in uptrend or no trend filter
      if(UseTrendFilter && trend != TREND_UP && trend != TREND_NONE)
         return false;
      
      // Should be near support
      if(IsNearSupport(currentPrice, nearestLevel))
      {
         Print("Bullish pattern near support at ", nearestLevel);
         return true;
      }
      
      // Also accept if just above recent swing low (pullback in uptrend)
      if(trend == TREND_UP)
      {
         double recentLow = iLow(_Symbol, PERIOD_CURRENT, iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, 10, 1));
         double atr[];
         ArraySetAsSeries(atr, true);
         if(CopyBuffer(handleATR, 0, 0, 1, atr) >= 1)
         {
            if(currentPrice < recentLow + atr[0] * 1.5)
            {
               Print("Bullish pattern on pullback in uptrend");
               return true;
            }
         }
      }
   }
   
   // Bearish patterns
   if(pattern == PATTERN_BEARISH_ENGULFING || pattern == PATTERN_BEARISH_PINBAR || 
      pattern == PATTERN_EVENING_STAR || pattern == PATTERN_BEARISH_INSIDE)
   {
      // Must be in downtrend or no trend filter
      if(UseTrendFilter && trend != TREND_DOWN && trend != TREND_NONE)
         return false;
      
      // Should be near resistance
      if(IsNearResistance(currentPrice, nearestLevel))
      {
         Print("Bearish pattern near resistance at ", nearestLevel);
         return true;
      }
      
      // Also accept if just below recent swing high (pullback in downtrend)
      if(trend == TREND_DOWN)
      {
         double recentHigh = iHigh(_Symbol, PERIOD_CURRENT, iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, 10, 1));
         double atr[];
         ArraySetAsSeries(atr, true);
         if(CopyBuffer(handleATR, 0, 0, 1, atr) >= 1)
         {
            if(currentPrice > recentHigh - atr[0] * 1.5)
            {
               Print("Bearish pattern on pullback in downtrend");
               return true;
            }
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Execute trade based on pattern                                    |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_PATTERN pattern)
{
   // Determine trade direction
   bool isBuy = (pattern == PATTERN_BULLISH_ENGULFING || pattern == PATTERN_BULLISH_PINBAR || 
                 pattern == PATTERN_MORNING_STAR || pattern == PATTERN_BULLISH_INSIDE);
   
   // Get signal candle data for stop loss
   double signalHigh = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double signalLow = iLow(_Symbol, PERIOD_CURRENT, 1);
   
   // For multi-candle patterns, use appropriate range
   if(pattern == PATTERN_MORNING_STAR || pattern == PATTERN_EVENING_STAR)
   {
      signalHigh = MathMax(signalHigh, MathMax(iHigh(_Symbol, PERIOD_CURRENT, 2), iHigh(_Symbol, PERIOD_CURRENT, 3)));
      signalLow = MathMin(signalLow, MathMin(iLow(_Symbol, PERIOD_CURRENT, 2), iLow(_Symbol, PERIOD_CURRENT, 3)));
   }
   
   // Get ATR for buffer
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(handleATR, 0, 0, 1, atr) < 1)
   {
      Print("Failed to get ATR");
      return;
   }
   
   // Use StopLossBufferATR parameter for wider stops to avoid noise
   double buffer = atr[0] * StopLossBufferATR;
   
   double entryPrice, stopLoss, takeProfit1, takeProfit2;
   
   if(isBuy)
   {
      entryPrice = symbolInfo.Ask();
      stopLoss = signalLow - buffer;
      double risk = entryPrice - stopLoss;
      takeProfit1 = entryPrice + risk * FirstTPMultiplier;
      takeProfit2 = entryPrice + risk * RiskRewardRatio;
   }
   else
   {
      entryPrice = symbolInfo.Bid();
      stopLoss = signalHigh + buffer;
      double risk = stopLoss - entryPrice;
      takeProfit1 = entryPrice - risk * FirstTPMultiplier;
      takeProfit2 = entryPrice - risk * RiskRewardRatio;
   }
   
   // Check minimum R:R filter before proceeding
   if(!CheckMinimumRR(entryPrice, stopLoss, isBuy))
   {
      return;  // Skip if R:R too low
   }
   
   // Calculate lot size based on risk
   double lotSize = CalculateLotSize(entryPrice, stopLoss);
   if(lotSize <= 0)
   {
      Print("Invalid lot size calculated");
      return;
   }
   
   // Normalize prices
   stopLoss = NormalizeDouble(stopLoss, symbolInfo.Digits());
   takeProfit2 = NormalizeDouble(takeProfit2, symbolInfo.Digits());
   
   // Execute trade
   string comment = TradeComment + "_" + GetPatternName(pattern);
   bool result;
   
   if(isBuy)
   {
      result = trade.Buy(lotSize, _Symbol, 0, stopLoss, takeProfit2, comment);
   }
   else
   {
      result = trade.Sell(lotSize, _Symbol, 0, stopLoss, takeProfit2, comment);
   }
   
   if(result)
   {
      ulong ticket = trade.ResultOrder();
      Print("Trade opened: ", GetPatternName(pattern), " | Ticket: ", ticket, 
            " | Lots: ", lotSize, " | SL: ", stopLoss, " | TP: ", takeProfit2);
      
      // Add to tracking array
      TradeInfo info;
      info.ticket = ticket;
      info.entryPrice = entryPrice;
      info.stopLoss = stopLoss;
      info.takeProfit1 = takeProfit1;
      info.originalLots = lotSize;
      info.riskAmount = MathAbs(entryPrice - stopLoss);
      info.partialClosed = false;
      info.trailingRLevel = 0;
      
      int size = ArraySize(activeTradesInfo);
      ArrayResize(activeTradesInfo, size + 1);
      activeTradesInfo[size] = info;
   }
   else
   {
      Print("Trade failed: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk percentage                       |
//+------------------------------------------------------------------+
double CalculateLotSize(double entryPrice, double stopLoss)
{
   double balance = accountInfo.Balance();
   double riskMoney = balance * RiskPercent / 100.0;
   
   double stopLossPips = MathAbs(entryPrice - stopLoss) / symbolInfo.Point();
   double pipValue = symbolInfo.TickValue() / symbolInfo.TickSize() * symbolInfo.Point();
   
   if(pipValue == 0 || stopLossPips == 0)
      return 0;
   
   double lotSize = riskMoney / (stopLossPips * pipValue);
   
   // Round to valid lot step
   double lotStep = symbolInfo.LotsStep();
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   
   // Ensure within limits
   lotSize = MathMax(lotSize, symbolInfo.LotsMin());
   lotSize = MathMin(lotSize, symbolInfo.LotsMax());
   
   return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
//| Manage open trades - partial close and trailing stop              |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
   for(int i = ArraySize(activeTradesInfo) - 1; i >= 0; i--)
   {
      ulong ticket = activeTradesInfo[i].ticket;
      
      if(!positionInfo.SelectByTicket(ticket))
      {
         // Position closed - remove from tracking
         RemoveTradeInfo(i);
         continue;
      }
      
      double currentPrice = positionInfo.PriceCurrent();
      double entryPrice = activeTradesInfo[i].entryPrice;
      double riskAmount = activeTradesInfo[i].riskAmount;
      bool isBuy = (positionInfo.PositionType() == POSITION_TYPE_BUY);
      
      double profitInR;
      if(isBuy)
         profitInR = (currentPrice - entryPrice) / riskAmount;
      else
         profitInR = (entryPrice - currentPrice) / riskAmount;
      
      //--- Partial Close at 1R ---
      if(!activeTradesInfo[i].partialClosed && profitInR >= FirstTPMultiplier)
      {
         double currentLots = positionInfo.Volume();
         double closeLots = NormalizeDouble(currentLots * (PartialClosePercent / 100.0), 2);
         closeLots = MathMax(closeLots, symbolInfo.LotsMin());
         
         if(closeLots < currentLots)
         {
            if(trade.PositionClosePartial(ticket, closeLots))
            {
               Print("Partial close at 1R: ", closeLots, " lots | Ticket: ", ticket);
               activeTradesInfo[i].partialClosed = true;
               
               // Move SL to breakeven
               double newSL = entryPrice;
               if(isBuy)
                  newSL = entryPrice + symbolInfo.Point() * 5; // Small buffer above entry
               else
                  newSL = entryPrice - symbolInfo.Point() * 5; // Small buffer below entry
               
               trade.PositionModify(ticket, newSL, positionInfo.TakeProfit());
               activeTradesInfo[i].stopLoss = newSL;
               activeTradesInfo[i].trailingRLevel = 1;
               Print("SL moved to breakeven: ", newSL);
            }
         }
      }
      
      //--- Trailing Stop every 1R ---
      if(activeTradesInfo[i].partialClosed)
      {
         int currentRLevel = (int)MathFloor(profitInR / TrailingStopR);
         
         if(currentRLevel > activeTradesInfo[i].trailingRLevel)
         {
            double newSL;
            
            if(isBuy)
            {
               // Trail SL to previous R level
               newSL = entryPrice + riskAmount * (currentRLevel - 1) * TrailingStopR;
               newSL = NormalizeDouble(newSL, symbolInfo.Digits());
               
               if(newSL > activeTradesInfo[i].stopLoss)
               {
                  if(trade.PositionModify(ticket, newSL, positionInfo.TakeProfit()))
                  {
                     Print("Trailing SL moved to ", newSL, " (", currentRLevel, "R profit) | Ticket: ", ticket);
                     activeTradesInfo[i].stopLoss = newSL;
                     activeTradesInfo[i].trailingRLevel = currentRLevel;
                  }
               }
            }
            else
            {
               // Trail SL for sell position
               newSL = entryPrice - riskAmount * (currentRLevel - 1) * TrailingStopR;
               newSL = NormalizeDouble(newSL, symbolInfo.Digits());
               
               if(newSL < activeTradesInfo[i].stopLoss)
               {
                  if(trade.PositionModify(ticket, newSL, positionInfo.TakeProfit()))
                  {
                     Print("Trailing SL moved to ", newSL, " (", currentRLevel, "R profit) | Ticket: ", ticket);
                     activeTradesInfo[i].stopLoss = newSL;
                     activeTradesInfo[i].trailingRLevel = currentRLevel;
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Remove trade info from tracking array                             |
//+------------------------------------------------------------------+
void RemoveTradeInfo(int index)
{
   int size = ArraySize(activeTradesInfo);
   for(int i = index; i < size - 1; i++)
   {
      activeTradesInfo[i] = activeTradesInfo[i + 1];
   }
   ArrayResize(activeTradesInfo, size - 1);
}

//+------------------------------------------------------------------+
//| Count open trades for this EA                                     |
//+------------------------------------------------------------------+
int CountOpenTrades()
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
//| Check if within trading hours                                     |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   // Check day of week
   if(dt.day_of_week == 0 || dt.day_of_week == 6) // Sunday or Saturday
      return false;
   
   if(!TradeFriday && dt.day_of_week == 5)
      return false;
   
   // Check hours
   if(dt.hour < StartHour || dt.hour >= EndHour)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Check and close positions before weekend                          |
//+------------------------------------------------------------------+
bool CheckWeekendClose()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   // Only check on Friday (day_of_week == 5)
   if(dt.day_of_week != 5)
      return false;
   
   // Check if we've reached the close time
   if(dt.hour < FridayCloseHour)
      return false;
   
   if(dt.hour == FridayCloseHour && dt.min < FridayCloseMinute)
      return false;
   
   // Time to close all positions
   int closedCount = CloseAllPositions();
   
   if(closedCount > 0)
   {
      Print("Weekend protection: Closed ", closedCount, " position(s) at ",
            TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES));
   }
   
   // Return true if we're in weekend close period (to prevent new trades)
   return true;
}

//+------------------------------------------------------------------+
//| Close all positions for this EA                                   |
//+------------------------------------------------------------------+
int CloseAllPositions()
{
   int closedCount = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == MagicNumber)
         {
            ulong ticket = positionInfo.Ticket();
            double profit = positionInfo.Profit();
            
            if(trade.PositionClose(ticket))
            {
               Print("Weekend close: Position #", ticket, " closed with profit: ", profit);
               closedCount++;
            }
            else
            {
               Print("Weekend close: Failed to close position #", ticket, " Error: ", GetLastError());
            }
         }
      }
   }
   
   // Clear tracking array for closed positions
   if(closedCount > 0)
   {
      ArrayResize(activeTradesInfo, 0);
   }
   
   return closedCount;
}

//+------------------------------------------------------------------+
//| Get pattern name for logging                                      |
//+------------------------------------------------------------------+
string GetPatternName(ENUM_PATTERN pattern)
{
   switch(pattern)
   {
      case PATTERN_BULLISH_ENGULFING: return "BullEngulf";
      case PATTERN_BEARISH_ENGULFING: return "BearEngulf";
      case PATTERN_BULLISH_PINBAR:    return "BullPinBar";
      case PATTERN_BEARISH_PINBAR:    return "BearPinBar";
      case PATTERN_MORNING_STAR:      return "MorningStar";
      case PATTERN_EVENING_STAR:      return "EveningStar";
      case PATTERN_BULLISH_INSIDE:    return "BullInside";
      case PATTERN_BEARISH_INSIDE:    return "BearInside";
      default:                        return "Unknown";
   }
}

//+------------------------------------------------------------------+
//| OnTrade event handler                                             |
//+------------------------------------------------------------------+
void OnTrade()
{
   // Sync tracking array with actual positions
   for(int i = ArraySize(activeTradesInfo) - 1; i >= 0; i--)
   {
      if(!positionInfo.SelectByTicket(activeTradesInfo[i].ticket))
      {
         Print("Position ", activeTradesInfo[i].ticket, " closed");
         RemoveTradeInfo(i);
      }
   }
}

//+------------------------------------------------------------------+
//| OnTradeTransaction event handler - track closed position profit   |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   // Only process deal transactions
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   
   // Get deal info
   ulong dealTicket = trans.deal;
   if(dealTicket == 0)
      return;
   
   // Select the deal from history
   if(!HistoryDealSelect(dealTicket))
      return;
   
   // Check if this is our EA's deal
   if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != MagicNumber)
      return;
   
   // Check if this is a closing deal (exit from position)
   ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   if(dealEntry != DEAL_ENTRY_OUT && dealEntry != DEAL_ENTRY_OUT_BY)
      return;
   
   // Get the profit of this closed deal
   double dealProfit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
   double dealSwap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
   double dealCommission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
   
   double totalProfit = dealProfit + dealSwap + dealCommission;
   
   Print("Trade closed - Profit: ", DoubleToString(totalProfit, 2));
   
   // Update consecutive loss counter
   UpdateConsecutiveLosses(totalProfit);
}
//+------------------------------------------------------------------+
