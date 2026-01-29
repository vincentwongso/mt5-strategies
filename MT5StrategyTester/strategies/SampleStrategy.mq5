//+------------------------------------------------------------------+
//|                                            SampleStrategy.mq5    |
//|                        Sample Strategy for Testing Pipeline      |
//+------------------------------------------------------------------+
#property copyright "Strategy Tester Pipeline"
#property link      ""
#property version   "1.00"
#property strict

//--- Input parameters
input double RiskPercent = 1.0;           // Risk per trade (%)
input int    FastMA_Period = 10;          // Fast MA Period
input int    SlowMA_Period = 20;          // Slow MA Period
input int    RSI_Period = 14;             // RSI Period
input double RSI_Overbought = 70;         // RSI Overbought Level
input double RSI_Oversold = 30;           // RSI Oversold Level
input int    StopLoss_Points = 500;       // Stop Loss (points)
input int    TakeProfit_Points = 1000;    // Take Profit (points)
input int    MaxDailyTrades = 3;          // Max trades per day
input int    MagicNumber = 12345;         // Magic Number

//--- Global variables
int fastMA_handle;
int slowMA_handle;
int rsi_handle;
int dailyTrades = 0;
datetime lastTradeDay;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize indicators
    fastMA_handle = iMA(_Symbol, PERIOD_CURRENT, FastMA_Period, 0, MODE_EMA, PRICE_CLOSE);
    slowMA_handle = iMA(_Symbol, PERIOD_CURRENT, SlowMA_Period, 0, MODE_EMA, PRICE_CLOSE);
    rsi_handle = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
    
    if(fastMA_handle == INVALID_HANDLE || slowMA_handle == INVALID_HANDLE || rsi_handle == INVALID_HANDLE)
    {
        Print("Error creating indicators");
        return(INIT_FAILED);
    }
    
    lastTradeDay = 0;
    dailyTrades = 0;
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    IndicatorRelease(fastMA_handle);
    IndicatorRelease(slowMA_handle);
    IndicatorRelease(rsi_handle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
    // Reset daily trade counter at new day
    MqlDateTime dt;
    TimeCurrent(dt);
    datetime currentDay = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
    
    if(currentDay != lastTradeDay)
    {
        dailyTrades = 0;
        lastTradeDay = currentDay;
    }
    
    // Check if we can trade
    if(dailyTrades >= MaxDailyTrades) return;
    
    // Check if we already have a position
    if(PositionSelect(_Symbol)) return;
    
    // Get indicator values
    double fastMA[], slowMA[], rsi[];
    ArraySetAsSeries(fastMA, true);
    ArraySetAsSeries(slowMA, true);
    ArraySetAsSeries(rsi, true);
    
    if(CopyBuffer(fastMA_handle, 0, 0, 3, fastMA) < 3) return;
    if(CopyBuffer(slowMA_handle, 0, 0, 3, slowMA) < 3) return;
    if(CopyBuffer(rsi_handle, 0, 0, 3, rsi) < 3) return;
    
    // Check for signals
    bool buySignal = false;
    bool sellSignal = false;
    
    // MA Crossover with RSI filter
    if(fastMA[1] <= slowMA[1] && fastMA[0] > slowMA[0])
    {
        if(rsi[0] < RSI_Overbought && rsi[0] > RSI_Oversold)
            buySignal = true;
    }
    
    if(fastMA[1] >= slowMA[1] && fastMA[0] < slowMA[0])
    {
        if(rsi[0] < RSI_Overbought && rsi[0] > RSI_Oversold)
            sellSignal = true;
    }
    
    // Calculate lot size
    double lotSize = CalculateLotSize();
    
    // Execute trades
    if(buySignal)
    {
        double sl = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - StopLoss_Points * _Point;
        double tp = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + TakeProfit_Points * _Point;
        
        if(OpenTrade(ORDER_TYPE_BUY, lotSize, sl, tp))
            dailyTrades++;
    }
    
    if(sellSignal)
    {
        double sl = SymbolInfoDouble(_Symbol, SYMBOL_BID) + StopLoss_Points * _Point;
        double tp = SymbolInfoDouble(_Symbol, SYMBOL_BID) - TakeProfit_Points * _Point;
        
        if(OpenTrade(ORDER_TYPE_SELL, lotSize, sl, tp))
            dailyTrades++;
    }
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk                              |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = balance * RiskPercent / 100.0;
    
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    
    if(tickValue == 0 || tickSize == 0) return 0.01;
    
    double lotSize = riskAmount / (StopLoss_Points * _Point / tickSize * tickValue);
    
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Open a trade                                                        |
//+------------------------------------------------------------------+
bool OpenTrade(ENUM_ORDER_TYPE type, double lots, double sl, double tp)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lots;
    request.type = type;
    request.price = (type == ORDER_TYPE_BUY) ? 
                    SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                    SymbolInfoDouble(_Symbol, SYMBOL_BID);
    request.sl = sl;
    request.tp = tp;
    request.deviation = 10;
    request.magic = MagicNumber;
    request.comment = "Strategy Tester";
    request.type_filling = ORDER_FILLING_IOC;
    
    if(!OrderSend(request, result))
    {
        Print("OrderSend error: ", GetLastError());
        return false;
    }
    
    if(result.retcode != TRADE_RETCODE_DONE)
    {
        Print("Trade failed: ", result.retcode);
        return false;
    }
    
    return true;
}
//+------------------------------------------------------------------+
