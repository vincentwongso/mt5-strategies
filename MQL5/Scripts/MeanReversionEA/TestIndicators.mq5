//+------------------------------------------------------------------+
//|                                               TestIndicators.mq5 |
//|                                      Mean Reversion EA           |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Mean Reversion EA"
#property link      ""
#property version   "1.00"
#property script_show_inputs

#include <MeanReversionEA/Logger.mqh>
#include <MeanReversionEA/Indicators.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input int      InpADXPeriod = 14;              // ADX Period
input int      InpATRPeriod = 14;              // ATR Period
input int      InpBBPeriod = 20;               // Bollinger Bands Period
input double   InpBBDeviation = 2.0;           // Bollinger Bands Deviation
input int      InpRSIPeriod = 14;              // RSI Period
input int      InpBarsToTest = 10;             // Bars to Test

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
    Print("===========================================");
    Print("Testing Indicators Module");
    Print("===========================================");
    Print("Symbol: ", _Symbol);
    Print("Timeframe: ", EnumToString(Period()));
    Print("");
    
    //--- Initialize logger
    g_logger.Initialize("TestInd", LOG_LEVEL_DEBUG, false);
    
    //--- Create indicators instance
    CIndicators indicators;
    indicators.SetLogger(&g_logger);
    
    //--- Initialize indicators
    Print("Initializing indicators...");
    if(!indicators.Initialize(_Symbol, PERIOD_CURRENT,
        InpADXPeriod, InpATRPeriod, InpBBPeriod, InpBBDeviation, InpRSIPeriod))
    {
        Print("ERROR: Failed to initialize indicators!");
        return;
    }
    Print("Indicators initialized successfully.");
    Print("");
    
    //--- Wait for data
    Sleep(500);
    
    //--- Check if data is ready
    if(!indicators.IsDataReady())
    {
        Print("WARNING: Indicator data may not be fully ready.");
    }
    
    //--- Refresh buffers
    if(!indicators.RefreshBuffers(InpBarsToTest + 5))
    {
        Print("ERROR: Failed to refresh indicator buffers!");
        return;
    }
    
    //--- Print indicator values for each bar
    Print("===========================================");
    Print("Indicator Values (Shift 0 = Current Bar)");
    Print("===========================================");
    
    for(int i = 0; i < InpBarsToTest; i++)
    {
        datetime barTime = iTime(_Symbol, PERIOD_CURRENT, i);
        double close = iClose(_Symbol, PERIOD_CURRENT, i);
        double high = iHigh(_Symbol, PERIOD_CURRENT, i);
        double low = iLow(_Symbol, PERIOD_CURRENT, i);
        
        double adx = indicators.GetADX(i);
        double atr = indicators.GetATR(i);
        double rsi = indicators.GetRSI(i);
        double bbUpper = indicators.GetBBUpper(i);
        double bbMiddle = indicators.GetBBMiddle(i);
        double bbLower = indicators.GetBBLower(i);
        
        Print("-------------------------------------------");
        Print(StringFormat("Bar %d: %s", i, TimeToString(barTime)));
        Print(StringFormat("  Price: H=%.5f L=%.5f C=%.5f", high, low, close));
        Print(StringFormat("  ADX: %.2f", adx));
        Print(StringFormat("  ATR: %.5f", atr));
        Print(StringFormat("  RSI: %.2f", rsi));
        Print(StringFormat("  BB Upper: %.5f", bbUpper));
        Print(StringFormat("  BB Middle: %.5f", bbMiddle));
        Print(StringFormat("  BB Lower: %.5f", bbLower));
        
        //--- Check conditions
        bool isTrending = indicators.IsTrending(25, i);
        bool isOversold = indicators.IsOversold(30, i);
        bool isOverbought = indicators.IsOverbought(70, i);
        bool belowLowerBB = indicators.IsBelowLowerBB(close, i);
        bool aboveUpperBB = indicators.IsAboveUpperBB(close, i);
        
        Print(StringFormat("  Trending (ADX>=25): %s", isTrending ? "YES" : "NO"));
        Print(StringFormat("  Oversold (RSI<30): %s", isOversold ? "YES" : "NO"));
        Print(StringFormat("  Overbought (RSI>70): %s", isOverbought ? "YES" : "NO"));
        Print(StringFormat("  Below Lower BB: %s", belowLowerBB ? "YES" : "NO"));
        Print(StringFormat("  Above Upper BB: %s", aboveUpperBB ? "YES" : "NO"));
    }
    
    Print("");
    Print("===========================================");
    Print("Signal Detection Test (Bar 1 - Last Closed)");
    Print("===========================================");
    
    //--- Test signal detection on bar 1 (last closed bar)
    double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
    double open1 = iOpen(_Symbol, PERIOD_CURRENT, 1);
    double bbUpper1 = indicators.GetBBUpper(1);
    double bbLower1 = indicators.GetBBLower(1);
    double rsi1 = indicators.GetRSI(1);
    
    bool longSignal = (close1 < bbLower1) && (rsi1 < 30) && (close1 > open1);
    bool shortSignal = (close1 > bbUpper1) && (rsi1 > 70) && (close1 < open1);
    
    Print(StringFormat("Close: %.5f, Open: %.5f", close1, open1));
    Print(StringFormat("BB Lower: %.5f, BB Upper: %.5f", bbLower1, bbUpper1));
    Print(StringFormat("RSI: %.2f", rsi1));
    Print(StringFormat("Bar Direction: %s", close1 > open1 ? "BULLISH" : "BEARISH"));
    Print("");
    Print(StringFormat("LONG Signal: %s", longSignal ? "YES - Entry conditions met!" : "NO"));
    Print(StringFormat("SHORT Signal: %s", shortSignal ? "YES - Entry conditions met!" : "NO"));
    
    //--- Cleanup
    indicators.Deinitialize();
    
    Print("");
    Print("===========================================");
    Print("Test Complete");
    Print("===========================================");
}
//+------------------------------------------------------------------+