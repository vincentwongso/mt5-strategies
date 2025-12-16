//+------------------------------------------------------------------+
//|                                                 TradeFilters.mqh |
//|                                      Mean Reversion EA           |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Mean Reversion EA"
#property link      ""
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Trade Filters class - Manages all trade filtering logic          |
//+------------------------------------------------------------------+
class CTradeFilters
{
private:
    //--- Symbol info
    string            m_symbol;
    
    //--- Filter parameters
    int               m_tradingStartHour;
    int               m_tradingStartMinute;
    int               m_tradingEndHour;
    int               m_tradingEndMinute;
    int               m_brokerGMTOffset;
    
    double            m_spreadMultiplier;
    double            m_minATR;
    int               m_cooldownBars;
    int               m_newsBufferMinutes;
    double            m_dailyLossLimitPercent;
    
    //--- State tracking
    double            m_averageSpread;
    int               m_spreadSampleCount;
    double            m_spreadSamples[];
    int               m_maxSpreadSamples;
    
    double            m_dailyStartEquity;
    double            m_dailyPnL;
    datetime          m_lastDayReset;
    
    int               m_barsSinceLastLoss;
    ENUM_ORDER_TYPE   m_lastLossDirection;
    bool              m_cooldownActive;
    
    //--- News times (manual input for now)
    datetime          m_newsTimes[];
    int               m_newsCount;
    
    //--- Initialization flag
    bool              m_isInitialized;
    
    //--- Logger reference
    CLogger*          m_logger;

public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CTradeFilters()
    {
        m_symbol = "";
        m_tradingStartHour = 9;
        m_tradingStartMinute = 30;
        m_tradingEndHour = 16;
        m_tradingEndMinute = 0;
        m_brokerGMTOffset = -5;
        
        m_spreadMultiplier = 2.0;
        m_minATR = 5.0;
        m_cooldownBars = 3;
        m_newsBufferMinutes = 5;
        m_dailyLossLimitPercent = 3.0;
        
        m_averageSpread = 0.0;
        m_spreadSampleCount = 0;
        m_maxSpreadSamples = 100;
        ArrayResize(m_spreadSamples, m_maxSpreadSamples);
        ArrayInitialize(m_spreadSamples, 0.0);
        
        m_dailyStartEquity = 0.0;
        m_dailyPnL = 0.0;
        m_lastDayReset = 0;
        
        m_barsSinceLastLoss = 999;  // Start with no cooldown
        m_lastLossDirection = ORDER_TYPE_BUY;
        m_cooldownActive = false;
        
        m_newsCount = 0;
        
        m_isInitialized = false;
        m_logger = NULL;
    }
    
    //+------------------------------------------------------------------+
    //| Destructor                                                       |
    //+------------------------------------------------------------------+
    ~CTradeFilters()
    {
        ArrayFree(m_spreadSamples);
        ArrayFree(m_newsTimes);
    }
    
    //+------------------------------------------------------------------+
    //| Set logger reference                                             |
    //+------------------------------------------------------------------+
    void SetLogger(CLogger* logger)
    {
        m_logger = logger;
    }
    
    //+------------------------------------------------------------------+
    //| Initialize the trade filters                                     |
    //+------------------------------------------------------------------+
    bool Initialize(string symbol,
                    int startHour, int startMinute,
                    int endHour, int endMinute,
                    int brokerGMTOffset,
                    double spreadMultiplier,
                    double minATR,
                    int cooldownBars,
                    int newsBufferMinutes,
                    double dailyLossLimitPercent)
    {
        m_symbol = symbol;
        m_tradingStartHour = startHour;
        m_tradingStartMinute = startMinute;
        m_tradingEndHour = endHour;
        m_tradingEndMinute = endMinute;
        m_brokerGMTOffset = brokerGMTOffset;
        
        m_spreadMultiplier = spreadMultiplier;
        m_minATR = minATR;
        m_cooldownBars = cooldownBars;
        m_newsBufferMinutes = newsBufferMinutes;
        m_dailyLossLimitPercent = dailyLossLimitPercent;
        
        //--- Initialize daily tracking
        m_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
        m_lastDayReset = GetTodayStart();
        m_dailyPnL = 0.0;
        
        m_isInitialized = true;
        LogInfo("Trade filters initialized");
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Called on each new bar                                           |
    //+------------------------------------------------------------------+
    void OnNewBar()
    {
        //--- Increment cooldown counter
        if(m_cooldownActive)
        {
            m_barsSinceLastLoss++;
            if(m_barsSinceLastLoss >= m_cooldownBars)
            {
                m_cooldownActive = false;
                LogInfo("Cooldown period ended");
            }
        }
        
        //--- Check for new day reset
        datetime todayStart = GetTodayStart();
        if(todayStart > m_lastDayReset)
        {
            ResetDailyStats();
        }
        
        //--- Update spread sample
        UpdateSpreadSample();
    }
    
    //+------------------------------------------------------------------+
    //| Called when a trade closes                                       |
    //+------------------------------------------------------------------+
    void OnTradeClose(double profit, ENUM_ORDER_TYPE direction)
    {
        //--- Update daily P&L
        m_dailyPnL += profit;
        
        //--- Check if it was a loss
        if(profit < 0)
        {
            m_barsSinceLastLoss = 0;
            m_lastLossDirection = direction;
            m_cooldownActive = true;
            LogInfo(StringFormat("Loss recorded. Cooldown activated for %d bars in %s direction",
                m_cooldownBars, EnumToString(direction)));
        }
    }
    
    //+------------------------------------------------------------------+
    //| Master filter check - returns true if trading is allowed         |
    //+------------------------------------------------------------------+
    bool CanTrade(ENUM_ORDER_TYPE direction)
    {
        if(!m_isInitialized)
            return false;
            
        //--- Check all filters
        if(!IsWithinTradingHours())
        {
            LogFilterRejection("Trading Hours");
            return false;
        }
        
        if(!IsDailyLossLimitOK())
        {
            LogFilterRejection("Daily Loss Limit");
            return false;
        }
        
        if(!IsSpreadAcceptable())
        {
            LogFilterRejection("Spread", StringFormat("Current spread too high"));
            return false;
        }
        
        if(!IsCooldownComplete(direction))
        {
            LogFilterRejection("Cooldown", StringFormat("Bars remaining: %d", m_cooldownBars - m_barsSinceLastLoss));
            return false;
        }
        
        if(!IsNewsWindowClear())
        {
            LogFilterRejection("News Window");
            return false;
        }
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Check if within trading hours (Eastern Time)                     |
    //+------------------------------------------------------------------+
    bool IsWithinTradingHours()
    {
        datetime currentTime = TimeCurrent();
        MqlDateTime dt;
        TimeToStruct(currentTime, dt);
        
        //--- Convert broker time to Eastern Time
        int etHour = dt.hour + (m_brokerGMTOffset - (-5));  // -5 is ET offset
        if(etHour < 0) etHour += 24;
        if(etHour >= 24) etHour -= 24;
        
        //--- Calculate minutes since midnight in ET
        int currentMinutes = etHour * 60 + dt.min;
        int startMinutes = m_tradingStartHour * 60 + m_tradingStartMinute;
        int endMinutes = m_tradingEndHour * 60 + m_tradingEndMinute;
        
        //--- Check if within trading window
        bool isWithin = (currentMinutes >= startMinutes && currentMinutes < endMinutes);
        
        //--- Also check if it's a weekday (Monday=1 to Friday=5)
        bool isWeekday = (dt.day_of_week >= 1 && dt.day_of_week <= 5);
        
        return isWithin && isWeekday;
    }
    
    //+------------------------------------------------------------------+
    //| Check if spread is acceptable                                    |
    //+------------------------------------------------------------------+
    bool IsSpreadAcceptable()
    {
        double currentSpread = GetCurrentSpread();
        
        //--- If we don't have enough samples yet, allow trading
        if(m_spreadSampleCount < 10)
            return true;
            
        //--- Check against average
        double maxAllowedSpread = m_averageSpread * m_spreadMultiplier;
        
        return (currentSpread <= maxAllowedSpread);
    }
    
    //+------------------------------------------------------------------+
    //| Check if volatility (ATR) is acceptable                          |
    //+------------------------------------------------------------------+
    bool IsVolatilityAcceptable(double currentATR)
    {
        return (currentATR >= m_minATR);
    }
    
    //+------------------------------------------------------------------+
    //| Check if daily loss limit is OK                                  |
    //+------------------------------------------------------------------+
    bool IsDailyLossLimitOK()
    {
        if(m_dailyStartEquity <= 0)
            return true;
            
        double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
        double dailyLossPercent = ((m_dailyStartEquity - currentEquity) / m_dailyStartEquity) * 100.0;
        
        if(dailyLossPercent >= m_dailyLossLimitPercent)
        {
            if(m_logger != NULL)
                m_logger.LogDailyLossLimit(dailyLossPercent, m_dailyLossLimitPercent);
            return false;
        }
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Check if cooldown period is complete                             |
    //+------------------------------------------------------------------+
    bool IsCooldownComplete(ENUM_ORDER_TYPE direction)
    {
        //--- If no cooldown active, allow trading
        if(!m_cooldownActive)
            return true;
            
        //--- Cooldown only applies to the same direction as the loss
        if(direction != m_lastLossDirection)
            return true;
            
        //--- Check if enough bars have passed
        return (m_barsSinceLastLoss >= m_cooldownBars);
    }
    
    //+------------------------------------------------------------------+
    //| Check if we're outside news window                               |
    //+------------------------------------------------------------------+
    bool IsNewsWindowClear()
    {
        if(m_newsCount == 0)
            return true;  // No news times configured
            
        datetime currentTime = TimeCurrent();
        int bufferSeconds = m_newsBufferMinutes * 60;
        
        for(int i = 0; i < m_newsCount; i++)
        {
            datetime newsTime = m_newsTimes[i];
            
            //--- Check if within buffer window
            if(currentTime >= (newsTime - bufferSeconds) && 
               currentTime <= (newsTime + bufferSeconds))
            {
                return false;
            }
        }
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Add a news time to avoid                                         |
    //+------------------------------------------------------------------+
    void AddNewsTime(datetime newsTime)
    {
        m_newsCount++;
        ArrayResize(m_newsTimes, m_newsCount);
        m_newsTimes[m_newsCount - 1] = newsTime;
    }
    
    //+------------------------------------------------------------------+
    //| Clear all news times                                             |
    //+------------------------------------------------------------------+
    void ClearNewsTimes()
    {
        m_newsCount = 0;
        ArrayResize(m_newsTimes, 0);
    }
    
    //+------------------------------------------------------------------+
    //| Reset daily statistics                                           |
    //+------------------------------------------------------------------+
    void ResetDailyStats()
    {
        m_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
        m_dailyPnL = 0.0;
        m_lastDayReset = GetTodayStart();
        LogInfo(StringFormat("Daily stats reset. Starting equity: %.2f", m_dailyStartEquity));
    }
    
    //+------------------------------------------------------------------+
    //| Get current spread in points                                     |
    //+------------------------------------------------------------------+
    double GetCurrentSpread()
    {
        double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
        double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        
        if(point == 0)
            return 0;
            
        return (ask - bid) / point;
    }
    
    //+------------------------------------------------------------------+
    //| Get average spread                                               |
    //+------------------------------------------------------------------+
    double GetAverageSpread()
    {
        return m_averageSpread;
    }
    
    //+------------------------------------------------------------------+
    //| Get daily P&L                                                    |
    //+------------------------------------------------------------------+
    double GetDailyPnL()
    {
        return m_dailyPnL;
    }
    
    //+------------------------------------------------------------------+
    //| Get daily P&L percentage                                         |
    //+------------------------------------------------------------------+
    double GetDailyPnLPercent()
    {
        if(m_dailyStartEquity <= 0)
            return 0.0;
            
        double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
        return ((currentEquity - m_dailyStartEquity) / m_dailyStartEquity) * 100.0;
    }
    
    //+------------------------------------------------------------------+
    //| Check if initialized                                             |
    //+------------------------------------------------------------------+
    bool IsInitialized() { return m_isInitialized; }
    
    //+------------------------------------------------------------------+
    //| Set minimum ATR (for different symbols)                          |
    //+------------------------------------------------------------------+
    void SetMinATR(double minATR)
    {
        m_minATR = minATR;
    }

private:
    //+------------------------------------------------------------------+
    //| Update spread sample for rolling average                         |
    //+------------------------------------------------------------------+
    void UpdateSpreadSample()
    {
        double currentSpread = GetCurrentSpread();
        
        //--- Add to circular buffer
        int index = m_spreadSampleCount % m_maxSpreadSamples;
        m_spreadSamples[index] = currentSpread;
        m_spreadSampleCount++;
        
        //--- Calculate average
        int samplesToUse = MathMin(m_spreadSampleCount, m_maxSpreadSamples);
        double sum = 0.0;
        for(int i = 0; i < samplesToUse; i++)
        {
            sum += m_spreadSamples[i];
        }
        m_averageSpread = sum / samplesToUse;
    }
    
    //+------------------------------------------------------------------+
    //| Get start of today (midnight)                                    |
    //+------------------------------------------------------------------+
    datetime GetTodayStart()
    {
        datetime currentTime = TimeCurrent();
        MqlDateTime dt;
        TimeToStruct(currentTime, dt);
        dt.hour = 0;
        dt.min = 0;
        dt.sec = 0;
        return StructToTime(dt);
    }
    
    //+------------------------------------------------------------------+
    //| Log helper functions                                             |
    //+------------------------------------------------------------------+
    void LogInfo(string message)
    {
        if(m_logger != NULL)
            m_logger.Info(message);
        else
            Print("[TradeFilters] INFO: ", message);
    }
    
    void LogFilterRejection(string filterName, string details = "")
    {
        if(m_logger != NULL)
            m_logger.LogFilterRejection(filterName, details);
        else
            Print("[TradeFilters] FILTER REJECTED: ", filterName, " ", details);
    }
};
//+------------------------------------------------------------------+