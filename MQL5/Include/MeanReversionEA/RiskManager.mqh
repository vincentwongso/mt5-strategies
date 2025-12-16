//+------------------------------------------------------------------+
//|                                                  RiskManager.mqh |
//|                                      Mean Reversion EA           |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Mean Reversion EA"
#property link      ""
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Risk Manager class - Handles position sizing and risk calc       |
//+------------------------------------------------------------------+
class CRiskManager
{
private:
    //--- Symbol info
    string            m_symbol;
    double            m_tickSize;
    double            m_tickValue;
    double            m_pointValue;
    double            m_minLot;
    double            m_maxLot;
    double            m_lotStep;
    int               m_digits;
    
    //--- Risk parameters
    double            m_riskPercent;
    double            m_atrMultiplierTrend;
    double            m_atrMultiplierRange;
    
    //--- Initialization flag
    bool              m_isInitialized;
    
    //--- Logger reference
    CLogger*          m_logger;

public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CRiskManager()
    {
        m_symbol = "";
        m_tickSize = 0.0;
        m_tickValue = 0.0;
        m_pointValue = 0.0;
        m_minLot = 0.01;
        m_maxLot = 100.0;
        m_lotStep = 0.01;
        m_digits = 2;
        
        m_riskPercent = 1.0;
        m_atrMultiplierTrend = 2.5;
        m_atrMultiplierRange = 1.5;
        
        m_isInitialized = false;
        m_logger = NULL;
    }
    
    //+------------------------------------------------------------------+
    //| Destructor                                                       |
    //+------------------------------------------------------------------+
    ~CRiskManager()
    {
    }
    
    //+------------------------------------------------------------------+
    //| Set logger reference                                             |
    //+------------------------------------------------------------------+
    void SetLogger(CLogger* logger)
    {
        m_logger = logger;
    }
    
    //+------------------------------------------------------------------+
    //| Initialize the risk manager                                      |
    //+------------------------------------------------------------------+
    bool Initialize(string symbol, double riskPercent,
                    double atrMultiplierTrend, double atrMultiplierRange)
    {
        m_symbol = symbol;
        m_riskPercent = riskPercent;
        m_atrMultiplierTrend = atrMultiplierTrend;
        m_atrMultiplierRange = atrMultiplierRange;
        
        //--- Get symbol information
        if(!RefreshSymbolInfo())
        {
            LogError("Failed to get symbol information");
            return false;
        }
        
        m_isInitialized = true;
        LogInfo(StringFormat("Risk Manager initialized for %s", m_symbol));
        LogInfo(StringFormat("Tick Size: %.5f, Tick Value: %.2f, Min Lot: %.2f, Lot Step: %.2f",
            m_tickSize, m_tickValue, m_minLot, m_lotStep));
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Refresh symbol information                                       |
    //+------------------------------------------------------------------+
    bool RefreshSymbolInfo()
    {
        m_tickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
        m_tickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
        m_pointValue = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        m_minLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
        m_maxLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
        m_lotStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
        m_digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
        
        if(m_tickSize == 0 || m_tickValue == 0)
        {
            LogError("Invalid symbol info: tick size or tick value is zero");
            return false;
        }
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Calculate stop loss distance based on ATR and regime            |
    //+------------------------------------------------------------------+
    double CalculateStopDistance(double atr, bool isTrending)
    {
        double multiplier = isTrending ? m_atrMultiplierTrend : m_atrMultiplierRange;
        double stopDistance = atr * multiplier;
        
        LogInfo(StringFormat("Stop Distance: %.5f (ATR: %.5f x Multiplier: %.1f, Regime: %s)",
            stopDistance, atr, multiplier, isTrending ? "Trending" : "Ranging"));
        
        return stopDistance;
    }
    
    //+------------------------------------------------------------------+
    //| Calculate position size based on risk                            |
    //+------------------------------------------------------------------+
    double CalculatePositionSize(double stopDistance)
    {
        if(!m_isInitialized || stopDistance <= 0)
        {
            LogError("Cannot calculate position size: not initialized or invalid stop distance");
            return 0.0;
        }
        
        //--- Refresh symbol info to get current tick value
        RefreshSymbolInfo();
        
        //--- Get account equity
        double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
        
        //--- Calculate risk amount in account currency
        double riskAmount = accountEquity * (m_riskPercent / 100.0);
        
        //--- Calculate stop distance in ticks
        double stopTicks = stopDistance / m_tickSize;
        
        //--- Calculate position size
        // Risk Amount = Position Size * Stop Ticks * Tick Value
        // Position Size = Risk Amount / (Stop Ticks * Tick Value)
        double positionSize = riskAmount / (stopTicks * m_tickValue);
        
        LogInfo(StringFormat("Position Size Calculation: Equity=%.2f, Risk%%=%.1f, RiskAmt=%.2f, StopTicks=%.1f, TickValue=%.2f",
            accountEquity, m_riskPercent, riskAmount, stopTicks, m_tickValue));
        
        //--- Validate and normalize lot size
        if(!ValidateLotSize(positionSize))
        {
            LogWarning(StringFormat("Position size adjusted from %.4f to %.4f", positionSize, positionSize));
        }
        
        LogInfo(StringFormat("Final Position Size: %.2f lots", positionSize));
        
        return positionSize;
    }
    
    //+------------------------------------------------------------------+
    //| Validate and normalize lot size                                  |
    //+------------------------------------------------------------------+
    bool ValidateLotSize(double &lots)
    {
        bool wasAdjusted = false;
        double originalLots = lots;
        
        //--- Check minimum
        if(lots < m_minLot)
        {
            lots = m_minLot;
            wasAdjusted = true;
        }
        
        //--- Check maximum
        if(lots > m_maxLot)
        {
            lots = m_maxLot;
            wasAdjusted = true;
        }
        
        //--- Normalize to lot step
        lots = NormalizeLots(lots);
        
        if(lots != originalLots)
            wasAdjusted = true;
            
        return !wasAdjusted;
    }
    
    //+------------------------------------------------------------------+
    //| Normalize lots to broker's lot step                              |
    //+------------------------------------------------------------------+
    double NormalizeLots(double lots)
    {
        if(m_lotStep == 0)
            return lots;
            
        return MathFloor(lots / m_lotStep) * m_lotStep;
    }
    
    //+------------------------------------------------------------------+
    //| Calculate take profit price (middle BB)                          |
    //+------------------------------------------------------------------+
    double GetTakeProfit(double bbMiddle, ENUM_ORDER_TYPE orderType, double entryPrice)
    {
        //--- For mean reversion, TP is the middle Bollinger Band
        double tp = bbMiddle;
        
        //--- Validate TP is in the right direction
        if(orderType == ORDER_TYPE_BUY)
        {
            if(tp <= entryPrice)
            {
                LogWarning(StringFormat("TP (%.5f) is not above entry (%.5f) for BUY. Using entry + 10 ticks.",
                    tp, entryPrice));
                tp = entryPrice + (10 * m_tickSize);
            }
        }
        else if(orderType == ORDER_TYPE_SELL)
        {
            if(tp >= entryPrice)
            {
                LogWarning(StringFormat("TP (%.5f) is not below entry (%.5f) for SELL. Using entry - 10 ticks.",
                    tp, entryPrice));
                tp = entryPrice - (10 * m_tickSize);
            }
        }
        
        return NormalizeDouble(tp, m_digits);
    }
    
    //+------------------------------------------------------------------+
    //| Calculate stop loss price                                        |
    //+------------------------------------------------------------------+
    double GetStopLoss(double stopDistance, ENUM_ORDER_TYPE orderType, double entryPrice)
    {
        double sl;
        
        if(orderType == ORDER_TYPE_BUY)
        {
            sl = entryPrice - stopDistance;
        }
        else // SELL
        {
            sl = entryPrice + stopDistance;
        }
        
        return NormalizeDouble(sl, m_digits);
    }
    
    //+------------------------------------------------------------------+
    //| Get tick value                                                   |
    //+------------------------------------------------------------------+
    double GetTickValue()
    {
        RefreshSymbolInfo();
        return m_tickValue;
    }
    
    //+------------------------------------------------------------------+
    //| Get tick size                                                    |
    //+------------------------------------------------------------------+
    double GetTickSize()
    {
        return m_tickSize;
    }
    
    //+------------------------------------------------------------------+
    //| Get point value                                                  |
    //+------------------------------------------------------------------+
    double GetPointValue()
    {
        return m_pointValue;
    }
    
    //+------------------------------------------------------------------+
    //| Get minimum lot size                                             |
    //+------------------------------------------------------------------+
    double GetMinLot()
    {
        return m_minLot;
    }
    
    //+------------------------------------------------------------------+
    //| Get lot step                                                     |
    //+------------------------------------------------------------------+
    double GetLotStep()
    {
        return m_lotStep;
    }
    
    //+------------------------------------------------------------------+
    //| Get digits                                                       |
    //+------------------------------------------------------------------+
    int GetDigits()
    {
        return m_digits;
    }
    
    //+------------------------------------------------------------------+
    //| Check if initialized                                             |
    //+------------------------------------------------------------------+
    bool IsInitialized() { return m_isInitialized; }
    
    //+------------------------------------------------------------------+
    //| Set risk percent                                                 |
    //+------------------------------------------------------------------+
    void SetRiskPercent(double riskPercent)
    {
        m_riskPercent = riskPercent;
    }
    
    //+------------------------------------------------------------------+
    //| Set ATR multipliers                                              |
    //+------------------------------------------------------------------+
    void SetATRMultipliers(double trendMultiplier, double rangeMultiplier)
    {
        m_atrMultiplierTrend = trendMultiplier;
        m_atrMultiplierRange = rangeMultiplier;
    }

private:
    //+------------------------------------------------------------------+
    //| Log helper functions                                             |
    //+------------------------------------------------------------------+
    void LogInfo(string message)
    {
        if(m_logger != NULL)
            m_logger.Info(message);
        else
            Print("[RiskManager] INFO: ", message);
    }
    
    void LogWarning(string message)
    {
        if(m_logger != NULL)
            m_logger.Warning(message);
        else
            Print("[RiskManager] WARNING: ", message);
    }
    
    void LogError(string message)
    {
        if(m_logger != NULL)
            m_logger.Error(message);
        else
            Print("[RiskManager] ERROR: ", message);
    }
};
//+------------------------------------------------------------------+