//+------------------------------------------------------------------+
//|                                                   Indicators.mqh |
//|                                      Mean Reversion EA           |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Mean Reversion EA"
#property link      ""
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Indicators class - Manages all technical indicators              |
//+------------------------------------------------------------------+
class CIndicators
{
private:
    //--- Symbol and timeframe
    string            m_symbol;
    ENUM_TIMEFRAMES   m_timeframe;
    
    //--- Indicator handles
    int               m_handleADX;
    int               m_handleATR;
    int               m_handleBB;
    int               m_handleRSI;
    
    //--- Indicator parameters
    int               m_adxPeriod;
    int               m_atrPeriod;
    int               m_bbPeriod;
    double            m_bbDeviation;
    int               m_rsiPeriod;
    
    //--- Indicator buffers
    double            m_adxBuffer[];
    double            m_adxPlusDI[];
    double            m_adxMinusDI[];
    double            m_atrBuffer[];
    double            m_bbUpperBuffer[];
    double            m_bbMiddleBuffer[];
    double            m_bbLowerBuffer[];
    double            m_rsiBuffer[];
    
    //--- Initialization flag
    bool              m_isInitialized;
    
    //--- Logger reference
    CLogger*          m_logger;

public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CIndicators()
    {
        m_symbol = "";
        m_timeframe = PERIOD_CURRENT;
        m_handleADX = INVALID_HANDLE;
        m_handleATR = INVALID_HANDLE;
        m_handleBB = INVALID_HANDLE;
        m_handleRSI = INVALID_HANDLE;
        m_isInitialized = false;
        m_logger = NULL;
        
        //--- Set default parameters
        m_adxPeriod = 14;
        m_atrPeriod = 14;
        m_bbPeriod = 20;
        m_bbDeviation = 2.0;
        m_rsiPeriod = 14;
        
        //--- Set arrays as series (most recent at index 0)
        ArraySetAsSeries(m_adxBuffer, true);
        ArraySetAsSeries(m_adxPlusDI, true);
        ArraySetAsSeries(m_adxMinusDI, true);
        ArraySetAsSeries(m_atrBuffer, true);
        ArraySetAsSeries(m_bbUpperBuffer, true);
        ArraySetAsSeries(m_bbMiddleBuffer, true);
        ArraySetAsSeries(m_bbLowerBuffer, true);
        ArraySetAsSeries(m_rsiBuffer, true);
    }
    
    //+------------------------------------------------------------------+
    //| Destructor                                                       |
    //+------------------------------------------------------------------+
    ~CIndicators()
    {
        Deinitialize();
    }
    
    //+------------------------------------------------------------------+
    //| Set logger reference                                             |
    //+------------------------------------------------------------------+
    void SetLogger(CLogger* logger)
    {
        m_logger = logger;
    }
    
    //+------------------------------------------------------------------+
    //| Initialize all indicators                                        |
    //+------------------------------------------------------------------+
    bool Initialize(string symbol, ENUM_TIMEFRAMES timeframe,
                    int adxPeriod = 14, int atrPeriod = 14,
                    int bbPeriod = 20, double bbDeviation = 2.0,
                    int rsiPeriod = 14)
    {
        m_symbol = symbol;
        m_timeframe = timeframe;
        m_adxPeriod = adxPeriod;
        m_atrPeriod = atrPeriod;
        m_bbPeriod = bbPeriod;
        m_bbDeviation = bbDeviation;
        m_rsiPeriod = rsiPeriod;
        
        //--- Create ADX indicator handle
        m_handleADX = iADX(m_symbol, m_timeframe, m_adxPeriod);
        if(m_handleADX == INVALID_HANDLE)
        {
            LogError("Failed to create ADX indicator handle");
            return false;
        }
        
        //--- Create ATR indicator handle
        m_handleATR = iATR(m_symbol, m_timeframe, m_atrPeriod);
        if(m_handleATR == INVALID_HANDLE)
        {
            LogError("Failed to create ATR indicator handle");
            return false;
        }
        
        //--- Create Bollinger Bands indicator handle
        m_handleBB = iBands(m_symbol, m_timeframe, m_bbPeriod, 0, m_bbDeviation, PRICE_CLOSE);
        if(m_handleBB == INVALID_HANDLE)
        {
            LogError("Failed to create Bollinger Bands indicator handle");
            return false;
        }
        
        //--- Create RSI indicator handle
        m_handleRSI = iRSI(m_symbol, m_timeframe, m_rsiPeriod, PRICE_CLOSE);
        if(m_handleRSI == INVALID_HANDLE)
        {
            LogError("Failed to create RSI indicator handle");
            return false;
        }
        
        m_isInitialized = true;
        LogInfo("Indicators initialized successfully");
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Deinitialize - Release indicator handles                         |
    //+------------------------------------------------------------------+
    void Deinitialize()
    {
        if(m_handleADX != INVALID_HANDLE)
        {
            IndicatorRelease(m_handleADX);
            m_handleADX = INVALID_HANDLE;
        }
        
        if(m_handleATR != INVALID_HANDLE)
        {
            IndicatorRelease(m_handleATR);
            m_handleATR = INVALID_HANDLE;
        }
        
        if(m_handleBB != INVALID_HANDLE)
        {
            IndicatorRelease(m_handleBB);
            m_handleBB = INVALID_HANDLE;
        }
        
        if(m_handleRSI != INVALID_HANDLE)
        {
            IndicatorRelease(m_handleRSI);
            m_handleRSI = INVALID_HANDLE;
        }
        
        m_isInitialized = false;
        LogInfo("Indicators deinitialized");
    }
    
    //+------------------------------------------------------------------+
    //| Check if indicators are ready (have enough data)                 |
    //+------------------------------------------------------------------+
    bool IsDataReady()
    {
        if(!m_isInitialized)
            return false;
            
        //--- Check if we have enough bars
        int barsAvailable = Bars(m_symbol, m_timeframe);
        int minBarsRequired = MathMax(m_adxPeriod, MathMax(m_atrPeriod, MathMax(m_bbPeriod, m_rsiPeriod))) + 10;
        
        if(barsAvailable < minBarsRequired)
        {
            LogWarning(StringFormat("Not enough bars. Available: %d, Required: %d", barsAvailable, minBarsRequired));
            return false;
        }
        
        //--- Try to copy data to verify indicators are calculated
        if(CopyBuffer(m_handleADX, 0, 0, 3, m_adxBuffer) < 3)
            return false;
        if(CopyBuffer(m_handleATR, 0, 0, 3, m_atrBuffer) < 3)
            return false;
        if(CopyBuffer(m_handleBB, 0, 0, 3, m_bbMiddleBuffer) < 3)
            return false;
        if(CopyBuffer(m_handleRSI, 0, 0, 3, m_rsiBuffer) < 3)
            return false;
            
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Refresh all indicator buffers                                    |
    //+------------------------------------------------------------------+
    bool RefreshBuffers(int count = 10)
    {
        if(!m_isInitialized)
            return false;
            
        //--- Copy ADX buffers (main line, +DI, -DI)
        if(CopyBuffer(m_handleADX, 0, 0, count, m_adxBuffer) < count)
        {
            LogError("Failed to copy ADX buffer");
            return false;
        }
        if(CopyBuffer(m_handleADX, 1, 0, count, m_adxPlusDI) < count)
        {
            LogError("Failed to copy ADX +DI buffer");
            return false;
        }
        if(CopyBuffer(m_handleADX, 2, 0, count, m_adxMinusDI) < count)
        {
            LogError("Failed to copy ADX -DI buffer");
            return false;
        }
        
        //--- Copy ATR buffer
        if(CopyBuffer(m_handleATR, 0, 0, count, m_atrBuffer) < count)
        {
            LogError("Failed to copy ATR buffer");
            return false;
        }
        
        //--- Copy Bollinger Bands buffers (middle, upper, lower)
        if(CopyBuffer(m_handleBB, 0, 0, count, m_bbMiddleBuffer) < count)
        {
            LogError("Failed to copy BB Middle buffer");
            return false;
        }
        if(CopyBuffer(m_handleBB, 1, 0, count, m_bbUpperBuffer) < count)
        {
            LogError("Failed to copy BB Upper buffer");
            return false;
        }
        if(CopyBuffer(m_handleBB, 2, 0, count, m_bbLowerBuffer) < count)
        {
            LogError("Failed to copy BB Lower buffer");
            return false;
        }
        
        //--- Copy RSI buffer
        if(CopyBuffer(m_handleRSI, 0, 0, count, m_rsiBuffer) < count)
        {
            LogError("Failed to copy RSI buffer");
            return false;
        }
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Get ADX value                                                    |
    //+------------------------------------------------------------------+
    double GetADX(int shift = 0)
    {
        if(!m_isInitialized || shift < 0)
            return 0.0;
            
        if(ArraySize(m_adxBuffer) <= shift)
        {
            if(!RefreshBuffers(shift + 5))
                return 0.0;
        }
        
        if(ArraySize(m_adxBuffer) <= shift)
            return 0.0;
            
        return m_adxBuffer[shift];
    }
    
    //+------------------------------------------------------------------+
    //| Get ADX +DI value                                                |
    //+------------------------------------------------------------------+
    double GetADXPlusDI(int shift = 0)
    {
        if(!m_isInitialized || shift < 0)
            return 0.0;
            
        if(ArraySize(m_adxPlusDI) <= shift)
        {
            if(!RefreshBuffers(shift + 5))
                return 0.0;
        }
        
        if(ArraySize(m_adxPlusDI) <= shift)
            return 0.0;
            
        return m_adxPlusDI[shift];
    }
    
    //+------------------------------------------------------------------+
    //| Get ADX -DI value                                                |
    //+------------------------------------------------------------------+
    double GetADXMinusDI(int shift = 0)
    {
        if(!m_isInitialized || shift < 0)
            return 0.0;
            
        if(ArraySize(m_adxMinusDI) <= shift)
        {
            if(!RefreshBuffers(shift + 5))
                return 0.0;
        }
        
        if(ArraySize(m_adxMinusDI) <= shift)
            return 0.0;
            
        return m_adxMinusDI[shift];
    }
    
    //+------------------------------------------------------------------+
    //| Get ATR value                                                    |
    //+------------------------------------------------------------------+
    double GetATR(int shift = 0)
    {
        if(!m_isInitialized || shift < 0)
            return 0.0;
            
        if(ArraySize(m_atrBuffer) <= shift)
        {
            if(!RefreshBuffers(shift + 5))
                return 0.0;
        }
        
        if(ArraySize(m_atrBuffer) <= shift)
            return 0.0;
            
        return m_atrBuffer[shift];
    }
    
    //+------------------------------------------------------------------+
    //| Get Bollinger Bands Upper value                                  |
    //+------------------------------------------------------------------+
    double GetBBUpper(int shift = 0)
    {
        if(!m_isInitialized || shift < 0)
            return 0.0;
            
        if(ArraySize(m_bbUpperBuffer) <= shift)
        {
            if(!RefreshBuffers(shift + 5))
                return 0.0;
        }
        
        if(ArraySize(m_bbUpperBuffer) <= shift)
            return 0.0;
            
        return m_bbUpperBuffer[shift];
    }
    
    //+------------------------------------------------------------------+
    //| Get Bollinger Bands Middle value                                 |
    //+------------------------------------------------------------------+
    double GetBBMiddle(int shift = 0)
    {
        if(!m_isInitialized || shift < 0)
            return 0.0;
            
        if(ArraySize(m_bbMiddleBuffer) <= shift)
        {
            if(!RefreshBuffers(shift + 5))
                return 0.0;
        }
        
        if(ArraySize(m_bbMiddleBuffer) <= shift)
            return 0.0;
            
        return m_bbMiddleBuffer[shift];
    }
    
    //+------------------------------------------------------------------+
    //| Get Bollinger Bands Lower value                                  |
    //+------------------------------------------------------------------+
    double GetBBLower(int shift = 0)
    {
        if(!m_isInitialized || shift < 0)
            return 0.0;
            
        if(ArraySize(m_bbLowerBuffer) <= shift)
        {
            if(!RefreshBuffers(shift + 5))
                return 0.0;
        }
        
        if(ArraySize(m_bbLowerBuffer) <= shift)
            return 0.0;
            
        return m_bbLowerBuffer[shift];
    }
    
    //+------------------------------------------------------------------+
    //| Get RSI value                                                    |
    //+------------------------------------------------------------------+
    double GetRSI(int shift = 0)
    {
        if(!m_isInitialized || shift < 0)
            return 50.0;  // Return neutral value if not initialized
            
        if(ArraySize(m_rsiBuffer) <= shift)
        {
            if(!RefreshBuffers(shift + 5))
                return 50.0;
        }
        
        if(ArraySize(m_rsiBuffer) <= shift)
            return 50.0;
            
        return m_rsiBuffer[shift];
    }
    
    //+------------------------------------------------------------------+
    //| Check if market is trending (ADX >= threshold)                   |
    //+------------------------------------------------------------------+
    bool IsTrending(int adxThreshold, int shift = 0)
    {
        double adx = GetADX(shift);
        return (adx >= adxThreshold);
    }
    
    //+------------------------------------------------------------------+
    //| Check if RSI is oversold                                         |
    //+------------------------------------------------------------------+
    bool IsOversold(int oversoldLevel, int shift = 0)
    {
        double rsi = GetRSI(shift);
        return (rsi < oversoldLevel);
    }
    
    //+------------------------------------------------------------------+
    //| Check if RSI is overbought                                       |
    //+------------------------------------------------------------------+
    bool IsOverbought(int overboughtLevel, int shift = 0)
    {
        double rsi = GetRSI(shift);
        return (rsi > overboughtLevel);
    }
    
    //+------------------------------------------------------------------+
    //| Check if price is below lower Bollinger Band                     |
    //+------------------------------------------------------------------+
    bool IsBelowLowerBB(double price, int shift = 0)
    {
        double bbLower = GetBBLower(shift);
        return (price < bbLower);
    }
    
    //+------------------------------------------------------------------+
    //| Check if price is above upper Bollinger Band                     |
    //+------------------------------------------------------------------+
    bool IsAboveUpperBB(double price, int shift = 0)
    {
        double bbUpper = GetBBUpper(shift);
        return (price > bbUpper);
    }
    
    //+------------------------------------------------------------------+
    //| Get all indicator values at once (for logging)                   |
    //+------------------------------------------------------------------+
    void GetAllValues(int shift, double &adx, double &atr, double &rsi,
                      double &bbUpper, double &bbMiddle, double &bbLower)
    {
        adx = GetADX(shift);
        atr = GetATR(shift);
        rsi = GetRSI(shift);
        bbUpper = GetBBUpper(shift);
        bbMiddle = GetBBMiddle(shift);
        bbLower = GetBBLower(shift);
    }
    
    //+------------------------------------------------------------------+
    //| Get symbol                                                       |
    //+------------------------------------------------------------------+
    string GetSymbol() { return m_symbol; }
    
    //+------------------------------------------------------------------+
    //| Get timeframe                                                    |
    //+------------------------------------------------------------------+
    ENUM_TIMEFRAMES GetTimeframe() { return m_timeframe; }
    
    //+------------------------------------------------------------------+
    //| Check if initialized                                             |
    //+------------------------------------------------------------------+
    bool IsInitialized() { return m_isInitialized; }

private:
    //+------------------------------------------------------------------+
    //| Log helper functions                                             |
    //+------------------------------------------------------------------+
    void LogInfo(string message)
    {
        if(m_logger != NULL)
            m_logger.Info(message);
        else
            Print("[Indicators] INFO: ", message);
    }
    
    void LogWarning(string message)
    {
        if(m_logger != NULL)
            m_logger.Warning(message);
        else
            Print("[Indicators] WARNING: ", message);
    }
    
    void LogError(string message)
    {
        if(m_logger != NULL)
            m_logger.Error(message);
        else
            Print("[Indicators] ERROR: ", message);
    }
};
//+------------------------------------------------------------------+