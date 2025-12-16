//+------------------------------------------------------------------+
//|                                                       Logger.mqh |
//|                                      Mean Reversion EA           |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Mean Reversion EA"
#property link      ""
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Enum for log levels                                              |
//+------------------------------------------------------------------+
enum ENUM_LOG_LEVEL
{
    LOG_LEVEL_DEBUG = 0,    // Debug - All messages
    LOG_LEVEL_INFO = 1,     // Info - Normal operation
    LOG_LEVEL_WARNING = 2,  // Warning - Potential issues
    LOG_LEVEL_ERROR = 3,    // Error - Errors only
    LOG_LEVEL_NONE = 4      // None - No logging
};

//+------------------------------------------------------------------+
//| Logger class for consistent logging throughout the EA            |
//+------------------------------------------------------------------+
class CLogger
{
private:
    ENUM_LOG_LEVEL m_logLevel;
    string         m_prefix;
    bool           m_logToFile;
    int            m_fileHandle;
    string         m_fileName;
    
    //--- Format timestamp for log entries
    string FormatTimestamp()
    {
        return TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
    }
    
    //--- Get log level string
    string GetLevelString(ENUM_LOG_LEVEL level)
    {
        switch(level)
        {
            case LOG_LEVEL_DEBUG:   return "DEBUG";
            case LOG_LEVEL_INFO:    return "INFO";
            case LOG_LEVEL_WARNING: return "WARN";
            case LOG_LEVEL_ERROR:   return "ERROR";
            default:                return "UNKNOWN";
        }
    }
    
    //--- Write to file if enabled
    void WriteToFile(string message)
    {
        if(!m_logToFile || m_fileHandle == INVALID_HANDLE)
            return;
            
        FileWriteString(m_fileHandle, message + "\n");
        FileFlush(m_fileHandle);
    }

public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CLogger()
    {
        m_logLevel = LOG_LEVEL_INFO;
        m_prefix = "MeanRevEA";
        m_logToFile = false;
        m_fileHandle = INVALID_HANDLE;
        m_fileName = "";
    }
    
    //+------------------------------------------------------------------+
    //| Destructor                                                       |
    //+------------------------------------------------------------------+
    ~CLogger()
    {
        if(m_fileHandle != INVALID_HANDLE)
        {
            FileClose(m_fileHandle);
            m_fileHandle = INVALID_HANDLE;
        }
    }
    
    //+------------------------------------------------------------------+
    //| Initialize the logger                                            |
    //+------------------------------------------------------------------+
    bool Initialize(string prefix, ENUM_LOG_LEVEL level, bool logToFile = false)
    {
        m_prefix = prefix;
        m_logLevel = level;
        m_logToFile = logToFile;
        
        if(m_logToFile)
        {
            m_fileName = m_prefix + "_" + TimeToString(TimeCurrent(), TIME_DATE) + ".log";
            StringReplace(m_fileName, ".", "_");
            StringReplace(m_fileName, ":", "_");
            m_fileName = m_fileName + ".log";
            
            m_fileHandle = FileOpen(m_fileName, FILE_WRITE | FILE_TXT | FILE_ANSI);
            if(m_fileHandle == INVALID_HANDLE)
            {
                Print("Logger: Failed to open log file: ", m_fileName);
                m_logToFile = false;
                return false;
            }
        }
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Set log level                                                    |
    //+------------------------------------------------------------------+
    void SetLogLevel(ENUM_LOG_LEVEL level)
    {
        m_logLevel = level;
    }
    
    //+------------------------------------------------------------------+
    //| Core logging function                                            |
    //+------------------------------------------------------------------+
    void Log(ENUM_LOG_LEVEL level, string message)
    {
        if(level < m_logLevel)
            return;
            
        string formattedMessage = StringFormat("[%s] [%s] [%s] %s",
            FormatTimestamp(),
            m_prefix,
            GetLevelString(level),
            message);
            
        Print(formattedMessage);
        WriteToFile(formattedMessage);
    }
    
    //+------------------------------------------------------------------+
    //| Debug level logging                                              |
    //+------------------------------------------------------------------+
    void Debug(string message)
    {
        Log(LOG_LEVEL_DEBUG, message);
    }
    
    //+------------------------------------------------------------------+
    //| Info level logging                                               |
    //+------------------------------------------------------------------+
    void Info(string message)
    {
        Log(LOG_LEVEL_INFO, message);
    }
    
    //+------------------------------------------------------------------+
    //| Warning level logging                                            |
    //+------------------------------------------------------------------+
    void Warning(string message)
    {
        Log(LOG_LEVEL_WARNING, message);
    }
    
    //+------------------------------------------------------------------+
    //| Error level logging                                              |
    //+------------------------------------------------------------------+
    void Error(string message)
    {
        Log(LOG_LEVEL_ERROR, message);
    }
    
    //+------------------------------------------------------------------+
    //| Log trade entry                                                  |
    //+------------------------------------------------------------------+
    void LogTradeEntry(string direction, double lots, double price, double sl, double tp)
    {
        string message = StringFormat("TRADE ENTRY: %s | Lots: %.2f | Price: %.5f | SL: %.5f | TP: %.5f",
            direction, lots, price, sl, tp);
        Info(message);
    }
    
    //+------------------------------------------------------------------+
    //| Log trade exit                                                   |
    //+------------------------------------------------------------------+
    void LogTradeExit(string reason, double profit, double closePrice)
    {
        string message = StringFormat("TRADE EXIT: %s | Profit: %.2f | Close Price: %.5f",
            reason, profit, closePrice);
        Info(message);
    }
    
    //+------------------------------------------------------------------+
    //| Log filter rejection                                             |
    //+------------------------------------------------------------------+
    void LogFilterRejection(string filterName, string details = "")
    {
        string message = StringFormat("FILTER REJECTED: %s", filterName);
        if(details != "")
            message += " | " + details;
        Debug(message);
    }
    
    //+------------------------------------------------------------------+
    //| Log indicator values                                             |
    //+------------------------------------------------------------------+
    void LogIndicators(double adx, double atr, double rsi, double bbUpper, double bbMiddle, double bbLower)
    {
        string message = StringFormat("INDICATORS: ADX=%.2f | ATR=%.5f | RSI=%.2f | BB[U=%.5f M=%.5f L=%.5f]",
            adx, atr, rsi, bbUpper, bbMiddle, bbLower);
        Debug(message);
    }
    
    //+------------------------------------------------------------------+
    //| Log slippage event                                               |
    //+------------------------------------------------------------------+
    void LogSlippage(double requested, double executed, int slippageTicks)
    {
        string message = StringFormat("SLIPPAGE: Requested=%.5f | Executed=%.5f | Slippage=%d ticks",
            requested, executed, slippageTicks);
        Warning(message);
    }
    
    //+------------------------------------------------------------------+
    //| Log daily loss limit reached                                     |
    //+------------------------------------------------------------------+
    void LogDailyLossLimit(double currentLoss, double limit)
    {
        string message = StringFormat("DAILY LOSS LIMIT REACHED: Current Loss=%.2f%% | Limit=%.2f%%",
            currentLoss, limit);
        Warning(message);
    }
};

//+------------------------------------------------------------------+
//| Global logger instance                                           |
//+------------------------------------------------------------------+
CLogger g_logger;
//+------------------------------------------------------------------+