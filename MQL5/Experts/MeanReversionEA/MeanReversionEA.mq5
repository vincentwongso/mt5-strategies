//+------------------------------------------------------------------+
//|                                            MeanReversionEA.mq5   |
//|                                      Mean Reversion EA           |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Mean Reversion EA"
#property link      ""
#property version   "1.00"
#property strict
#property description "Mean Reversion Strategy for ES/NQ Futures"
#property description "With Dynamic Regime-Based Risk Management"

//+------------------------------------------------------------------+
//| Include Files                                                    |
//+------------------------------------------------------------------+
#include <MeanReversionEA/Logger.mqh>
#include <MeanReversionEA/Indicators.mqh>
#include <MeanReversionEA/RiskManager.mqh>
#include <MeanReversionEA/TradeFilters.mqh>
#include <MeanReversionEA/TradeExecutor.mqh>
#include <MeanReversionEA/TrailingStop.mqh>

//+------------------------------------------------------------------+
//| Input Parameters - Indicator Settings                            |
//+------------------------------------------------------------------+
input group "=== Indicator Settings ==="
input int      InpADXPeriod = 14;              // ADX Period
input int      InpATRPeriod = 14;              // ATR Period
input int      InpBBPeriod = 20;               // Bollinger Bands Period
input double   InpBBDeviation = 2.0;           // Bollinger Bands Deviation
input int      InpRSIPeriod = 14;              // RSI Period
input int      InpRSIOversold = 30;            // RSI Oversold Level
input int      InpRSIOverbought = 70;          // RSI Overbought Level
input int      InpADXThreshold = 25;           // ADX Trend Threshold

//+------------------------------------------------------------------+
//| Input Parameters - Risk Management                               |
//+------------------------------------------------------------------+
input group "=== Risk Management ==="
input double   InpRiskPercent = 1.0;           // Risk Per Trade (%)
input double   InpDailyLossLimit = 3.0;        // Daily Loss Limit (%)
input double   InpATRMultiplierTrend = 2.5;    // ATR Multiplier (Trending)
input double   InpATRMultiplierRange = 1.5;    // ATR Multiplier (Ranging)

//+------------------------------------------------------------------+
//| Input Parameters - Trade Filters                                 |
//+------------------------------------------------------------------+
input group "=== Trade Filters ==="
input double   InpSpreadMultiplier = 2.0;      // Max Spread Multiplier
input double   InpMinATR_ES = 5.0;             // Min ATR for ES (points)
input double   InpMinATR_NQ = 20.0;            // Min ATR for NQ (points)
input int      InpCooldownBars = 3;            // Cooldown After Loss (bars)
input int      InpNewsBufferMinutes = 5;       // News Buffer (minutes)
input int      InpMaxSlippageTicks = 3;        // Max Slippage (ticks)

//+------------------------------------------------------------------+
//| Input Parameters - Trading Hours (Eastern Time)                  |
//+------------------------------------------------------------------+
input group "=== Trading Hours (ET) ==="
input int      InpTradingStartHour = 9;        // Trading Start Hour
input int      InpTradingStartMinute = 30;     // Trading Start Minute
input int      InpTradingEndHour = 16;         // Trading End Hour
input int      InpTradingEndMinute = 0;        // Trading End Minute
input int      InpBrokerGMTOffset = -5;        // Broker GMT Offset (for ET conversion)

//+------------------------------------------------------------------+
//| Input Parameters - General Settings                              |
//+------------------------------------------------------------------+
input group "=== General Settings ==="
input ulong    InpMagicNumber = 123456;        // Magic Number
input string   InpTradeComment = "MeanRevEA";  // Trade Comment
input ENUM_LOG_LEVEL InpLogLevel = LOG_LEVEL_INFO; // Log Level
input bool     InpLogToFile = false;           // Log to File

//+------------------------------------------------------------------+
//| Enums                                                            |
//+------------------------------------------------------------------+
enum ENUM_MARKET_REGIME
{
    REGIME_TRENDING,      // Trending (ADX >= threshold)
    REGIME_CONSOLIDATING  // Consolidating (ADX < threshold)
};

enum ENUM_SIGNAL
{
    SIGNAL_NONE,          // No signal
    SIGNAL_BUY,           // Buy signal
    SIGNAL_SELL           // Sell signal
};

//+------------------------------------------------------------------+
//| Global Variables - Module Instances                              |
//+------------------------------------------------------------------+
CIndicators    g_indicators;
CRiskManager   g_riskManager;
CTradeFilters  g_filters;
CTradeExecutor g_executor;
CTrailingStop  g_trailingStop;

//+------------------------------------------------------------------+
//| Global Variables - State                                         |
//+------------------------------------------------------------------+
datetime g_lastBarTime = 0;
bool     g_isInitialized = false;
double   g_minATR = 5.0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    //--- Initialize logger
    if(!g_logger.Initialize(InpTradeComment, InpLogLevel, InpLogToFile))
    {
        Print("Failed to initialize logger");
        return INIT_FAILED;
    }
    
    g_logger.Info("===========================================");
    g_logger.Info("Mean Reversion EA Initializing...");
    g_logger.Info("===========================================");
    
    //--- Validate symbol and set min ATR
    string symbol = _Symbol;
    if(StringFind(symbol, "ES") >= 0 || StringFind(symbol, "SP500") >= 0 || StringFind(symbol, "US500") >= 0)
    {
        g_minATR = InpMinATR_ES;
        g_logger.Info("Symbol detected as ES type. Min ATR: " + DoubleToString(g_minATR, 1));
    }
    else if(StringFind(symbol, "NQ") >= 0 || StringFind(symbol, "NASDAQ") >= 0 || StringFind(symbol, "USTEC") >= 0)
    {
        g_minATR = InpMinATR_NQ;
        g_logger.Info("Symbol detected as NQ type. Min ATR: " + DoubleToString(g_minATR, 1));
    }
    else
    {
        g_minATR = InpMinATR_ES;  // Default to ES
        g_logger.Warning("Symbol not recognized as ES or NQ. Using ES min ATR: " + DoubleToString(g_minATR, 1));
    }
    
    //--- Log configuration
    LogConfiguration();
    
    //--- Initialize modules
    if(!InitializeModules())
    {
        g_logger.Error("Failed to initialize modules");
        return INIT_FAILED;
    }
    
    g_isInitialized = true;
    g_logger.Info("EA Initialized Successfully");
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    g_logger.Info("EA Deinitializing. Reason: " + GetDeinitReasonText(reason));
    
    //--- Cleanup modules
    g_indicators.Deinitialize();
    
    g_logger.Info("EA Deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    if(!g_isInitialized)
        return;
    
    //--- Check for new bar
    if(IsNewBar())
    {
        OnNewBar();
    }
}

//+------------------------------------------------------------------+
//| New bar handler                                                  |
//+------------------------------------------------------------------+
void OnNewBar()
{
    g_logger.Debug("New bar detected at " + TimeToString(TimeCurrent()));
    
    //--- Refresh indicator buffers
    if(!g_indicators.RefreshBuffers(10))
    {
        g_logger.Warning("Failed to refresh indicator buffers");
        return;
    }
    
    //--- Update filters on new bar
    g_filters.OnNewBar();
    
    //--- Check if we have an open position
    if(g_executor.HasOpenPosition())
    {
        //--- Check for exit conditions and update trailing stop
        CheckExitConditions();
        UpdateTrailingStop();
        return;  // Don't look for new entries while in position
    }
    
    //--- Check entry signals
    CheckEntrySignals();
}

//+------------------------------------------------------------------+
//| Check for new bar                                                |
//+------------------------------------------------------------------+
bool IsNewBar()
{
    datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
    
    if(currentBarTime != g_lastBarTime)
    {
        g_lastBarTime = currentBarTime;
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Initialize all modules                                           |
//+------------------------------------------------------------------+
bool InitializeModules()
{
    //--- Set logger references for all modules
    g_indicators.SetLogger(&g_logger);
    g_riskManager.SetLogger(&g_logger);
    g_filters.SetLogger(&g_logger);
    g_executor.SetLogger(&g_logger);
    g_trailingStop.SetLogger(&g_logger);
    
    //--- Initialize indicators
    if(!g_indicators.Initialize(_Symbol, PERIOD_CURRENT,
        InpADXPeriod, InpATRPeriod, InpBBPeriod, InpBBDeviation, InpRSIPeriod))
    {
        g_logger.Error("Failed to initialize indicators");
        return false;
    }
    
    //--- Wait for indicators to have data
    int attempts = 0;
    while(!g_indicators.IsDataReady() && attempts < 10)
    {
        Sleep(100);
        attempts++;
    }
    
    if(!g_indicators.IsDataReady())
    {
        g_logger.Warning("Indicators may not have enough data yet");
    }
    
    //--- Initialize risk manager
    if(!g_riskManager.Initialize(_Symbol, InpRiskPercent, 
        InpATRMultiplierTrend, InpATRMultiplierRange))
    {
        g_logger.Error("Failed to initialize risk manager");
        return false;
    }
    
    //--- Initialize trade filters
    if(!g_filters.Initialize(_Symbol,
        InpTradingStartHour, InpTradingStartMinute,
        InpTradingEndHour, InpTradingEndMinute,
        InpBrokerGMTOffset,
        InpSpreadMultiplier, g_minATR, InpCooldownBars,
        InpNewsBufferMinutes, InpDailyLossLimit))
    {
        g_logger.Error("Failed to initialize trade filters");
        return false;
    }
    
    //--- Initialize trade executor
    if(!g_executor.Initialize(_Symbol, InpMagicNumber, InpTradeComment, InpMaxSlippageTicks))
    {
        g_logger.Error("Failed to initialize trade executor");
        return false;
    }
    
    //--- Initialize trailing stop
    g_trailingStop.Initialize(g_riskManager.GetDigits(), g_riskManager.GetTickSize(),
        InpATRMultiplierTrend, InpATRMultiplierRange);
    
    return true;
}

//+------------------------------------------------------------------+
//| Check for entry signals                                          |
//+------------------------------------------------------------------+
void CheckEntrySignals()
{
    //--- Get indicator values from previous closed bar (shift 1)
    double adx = g_indicators.GetADX(1);
    double atr = g_indicators.GetATR(1);
    double rsi = g_indicators.GetRSI(1);
    double bbUpper = g_indicators.GetBBUpper(1);
    double bbMiddle = g_indicators.GetBBMiddle(1);
    double bbLower = g_indicators.GetBBLower(1);
    
    //--- Get price data from previous closed bar
    double close = iClose(_Symbol, PERIOD_CURRENT, 1);
    double open = iOpen(_Symbol, PERIOD_CURRENT, 1);
    double high = iHigh(_Symbol, PERIOD_CURRENT, 1);
    double low = iLow(_Symbol, PERIOD_CURRENT, 1);
    
    //--- Log indicator values
    g_logger.LogIndicators(adx, atr, rsi, bbUpper, bbMiddle, bbLower);
    
    //--- Check volatility filter
    if(!g_filters.IsVolatilityAcceptable(atr))
    {
        g_logger.LogFilterRejection("Min ATR", StringFormat("ATR=%.2f < Min=%.2f", atr, g_minATR));
        return;
    }
    
    //--- Determine market regime
    bool isTrending = (adx >= InpADXThreshold);
    ENUM_MARKET_REGIME regime = isTrending ? REGIME_TRENDING : REGIME_CONSOLIDATING;
    g_logger.Debug(StringFormat("Market Regime: %s (ADX=%.2f, Threshold=%d)",
        isTrending ? "TRENDING" : "CONSOLIDATING", adx, InpADXThreshold));
    
    //--- Check for LONG entry conditions
    // 1. Price closes below Lower BB
    // 2. RSI < Oversold level
    // 3. Confirmation: Close > Open (bullish bar)
    if(close < bbLower && rsi < InpRSIOversold && close > open)
    {
        g_logger.Info("LONG signal detected!");
        g_logger.Debug(StringFormat("Close=%.5f < BBLower=%.5f, RSI=%.2f < %d, Close > Open",
            close, bbLower, rsi, InpRSIOversold));
        
        if(g_filters.CanTrade(ORDER_TYPE_BUY))
        {
            ExecuteLongEntry(isTrending, atr, bbMiddle, high, low);
        }
        return;
    }
    
    //--- Check for SHORT entry conditions
    // 1. Price closes above Upper BB
    // 2. RSI > Overbought level
    // 3. Confirmation: Close < Open (bearish bar)
    if(close > bbUpper && rsi > InpRSIOverbought && close < open)
    {
        g_logger.Info("SHORT signal detected!");
        g_logger.Debug(StringFormat("Close=%.5f > BBUpper=%.5f, RSI=%.2f > %d, Close < Open",
            close, bbUpper, rsi, InpRSIOverbought));
        
        if(g_filters.CanTrade(ORDER_TYPE_SELL))
        {
            ExecuteShortEntry(isTrending, atr, bbMiddle, high, low);
        }
        return;
    }
}

//+------------------------------------------------------------------+
//| Execute long entry                                               |
//+------------------------------------------------------------------+
void ExecuteLongEntry(bool isTrending, double atr, double bbMiddle, double high, double low)
{
    //--- Calculate stop distance based on regime
    double stopDistance = g_riskManager.CalculateStopDistance(atr, isTrending);
    
    //--- Calculate position size
    double lots = g_riskManager.CalculatePositionSize(stopDistance);
    if(lots <= 0)
    {
        g_logger.Error("Invalid position size calculated");
        return;
    }
    
    //--- Get entry price
    double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    //--- Calculate SL and TP
    double sl = g_riskManager.GetStopLoss(stopDistance, ORDER_TYPE_BUY, entryPrice);
    double tp = g_riskManager.GetTakeProfit(bbMiddle, ORDER_TYPE_BUY, entryPrice);
    
    //--- Execute trade
    if(g_executor.OpenBuy(lots, sl, tp))
    {
        g_logger.LogTradeEntry("BUY", lots, entryPrice, sl, tp);
        
        //--- Initialize trailing stop
        g_trailingStop.OnPositionOpen(ORDER_TYPE_BUY, entryPrice, sl, high, low);
    }
}

//+------------------------------------------------------------------+
//| Execute short entry                                              |
//+------------------------------------------------------------------+
void ExecuteShortEntry(bool isTrending, double atr, double bbMiddle, double high, double low)
{
    //--- Calculate stop distance based on regime
    double stopDistance = g_riskManager.CalculateStopDistance(atr, isTrending);
    
    //--- Calculate position size
    double lots = g_riskManager.CalculatePositionSize(stopDistance);
    if(lots <= 0)
    {
        g_logger.Error("Invalid position size calculated");
        return;
    }
    
    //--- Get entry price
    double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    //--- Calculate SL and TP
    double sl = g_riskManager.GetStopLoss(stopDistance, ORDER_TYPE_SELL, entryPrice);
    double tp = g_riskManager.GetTakeProfit(bbMiddle, ORDER_TYPE_SELL, entryPrice);
    
    //--- Execute trade
    if(g_executor.OpenSell(lots, sl, tp))
    {
        g_logger.LogTradeEntry("SELL", lots, entryPrice, sl, tp);
        
        //--- Initialize trailing stop
        g_trailingStop.OnPositionOpen(ORDER_TYPE_SELL, entryPrice, sl, high, low);
    }
}

//+------------------------------------------------------------------+
//| Check exit conditions                                            |
//+------------------------------------------------------------------+
void CheckExitConditions()
{
    //--- TP and SL are handled by the broker
    //--- We just need to detect when position is closed and update filters
    
    if(!g_executor.HasOpenPosition())
    {
        //--- Position was closed (by TP, SL, or manually)
        double profit = g_executor.GetPositionProfit();
        ENUM_ORDER_TYPE posType = g_executor.GetPositionType();
        
        //--- Notify filters about trade close
        g_filters.OnTradeClose(profit, posType);
        
        //--- Reset trailing stop
        g_trailingStop.Reset();
        
        g_logger.Info("Position closed detected");
    }
}

//+------------------------------------------------------------------+
//| Update trailing stop                                             |
//+------------------------------------------------------------------+
void UpdateTrailingStop()
{
    if(!g_trailingStop.IsActive())
        return;
    
    //--- Get current bar data
    double high = iHigh(_Symbol, PERIOD_CURRENT, 1);
    double low = iLow(_Symbol, PERIOD_CURRENT, 1);
    double atr = g_indicators.GetATR(1);
    double adx = g_indicators.GetADX(1);
    bool isTrending = (adx >= InpADXThreshold);
    
    //--- Update trailing stop calculation
    g_trailingStop.OnNewBar(high, low, atr, isTrending);
    
    //--- If stop needs to be updated, modify the position
    if(g_trailingStop.ShouldUpdateStop())
    {
        double newStop = g_trailingStop.GetCurrentStop();
        
        if(g_executor.ModifyStopLoss(newStop))
        {
            g_logger.Info(StringFormat("Trailing stop updated to %.5f", newStop));
        }
    }
}

//+------------------------------------------------------------------+
//| Log configuration on startup                                     |
//+------------------------------------------------------------------+
void LogConfiguration()
{
    g_logger.Info("--- Configuration ---");
    g_logger.Info(StringFormat("Symbol: %s", _Symbol));
    g_logger.Info(StringFormat("Timeframe: %s", EnumToString(Period())));
    g_logger.Info(StringFormat("Magic Number: %d", InpMagicNumber));
    
    g_logger.Info("--- Indicator Settings ---");
    g_logger.Info(StringFormat("ADX Period: %d, Threshold: %d", InpADXPeriod, InpADXThreshold));
    g_logger.Info(StringFormat("ATR Period: %d", InpATRPeriod));
    g_logger.Info(StringFormat("BB Period: %d, Deviation: %.1f", InpBBPeriod, InpBBDeviation));
    g_logger.Info(StringFormat("RSI Period: %d, Oversold: %d, Overbought: %d", 
        InpRSIPeriod, InpRSIOversold, InpRSIOverbought));
    
    g_logger.Info("--- Risk Management ---");
    g_logger.Info(StringFormat("Risk Per Trade: %.1f%%", InpRiskPercent));
    g_logger.Info(StringFormat("Daily Loss Limit: %.1f%%", InpDailyLossLimit));
    g_logger.Info(StringFormat("ATR Multiplier (Trend): %.1f, (Range): %.1f", 
        InpATRMultiplierTrend, InpATRMultiplierRange));
    
    g_logger.Info("--- Trade Filters ---");
    g_logger.Info(StringFormat("Spread Multiplier: %.1f", InpSpreadMultiplier));
    g_logger.Info(StringFormat("Min ATR: %.1f", g_minATR));
    g_logger.Info(StringFormat("Cooldown Bars: %d", InpCooldownBars));
    g_logger.Info(StringFormat("Max Slippage: %d ticks", InpMaxSlippageTicks));
    
    g_logger.Info("--- Trading Hours (ET) ---");
    g_logger.Info(StringFormat("Start: %02d:%02d, End: %02d:%02d", 
        InpTradingStartHour, InpTradingStartMinute, 
        InpTradingEndHour, InpTradingEndMinute));
}

//+------------------------------------------------------------------+
//| Get deinitialization reason text                                 |
//+------------------------------------------------------------------+
string GetDeinitReasonText(int reason)
{
    switch(reason)
    {
        case REASON_PROGRAM:     return "Program removed";
        case REASON_REMOVE:      return "EA removed from chart";
        case REASON_RECOMPILE:   return "EA recompiled";
        case REASON_CHARTCHANGE: return "Chart symbol or period changed";
        case REASON_CHARTCLOSE:  return "Chart closed";
        case REASON_PARAMETERS:  return "Input parameters changed";
        case REASON_ACCOUNT:     return "Account changed";
        case REASON_TEMPLATE:    return "Template applied";
        case REASON_INITFAILED:  return "OnInit failed";
        case REASON_CLOSE:       return "Terminal closed";
        default:                 return "Unknown reason";
    }
}
//+------------------------------------------------------------------+