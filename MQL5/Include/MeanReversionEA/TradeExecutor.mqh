//+------------------------------------------------------------------+
//|                                                TradeExecutor.mqh |
//|                                      Mean Reversion EA           |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Mean Reversion EA"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Trade Executor class - Handles order execution                   |
//+------------------------------------------------------------------+
class CTradeExecutor
{
private:
    //--- Trade object
    CTrade            m_trade;
    
    //--- Symbol info
    string            m_symbol;
    int               m_digits;
    double            m_tickSize;
    
    //--- Trade settings
    ulong             m_magicNumber;
    string            m_tradeComment;
    int               m_maxSlippageTicks;
    ulong             m_deviation;
    
    //--- Position tracking
    ulong             m_openTicket;
    ENUM_ORDER_TYPE   m_positionType;
    double            m_positionOpenPrice;
    double            m_positionSL;
    double            m_positionTP;
    double            m_positionLots;
    datetime          m_positionOpenTime;
    
    //--- Initialization flag
    bool              m_isInitialized;
    
    //--- Logger reference
    CLogger*          m_logger;

public:
    //+------------------------------------------------------------------+
    //| Constructor                                                      |
    //+------------------------------------------------------------------+
    CTradeExecutor()
    {
        m_symbol = "";
        m_digits = 2;
        m_tickSize = 0.01;
        m_magicNumber = 0;
        m_tradeComment = "";
        m_maxSlippageTicks = 3;
        m_deviation = 10;
        
        m_openTicket = 0;
        m_positionType = ORDER_TYPE_BUY;
        m_positionOpenPrice = 0.0;
        m_positionSL = 0.0;
        m_positionTP = 0.0;
        m_positionLots = 0.0;
        m_positionOpenTime = 0;
        
        m_isInitialized = false;
        m_logger = NULL;
    }
    
    //+------------------------------------------------------------------+
    //| Destructor                                                       |
    //+------------------------------------------------------------------+
    ~CTradeExecutor()
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
    //| Initialize the trade executor                                    |
    //+------------------------------------------------------------------+
    bool Initialize(string symbol, ulong magicNumber, string comment, int maxSlippageTicks)
    {
        m_symbol = symbol;
        m_magicNumber = magicNumber;
        m_tradeComment = comment;
        m_maxSlippageTicks = maxSlippageTicks;
        
        //--- Get symbol info
        m_digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
        m_tickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
        
        //--- Configure trade object
        m_trade.SetExpertMagicNumber(m_magicNumber);
        m_trade.SetDeviationInPoints(m_maxSlippageTicks);
        m_trade.SetTypeFilling(ORDER_FILLING_IOC);  // Immediate or Cancel
        m_trade.SetAsyncMode(false);  // Synchronous mode for reliable execution
        
        //--- Check for existing positions
        ScanForExistingPosition();
        
        m_isInitialized = true;
        LogInfo(StringFormat("Trade Executor initialized. Magic: %d, Symbol: %s", m_magicNumber, m_symbol));
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Open a buy position                                              |
    //+------------------------------------------------------------------+
    bool OpenBuy(double lots, double sl, double tp)
    {
        if(!m_isInitialized)
        {
            LogError("Trade Executor not initialized");
            return false;
        }
        
        if(HasOpenPosition())
        {
            LogWarning("Cannot open BUY: Position already exists");
            return false;
        }
        
        //--- Get current ask price
        double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
        
        //--- Normalize prices
        sl = NormalizeDouble(sl, m_digits);
        tp = NormalizeDouble(tp, m_digits);
        
        LogInfo(StringFormat("Opening BUY: Lots=%.2f, Price=%.5f, SL=%.5f, TP=%.5f", lots, ask, sl, tp));
        
        //--- Execute trade
        if(!m_trade.Buy(lots, m_symbol, ask, sl, tp, m_tradeComment))
        {
            LogError(StringFormat("Failed to open BUY. Error: %d - %s", 
                m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription()));
            return false;
        }
        
        //--- Check result
        if(m_trade.ResultRetcode() != TRADE_RETCODE_DONE)
        {
            LogError(StringFormat("BUY order failed. Retcode: %d - %s",
                m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription()));
            return false;
        }
        
        //--- Store position info
        m_openTicket = m_trade.ResultOrder();
        m_positionType = ORDER_TYPE_BUY;
        m_positionOpenPrice = m_trade.ResultPrice();
        m_positionSL = sl;
        m_positionTP = tp;
        m_positionLots = lots;
        m_positionOpenTime = TimeCurrent();
        
        //--- Check for slippage
        CheckSlippage(ask, m_positionOpenPrice);
        
        LogInfo(StringFormat("BUY opened successfully. Ticket: %d, Price: %.5f", m_openTicket, m_positionOpenPrice));
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Open a sell position                                             |
    //+------------------------------------------------------------------+
    bool OpenSell(double lots, double sl, double tp)
    {
        if(!m_isInitialized)
        {
            LogError("Trade Executor not initialized");
            return false;
        }
        
        if(HasOpenPosition())
        {
            LogWarning("Cannot open SELL: Position already exists");
            return false;
        }
        
        //--- Get current bid price
        double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        
        //--- Normalize prices
        sl = NormalizeDouble(sl, m_digits);
        tp = NormalizeDouble(tp, m_digits);
        
        LogInfo(StringFormat("Opening SELL: Lots=%.2f, Price=%.5f, SL=%.5f, TP=%.5f", lots, bid, sl, tp));
        
        //--- Execute trade
        if(!m_trade.Sell(lots, m_symbol, bid, sl, tp, m_tradeComment))
        {
            LogError(StringFormat("Failed to open SELL. Error: %d - %s",
                m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription()));
            return false;
        }
        
        //--- Check result
        if(m_trade.ResultRetcode() != TRADE_RETCODE_DONE)
        {
            LogError(StringFormat("SELL order failed. Retcode: %d - %s",
                m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription()));
            return false;
        }
        
        //--- Store position info
        m_openTicket = m_trade.ResultOrder();
        m_positionType = ORDER_TYPE_SELL;
        m_positionOpenPrice = m_trade.ResultPrice();
        m_positionSL = sl;
        m_positionTP = tp;
        m_positionLots = lots;
        m_positionOpenTime = TimeCurrent();
        
        //--- Check for slippage
        CheckSlippage(bid, m_positionOpenPrice);
        
        LogInfo(StringFormat("SELL opened successfully. Ticket: %d, Price: %.5f", m_openTicket, m_positionOpenPrice));
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Close the current position                                       |
    //+------------------------------------------------------------------+
    bool ClosePosition(string reason = "")
    {
        if(!HasOpenPosition())
        {
            LogWarning("No position to close");
            return false;
        }
        
        LogInfo(StringFormat("Closing position. Ticket: %d, Reason: %s", m_openTicket, reason));
        
        //--- Select the position
        if(!PositionSelectByTicket(m_openTicket))
        {
            LogError(StringFormat("Failed to select position. Ticket: %d", m_openTicket));
            ResetPositionInfo();
            return false;
        }
        
        //--- Close the position
        if(!m_trade.PositionClose(m_openTicket))
        {
            LogError(StringFormat("Failed to close position. Error: %d - %s",
                m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription()));
            return false;
        }
        
        //--- Check result
        if(m_trade.ResultRetcode() != TRADE_RETCODE_DONE)
        {
            LogError(StringFormat("Position close failed. Retcode: %d - %s",
                m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription()));
            return false;
        }
        
        double closePrice = m_trade.ResultPrice();
        double profit = PositionGetDouble(POSITION_PROFIT);
        
        if(m_logger != NULL)
            m_logger.LogTradeExit(reason, profit, closePrice);
        
        LogInfo(StringFormat("Position closed. Price: %.5f, Profit: %.2f", closePrice, profit));
        
        ResetPositionInfo();
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Modify stop loss of current position                             |
    //+------------------------------------------------------------------+
    bool ModifyStopLoss(double newSL)
    {
        if(!HasOpenPosition())
        {
            LogWarning("No position to modify");
            return false;
        }
        
        //--- Normalize the new SL
        newSL = NormalizeDouble(newSL, m_digits);
        
        //--- Check if SL actually changed
        if(MathAbs(newSL - m_positionSL) < m_tickSize)
        {
            return true;  // No change needed
        }
        
        //--- Select the position
        if(!PositionSelectByTicket(m_openTicket))
        {
            LogError(StringFormat("Failed to select position for SL modification. Ticket: %d", m_openTicket));
            return false;
        }
        
        //--- Get current TP
        double currentTP = PositionGetDouble(POSITION_TP);
        
        LogInfo(StringFormat("Modifying SL: Old=%.5f, New=%.5f", m_positionSL, newSL));
        
        //--- Modify the position
        if(!m_trade.PositionModify(m_openTicket, newSL, currentTP))
        {
            LogError(StringFormat("Failed to modify SL. Error: %d - %s",
                m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription()));
            return false;
        }
        
        //--- Check result
        if(m_trade.ResultRetcode() != TRADE_RETCODE_DONE)
        {
            LogError(StringFormat("SL modification failed. Retcode: %d - %s",
                m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription()));
            return false;
        }
        
        m_positionSL = newSL;
        LogInfo(StringFormat("SL modified successfully to %.5f", newSL));
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Check if there's an open position                                |
    //+------------------------------------------------------------------+
    bool HasOpenPosition()
    {
        //--- First check our tracked ticket
        if(m_openTicket > 0)
        {
            if(PositionSelectByTicket(m_openTicket))
            {
                return true;
            }
            else
            {
                //--- Position was closed externally
                LogInfo("Position was closed externally");
                ResetPositionInfo();
            }
        }
        
        //--- Scan for any position with our magic number
        return ScanForExistingPosition();
    }
    
    //+------------------------------------------------------------------+
    //| Get open ticket                                                  |
    //+------------------------------------------------------------------+
    ulong GetOpenTicket() { return m_openTicket; }
    
    //+------------------------------------------------------------------+
    //| Get position type                                                |
    //+------------------------------------------------------------------+
    ENUM_ORDER_TYPE GetPositionType() { return m_positionType; }
    
    //+------------------------------------------------------------------+
    //| Get position open price                                          |
    //+------------------------------------------------------------------+
    double GetPositionOpenPrice() { return m_positionOpenPrice; }
    
    //+------------------------------------------------------------------+
    //| Get position stop loss                                           |
    //+------------------------------------------------------------------+
    double GetPositionSL() { return m_positionSL; }
    
    //+------------------------------------------------------------------+
    //| Get position take profit                                         |
    //+------------------------------------------------------------------+
    double GetPositionTP() { return m_positionTP; }
    
    //+------------------------------------------------------------------+
    //| Get position lots                                                |
    //+------------------------------------------------------------------+
    double GetPositionLots() { return m_positionLots; }
    
    //+------------------------------------------------------------------+
    //| Get position open time                                           |
    //+------------------------------------------------------------------+
    datetime GetPositionOpenTime() { return m_positionOpenTime; }
    
    //+------------------------------------------------------------------+
    //| Get current position profit                                      |
    //+------------------------------------------------------------------+
    double GetPositionProfit()
    {
        if(!HasOpenPosition())
            return 0.0;
            
        if(PositionSelectByTicket(m_openTicket))
            return PositionGetDouble(POSITION_PROFIT);
            
        return 0.0;
    }
    
    //+------------------------------------------------------------------+
    //| Check if initialized                                             |
    //+------------------------------------------------------------------+
    bool IsInitialized() { return m_isInitialized; }

private:
    //+------------------------------------------------------------------+
    //| Scan for existing position with our magic number                 |
    //+------------------------------------------------------------------+
    bool ScanForExistingPosition()
    {
        int totalPositions = PositionsTotal();
        
        for(int i = 0; i < totalPositions; i++)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0)
                continue;
                
            //--- Check if it's our position
            if(PositionGetInteger(POSITION_MAGIC) == m_magicNumber &&
               PositionGetString(POSITION_SYMBOL) == m_symbol)
            {
                //--- Found our position
                m_openTicket = ticket;
                m_positionType = (ENUM_ORDER_TYPE)PositionGetInteger(POSITION_TYPE);
                m_positionOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                m_positionSL = PositionGetDouble(POSITION_SL);
                m_positionTP = PositionGetDouble(POSITION_TP);
                m_positionLots = PositionGetDouble(POSITION_VOLUME);
                m_positionOpenTime = (datetime)PositionGetInteger(POSITION_TIME);
                
                LogInfo(StringFormat("Found existing position. Ticket: %d, Type: %s, Lots: %.2f",
                    m_openTicket, EnumToString(m_positionType), m_positionLots));
                
                return true;
            }
        }
        
        return false;
    }
    
    //+------------------------------------------------------------------+
    //| Reset position tracking info                                     |
    //+------------------------------------------------------------------+
    void ResetPositionInfo()
    {
        m_openTicket = 0;
        m_positionOpenPrice = 0.0;
        m_positionSL = 0.0;
        m_positionTP = 0.0;
        m_positionLots = 0.0;
        m_positionOpenTime = 0;
    }
    
    //+------------------------------------------------------------------+
    //| Check and log slippage                                           |
    //+------------------------------------------------------------------+
    void CheckSlippage(double requestedPrice, double executedPrice)
    {
        double slippagePoints = MathAbs(executedPrice - requestedPrice);
        int slippageTicks = (int)(slippagePoints / m_tickSize);
        
        if(slippageTicks > m_maxSlippageTicks)
        {
            if(m_logger != NULL)
                m_logger.LogSlippage(requestedPrice, executedPrice, slippageTicks);
            else
                LogWarning(StringFormat("Slippage exceeded: %d ticks (max: %d)", slippageTicks, m_maxSlippageTicks));
        }
        else if(slippageTicks > 0)
        {
            LogInfo(StringFormat("Slippage: %d ticks", slippageTicks));
        }
    }
    
    //+------------------------------------------------------------------+
    //| Log helper functions                                             |
    //+------------------------------------------------------------------+
    void LogInfo(string message)
    {
        if(m_logger != NULL)
            m_logger.Info(message);
        else
            Print("[TradeExecutor] INFO: ", message);
    }
    
    void LogWarning(string message)
    {
        if(m_logger != NULL)
            m_logger.Warning(message);
        else
            Print("[TradeExecutor] WARNING: ", message);
    }
    
    void LogError(string message)
    {
        if(m_logger != NULL)
            m_logger.Error(message);
        else
            Print("[TradeExecutor] ERROR: ", message);
    }
};
//+------------------------------------------------------------------+