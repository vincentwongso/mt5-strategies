//+------------------------------------------------------------------+
//|                                                 TrailingStop.mqh |
//|                                      Mean Reversion EA           |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Mean Reversion EA"
#property link      ""
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Trailing Stop class - Implements Chandelier Exit                 |
//+------------------------------------------------------------------+
class CTrailingStop
{
private:
    //--- Position tracking
    ENUM_ORDER_TYPE   m_positionType;
    double            m_entryPrice;
    double            m_highestHigh;
    double            m_lowestLow;
    double            m_currentStop;
    double            m_initialStop;
    
    //--- ATR multipliers
    double            m_atrMultiplierTrend;
    double            m_atrMultiplierRange;
    
    //--- Symbol info
    int               m_digits;
    double            m_tickSize;
    
    //--- State
    bool              m_isActive;
    bool              m_stopNeedsUpdate;
    
    //--- Logger reference
    CLogger*          m_logger;

public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CTrailingStop()
    {
        m_positionType = ORDER_TYPE_BUY;
        m_entryPrice = 0.0;
        m_highestHigh = 0.0;
        m_lowestLow = DBL_MAX;
        m_currentStop = 0.0;
        m_initialStop = 0.0;
        
        m_atrMultiplierTrend = 2.5;
        m_atrMultiplierRange = 1.5;
        
        m_digits = 2;
        m_tickSize = 0.01;
        
        m_isActive = false;
        m_stopNeedsUpdate = false;
        
        m_logger = NULL;
    }
    
    //+------------------------------------------------------------------+
    //| Destructor                                                       |
    //+------------------------------------------------------------------+
    ~CTrailingStop()
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
    //| Initialize with symbol info                                      |
    //+------------------------------------------------------------------+
    void Initialize(int digits, double tickSize, 
                    double atrMultiplierTrend, double atrMultiplierRange)
    {
        m_digits = digits;
        m_tickSize = tickSize;
        m_atrMultiplierTrend = atrMultiplierTrend;
        m_atrMultiplierRange = atrMultiplierRange;
    }
    
    //+------------------------------------------------------------------+
    //| Called when a new position is opened                             |
    //+------------------------------------------------------------------+
    void OnPositionOpen(ENUM_ORDER_TYPE positionType, double entryPrice, 
                        double initialStop, double high, double low)
    {
        m_positionType = positionType;
        m_entryPrice = entryPrice;
        m_initialStop = initialStop;
        m_currentStop = initialStop;
        
        //--- Initialize high/low tracking from entry bar
        if(m_positionType == ORDER_TYPE_BUY)
        {
            m_highestHigh = high;
            m_lowestLow = DBL_MAX;  // Not used for longs
        }
        else // SELL
        {
            m_lowestLow = low;
            m_highestHigh = 0.0;  // Not used for shorts
        }
        
        m_isActive = true;
        m_stopNeedsUpdate = false;
        
        LogInfo(StringFormat("Trailing stop activated. Type: %s, Entry: %.5f, Initial SL: %.5f",
            EnumToString(m_positionType), m_entryPrice, m_initialStop));
    }
    
    //+------------------------------------------------------------------+
    //| Called on each new bar to update trailing stop                   |
    //+------------------------------------------------------------------+
    void OnNewBar(double high, double low, double atr, bool isTrending)
    {
        if(!m_isActive)
            return;
            
        m_stopNeedsUpdate = false;
        
        //--- Calculate ATR-based stop distance
        double multiplier = isTrending ? m_atrMultiplierTrend : m_atrMultiplierRange;
        double stopDistance = atr * multiplier;
        
        double newStop = 0.0;
        
        if(m_positionType == ORDER_TYPE_BUY)
        {
            //--- Update highest high
            if(high > m_highestHigh)
            {
                m_highestHigh = high;
                LogInfo(StringFormat("New highest high: %.5f", m_highestHigh));
            }
            
            //--- Calculate new stop (below highest high)
            newStop = m_highestHigh - stopDistance;
            newStop = NormalizeDouble(newStop, m_digits);
            
            //--- Stop can only move up, never down
            if(newStop > m_currentStop)
            {
                LogInfo(StringFormat("Trailing stop update (BUY): %.5f -> %.5f (HH: %.5f, ATR: %.5f, Mult: %.1f)",
                    m_currentStop, newStop, m_highestHigh, atr, multiplier));
                m_currentStop = newStop;
                m_stopNeedsUpdate = true;
            }
        }
        else // SELL
        {
            //--- Update lowest low
            if(low < m_lowestLow)
            {
                m_lowestLow = low;
                LogInfo(StringFormat("New lowest low: %.5f", m_lowestLow));
            }
            
            //--- Calculate new stop (above lowest low)
            newStop = m_lowestLow + stopDistance;
            newStop = NormalizeDouble(newStop, m_digits);
            
            //--- Stop can only move down, never up
            if(newStop < m_currentStop)
            {
                LogInfo(StringFormat("Trailing stop update (SELL): %.5f -> %.5f (LL: %.5f, ATR: %.5f, Mult: %.1f)",
                    m_currentStop, newStop, m_lowestLow, atr, multiplier));
                m_currentStop = newStop;
                m_stopNeedsUpdate = true;
            }
        }
    }
    
    //+------------------------------------------------------------------+
    //| Check if stop needs to be updated                                |
    //+------------------------------------------------------------------+
    bool ShouldUpdateStop()
    {
        return m_isActive && m_stopNeedsUpdate;
    }
    
    //+------------------------------------------------------------------+
    //| Get current stop level                                           |
    //+------------------------------------------------------------------+
    double GetCurrentStop()
    {
        return m_currentStop;
    }
    
    //+------------------------------------------------------------------+
    //| Get highest high since entry (for longs)                         |
    //+------------------------------------------------------------------+
    double GetHighestHigh()
    {
        return m_highestHigh;
    }
    
    //+------------------------------------------------------------------+
    //| Get lowest low since entry (for shorts)                          |
    //+------------------------------------------------------------------+
    double GetLowestLow()
    {
        return m_lowestLow;
    }
    
    //+------------------------------------------------------------------+
    //| Get initial stop                                                 |
    //+------------------------------------------------------------------+
    double GetInitialStop()
    {
        return m_initialStop;
    }
    
    //+------------------------------------------------------------------+
    //| Check if trailing stop is active                                 |
    //+------------------------------------------------------------------+
    bool IsActive()
    {
        return m_isActive;
    }
    
    //+------------------------------------------------------------------+
    //| Reset trailing stop (when position is closed)                    |
    //+------------------------------------------------------------------+
    void Reset()
    {
        m_positionType = ORDER_TYPE_BUY;
        m_entryPrice = 0.0;
        m_highestHigh = 0.0;
        m_lowestLow = DBL_MAX;
        m_currentStop = 0.0;
        m_initialStop = 0.0;
        m_isActive = false;
        m_stopNeedsUpdate = false;
        
        LogInfo("Trailing stop reset");
    }
    
    //+------------------------------------------------------------------+
    //| Calculate stop distance for given ATR and regime                 |
    //+------------------------------------------------------------------+
    double CalculateStopDistance(double atr, bool isTrending)
    {
        double multiplier = isTrending ? m_atrMultiplierTrend : m_atrMultiplierRange;
        return atr * multiplier;
    }
    
    //+------------------------------------------------------------------+
    //| Get stop distance from current price                             |
    //+------------------------------------------------------------------+
    double GetStopDistanceFromPrice(double currentPrice)
    {
        if(!m_isActive)
            return 0.0;
            
        if(m_positionType == ORDER_TYPE_BUY)
            return currentPrice - m_currentStop;
        else
            return m_currentStop - currentPrice;
    }
    
    //+------------------------------------------------------------------+
    //| Check if price has hit the stop                                  |
    //+------------------------------------------------------------------+
    bool IsStopHit(double currentPrice)
    {
        if(!m_isActive)
            return false;
            
        if(m_positionType == ORDER_TYPE_BUY)
            return currentPrice <= m_currentStop;
        else
            return currentPrice >= m_currentStop;
    }
    
    //+------------------------------------------------------------------+
    //| Get profit in points from entry                                  |
    //+------------------------------------------------------------------+
    double GetProfitPoints(double currentPrice)
    {
        if(!m_isActive)
            return 0.0;
            
        if(m_positionType == ORDER_TYPE_BUY)
            return currentPrice - m_entryPrice;
        else
            return m_entryPrice - currentPrice;
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
    //| Log helper function                                              |
    //+------------------------------------------------------------------+
    void LogInfo(string message)
    {
        if(m_logger != NULL)
            m_logger.Info(message);
        else
            Print("[TrailingStop] INFO: ", message);
    }
};
//+------------------------------------------------------------------+