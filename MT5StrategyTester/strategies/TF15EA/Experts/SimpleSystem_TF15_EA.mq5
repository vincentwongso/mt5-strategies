//+------------------------------------------------------------------+
//|                                         SimpleSystem_TF15_EA.mq5 |
//|                    "Another Simple System - Time Frame 15"       |
//|                    Based on ForexFactory Strategy                |
//|                    https://www.forexfactory.com/thread/345586    |
//+------------------------------------------------------------------+
#property copyright "ForexFactory Community Strategy"
#property link      "https://www.forexfactory.com/thread/345586"
#property version   "1.00"
#property description "Another Simple System - Time Frame 15"
#property description "Price action strategy with TDI confirmation"
#property description "Trade during London/NY session for best results"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "═══════════ STRATEGY SETTINGS ═══════════"
input int    EMA_Fast        = 10;        // Fast EMA Period (Entry filter)
input int    EMA_200         = 200;       // 200 EMA Period (1HR 50 equivalent)
input int    EMA_800         = 800;       // 800 EMA Period (4HR 50 equivalent)
input int    MinDistanceEMA  = 15;        // Minimum distance from 200 EMA (pips)
input bool   UseEMA800Filter = true;      // Use 800 EMA as trend filter

input group "═══════════ TDI SETTINGS ═══════════"
input int    TDI_RSI_Period      = 13;    // TDI RSI Period
input int    TDI_Volatility_Band = 34;    // TDI Volatility Band Period
input int    TDI_RSI_Price_Line  = 2;     // TDI RSI Price Line Smoothing
input int    TDI_Trade_Signal    = 7;     // TDI Trade Signal Line Period

input group "═══════════ TRADING SESSION ═══════════"
input bool   UseTradingHours     = true;  // Enable Trading Hours Filter
input int    LondonOpenHour      = 8;     // London Open Hour (Server Time)
input int    LondonCloseHour     = 17;    // London Close Hour (Server Time)
input int    NYOpenHour          = 13;    // New York Open Hour (Server Time)
input int    NYCloseHour         = 22;    // New York Close Hour (Server Time)
input bool   TradeOnlyOverlap    = false; // Trade only during London/NY overlap
input bool   TradeMonday         = true;  // Trade on Monday
input bool   TradeTuesday        = true;  // Trade on Tuesday
input bool   TradeWednesday      = true;  // Trade on Wednesday
input bool   TradeThursday       = true;  // Trade on Thursday
input bool   TradeFriday         = true;  // Trade on Friday

input group "═══════════ MONEY MANAGEMENT ═══════════"
input double RiskPercent    = 0.5;        // Risk per trade (%)
input double StopLossPips   = 20;         // Stop Loss (pips)
input double TakeProfitPips = 40;         // Take Profit (pips) - 0 for TDI exit
input bool   UseBreakeven   = true;       // Use Breakeven
input double BreakevenPips  = 12;         // Move to BE after (pips)
input double BreakevenPlus  = 1;          // BE plus (pips)
input bool   UseTrailingStop = false;     // Use Trailing Stop
input double TrailingStart  = 20;         // Start trailing after (pips)
input double TrailingStep   = 10;         // Trailing step (pips)

input group "═══════════ EXIT OPTIONS ═══════════"
input bool   ExitOnTDICross = false;      // Exit when TDI crosses back
input bool   CloseAtSessionEnd = false;   // Close trades at session end

input group "═══════════ TRADE MANAGEMENT ═══════════"
input int    MaxOpenTrades  = 1;          // Maximum open trades
input int    MagicNumber    = 345586;     // Magic Number
input int    Slippage       = 3;          // Max Slippage (points)
input string TradeComment   = "SimpleSystem_TF15"; // Trade Comment

input group "═══════════ DISPLAY OPTIONS ═══════════"
input bool   ShowInfoPanel  = true;       // Show Information Panel
input color  PanelTextColor = clrWhite;   // Panel Text Color
input color  PanelBgColor   = clrDarkSlateGray; // Panel Background Color

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  posInfo;

// Indicator handles
int handleEMA10, handleEMA200, handleEMA800;
int handleRSI;

// TDI buffers
double TDI_GreenLine[], TDI_RedLine[], TDI_YellowLine[];
double RSIBuffer[];

// EMA buffers
double EMA10_Buffer[], EMA200_Buffer[], EMA800_Buffer[];

// Point value
double pipValue;
int pipDigits;

// Last signal bar
int lastSignalBar = -1;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Initialize trade object
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   //--- Calculate pip value
   pipDigits = (_Digits == 3 || _Digits == 5) ? 1 : 0;
   pipValue = _Point * MathPow(10, pipDigits);
   
   //--- Create indicator handles
   handleEMA10 = iMA(_Symbol, PERIOD_CURRENT, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA200 = iMA(_Symbol, PERIOD_CURRENT, EMA_200, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA800 = iMA(_Symbol, PERIOD_CURRENT, EMA_800, 0, MODE_EMA, PRICE_CLOSE);
   handleRSI = iRSI(_Symbol, PERIOD_CURRENT, TDI_RSI_Period, PRICE_CLOSE);
   
   //--- Check handles
   if(handleEMA10 == INVALID_HANDLE || handleEMA200 == INVALID_HANDLE || 
      handleEMA800 == INVALID_HANDLE || handleRSI == INVALID_HANDLE)
   {
      Print("Error creating indicator handles!");
      return(INIT_FAILED);
   }
   
   //--- Set arrays as series
   ArraySetAsSeries(TDI_GreenLine, true);
   ArraySetAsSeries(TDI_RedLine, true);
   ArraySetAsSeries(TDI_YellowLine, true);
   ArraySetAsSeries(RSIBuffer, true);
   ArraySetAsSeries(EMA10_Buffer, true);
   ArraySetAsSeries(EMA200_Buffer, true);
   ArraySetAsSeries(EMA800_Buffer, true);
   
   //--- Chart settings
   if(ShowInfoPanel)
      CreateInfoPanel();
   
   Print("SimpleSystem TF15 EA initialized successfully!");
   Print("Magic Number: ", MagicNumber);
   Print("Risk per trade: ", RiskPercent, "%");
   Print("Stop Loss: ", StopLossPips, " pips | Take Profit: ", TakeProfitPips, " pips");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release handles
   if(handleEMA10 != INVALID_HANDLE) IndicatorRelease(handleEMA10);
   if(handleEMA200 != INVALID_HANDLE) IndicatorRelease(handleEMA200);
   if(handleEMA800 != INVALID_HANDLE) IndicatorRelease(handleEMA800);
   if(handleRSI != INVALID_HANDLE) IndicatorRelease(handleRSI);
   
   //--- Delete objects
   ObjectsDeleteAll(0, "SS_");
   Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Update info panel
   if(ShowInfoPanel)
      UpdateInfoPanel();
   
   //--- Check for new bar
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   
   if(currentBarTime == lastBarTime)
   {
      //--- Manage existing trades (breakeven, trailing)
      ManageOpenTrades();
      return;
   }
   lastBarTime = currentBarTime;
   
   //--- Get indicator data
   if(!GetIndicatorData())
      return;
   
   //--- Close at session end if enabled
   if(CloseAtSessionEnd && !IsTradingTime())
      CloseAllPositions();
   
   //--- Exit on TDI cross if enabled
   if(ExitOnTDICross)
      CheckTDIExit();
   
   //--- Check trading conditions
   if(!IsTradingAllowed())
      return;
   
   //--- Check for entry signals
   CheckEntrySignals();
   
   //--- Manage existing trades
   ManageOpenTrades();
}

//+------------------------------------------------------------------+
//| Get indicator data                                               |
//+------------------------------------------------------------------+
bool GetIndicatorData()
{
   //--- Copy EMA data
   if(CopyBuffer(handleEMA10, 0, 0, 10, EMA10_Buffer) < 10) return false;
   if(CopyBuffer(handleEMA200, 0, 0, 10, EMA200_Buffer) < 10) return false;
   if(CopyBuffer(handleEMA800, 0, 0, 10, EMA800_Buffer) < 10) return false;
   
   //--- Copy RSI data for TDI calculation
   if(CopyBuffer(handleRSI, 0, 0, TDI_Volatility_Band + 20, RSIBuffer) < TDI_Volatility_Band + 20) return false;
   
   //--- Calculate TDI lines
   CalculateTDI();
   
   return true;
}

//+------------------------------------------------------------------+
//| Calculate TDI lines                                              |
//+------------------------------------------------------------------+
void CalculateTDI()
{
   ArrayResize(TDI_GreenLine, 10);
   ArrayResize(TDI_RedLine, 10);
   ArrayResize(TDI_YellowLine, 10);
   
   for(int i = 0; i < 10; i++)
   {
      //--- Calculate RSI Price Line (Green) - SMA of RSI
      double sumGreen = 0;
      for(int j = 0; j < TDI_RSI_Price_Line && (i + j) < ArraySize(RSIBuffer); j++)
         sumGreen += RSIBuffer[i + j];
      TDI_GreenLine[i] = sumGreen / TDI_RSI_Price_Line;
      
      //--- Calculate Trade Signal Line (Red) - SMA of RSI
      double sumRed = 0;
      for(int j = 0; j < TDI_Trade_Signal && (i + j) < ArraySize(RSIBuffer); j++)
         sumRed += RSIBuffer[i + j];
      TDI_RedLine[i] = sumRed / TDI_Trade_Signal;
      
      //--- Calculate Market Base Line (Yellow) - Middle of Volatility Bands
      double sumYellow = 0;
      for(int j = 0; j < TDI_Volatility_Band && (i + j) < ArraySize(RSIBuffer); j++)
         sumYellow += RSIBuffer[i + j];
      TDI_YellowLine[i] = sumYellow / TDI_Volatility_Band;
   }
}

//+------------------------------------------------------------------+
//| Check if trading is allowed                                      |
//+------------------------------------------------------------------+
bool IsTradingAllowed()
{
   //--- Check if trading is enabled
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return false;
   
   //--- Check open trades limit
   if(CountOpenTrades() >= MaxOpenTrades)
      return false;
   
   //--- Check trading day
   if(!IsTradingDay())
      return false;
   
   //--- Check trading time
   if(UseTradingHours && !IsTradingTime())
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if current day is trading day                              |
//+------------------------------------------------------------------+
bool IsTradingDay()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   switch(dt.day_of_week)
   {
      case 1: return TradeMonday;
      case 2: return TradeTuesday;
      case 3: return TradeWednesday;
      case 4: return TradeThursday;
      case 5: return TradeFriday;
      default: return false;
   }
}

//+------------------------------------------------------------------+
//| Check if current time is within trading hours                    |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
   if(!UseTradingHours)
      return true;
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int currentHour = dt.hour;
   
   bool londonSession = (currentHour >= LondonOpenHour && currentHour < LondonCloseHour);
   bool nySession = (currentHour >= NYOpenHour && currentHour < NYCloseHour);
   
   if(TradeOnlyOverlap)
   {
      //--- London/NY overlap (typically 13:00-17:00)
      return (londonSession && nySession);
   }
   
   return (londonSession || nySession);
}

//+------------------------------------------------------------------+
//| Count open trades with our magic number                          |
//+------------------------------------------------------------------+
int CountOpenTrades()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == MagicNumber)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Check entry signals                                              |
//+------------------------------------------------------------------+
void CheckEntrySignals()
{
   //--- Prevent multiple signals on same bar
   int currentBar = Bars(_Symbol, PERIOD_CURRENT);
   if(currentBar == lastSignalBar)
      return;
   
   //--- Get current price data
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);  // Previous closed candle
   double close2 = iClose(_Symbol, PERIOD_CURRENT, 2);  // Two candles back
   
   double ema10_1 = EMA10_Buffer[1];
   double ema200_1 = EMA200_Buffer[1];
   double ema800_1 = EMA800_Buffer[1];
   
   //--- TDI values (on closed bars)
   double greenLine1 = TDI_GreenLine[1];
   double greenLine2 = TDI_GreenLine[2];
   double yellowLine1 = TDI_YellowLine[1];
   double yellowLine2 = TDI_YellowLine[2];
   
   //--- Calculate distance from 200 EMA in pips
   double distanceFromEMA200 = MathAbs(close1 - ema200_1) / pipValue;
   
   //--- Check minimum distance from 200 EMA (we want to trade AWAY from it)
   bool awayFromEMA = distanceFromEMA200 >= MinDistanceEMA;
   
   //--- TDI Green crosses Yellow (bullish)
   bool tdiCrossUp = (greenLine1 > yellowLine1 && greenLine2 <= yellowLine2);
   
   //--- TDI Green crosses below Yellow (bearish)
   bool tdiCrossDown = (greenLine1 < yellowLine1 && greenLine2 >= yellowLine2);
   
   //--- EMA 800 trend filter
   bool bullishTrend = !UseEMA800Filter || close1 > ema800_1;
   bool bearishTrend = !UseEMA800Filter || close1 < ema800_1;
   
   //+------------------------------------------------------------------+
   //| BUY Signal:                                                      |
   //| 1. Price closes above 10 EMA                                     |
   //| 2. TDI Green crosses above Yellow                                |
   //| 3. Price is AWAY from 200 EMA (not too close)                    |
   //| 4. Price above 800 EMA (if filter enabled)                       |
   //+------------------------------------------------------------------+
   if(close1 > ema10_1 && tdiCrossUp && awayFromEMA && bullishTrend)
   {
      Print("BUY Signal Detected!");
      Print("  Close: ", close1, " > EMA10: ", ema10_1);
      Print("  TDI Green: ", greenLine1, " crossed above Yellow: ", yellowLine1);
      Print("  Distance from EMA200: ", distanceFromEMA200, " pips");
      
      if(OpenBuyTrade())
         lastSignalBar = currentBar;
   }
   
   //+------------------------------------------------------------------+
   //| SELL Signal:                                                     |
   //| 1. Price closes below 10 EMA                                     |
   //| 2. TDI Green crosses below Yellow                                |
   //| 3. Price is AWAY from 200 EMA (not too close)                    |
   //| 4. Price below 800 EMA (if filter enabled)                       |
   //+------------------------------------------------------------------+
   if(close1 < ema10_1 && tdiCrossDown && awayFromEMA && bearishTrend)
   {
      Print("SELL Signal Detected!");
      Print("  Close: ", close1, " < EMA10: ", ema10_1);
      Print("  TDI Green: ", greenLine1, " crossed below Yellow: ", yellowLine1);
      Print("  Distance from EMA200: ", distanceFromEMA200, " pips");
      
      if(OpenSellTrade())
         lastSignalBar = currentBar;
   }
}

//+------------------------------------------------------------------+
//| Open Buy Trade                                                   |
//+------------------------------------------------------------------+
bool OpenBuyTrade()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = ask - StopLossPips * pipValue;
   double tp = (TakeProfitPips > 0) ? ask + TakeProfitPips * pipValue : 0;
   
   double lotSize = CalculateLotSize(StopLossPips);
   
   if(lotSize <= 0)
   {
      Print("Invalid lot size calculated!");
      return false;
   }
   
   //--- Normalize prices
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
   
   if(trade.Buy(lotSize, _Symbol, ask, sl, tp, TradeComment))
   {
      Print("BUY order opened successfully!");
      Print("  Lots: ", lotSize, " | Entry: ", ask, " | SL: ", sl, " | TP: ", tp);
      return true;
   }
   else
   {
      Print("Error opening BUY order: ", GetLastError());
      return false;
   }
}

//+------------------------------------------------------------------+
//| Open Sell Trade                                                  |
//+------------------------------------------------------------------+
bool OpenSellTrade()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = bid + StopLossPips * pipValue;
   double tp = (TakeProfitPips > 0) ? bid - TakeProfitPips * pipValue : 0;
   
   double lotSize = CalculateLotSize(StopLossPips);
   
   if(lotSize <= 0)
   {
      Print("Invalid lot size calculated!");
      return false;
   }
   
   //--- Normalize prices
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
   
   if(trade.Sell(lotSize, _Symbol, bid, sl, tp, TradeComment))
   {
      Print("SELL order opened successfully!");
      Print("  Lots: ", lotSize, " | Entry: ", bid, " | SL: ", sl, " | TP: ", tp);
      return true;
   }
   else
   {
      Print("Error opening SELL order: ", GetLastError());
      return false;
   }
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk                            |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPips)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * (RiskPercent / 100.0);
   
   //--- Get tick value
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double pointValue = tickValue / tickSize * _Point;
   
   //--- Calculate lot size
   double slPoints = slPips * MathPow(10, pipDigits);
   double lotSize = riskAmount / (slPoints * pointValue);
   
   //--- Get lot constraints
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   //--- Normalize lot size
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   
   return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
//| Manage open trades (breakeven, trailing stop)                    |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i))
         continue;
      
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != MagicNumber)
         continue;
      
      double openPrice = posInfo.PriceOpen();
      double currentSL = posInfo.StopLoss();
      double currentTP = posInfo.TakeProfit();
      ulong ticket = posInfo.Ticket();
      
      if(posInfo.PositionType() == POSITION_TYPE_BUY)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double profitPips = (bid - openPrice) / pipValue;
         
         //--- Breakeven
         if(UseBreakeven && profitPips >= BreakevenPips)
         {
            double newSL = openPrice + BreakevenPlus * pipValue;
            if(currentSL < newSL)
            {
               newSL = NormalizeDouble(newSL, _Digits);
               if(trade.PositionModify(ticket, newSL, currentTP))
                  Print("BUY position moved to breakeven. Ticket: ", ticket);
            }
         }
         
         //--- Trailing stop
         if(UseTrailingStop && profitPips >= TrailingStart)
         {
            double newSL = bid - TrailingStep * pipValue;
            if(newSL > currentSL)
            {
               newSL = NormalizeDouble(newSL, _Digits);
               if(trade.PositionModify(ticket, newSL, currentTP))
                  Print("BUY trailing stop updated. Ticket: ", ticket);
            }
         }
      }
      else if(posInfo.PositionType() == POSITION_TYPE_SELL)
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double profitPips = (openPrice - ask) / pipValue;
         
         //--- Breakeven
         if(UseBreakeven && profitPips >= BreakevenPips)
         {
            double newSL = openPrice - BreakevenPlus * pipValue;
            if(currentSL > newSL || currentSL == 0)
            {
               newSL = NormalizeDouble(newSL, _Digits);
               if(trade.PositionModify(ticket, newSL, currentTP))
                  Print("SELL position moved to breakeven. Ticket: ", ticket);
            }
         }
         
         //--- Trailing stop
         if(UseTrailingStop && profitPips >= TrailingStart)
         {
            double newSL = ask + TrailingStep * pipValue;
            if(newSL < currentSL || currentSL == 0)
            {
               newSL = NormalizeDouble(newSL, _Digits);
               if(trade.PositionModify(ticket, newSL, currentTP))
                  Print("SELL trailing stop updated. Ticket: ", ticket);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check TDI Exit signals                                           |
//+------------------------------------------------------------------+
void CheckTDIExit()
{
   if(!ExitOnTDICross)
      return;
   
   //--- TDI cross signals for exit
   double greenLine1 = TDI_GreenLine[1];
   double greenLine2 = TDI_GreenLine[2];
   double redLine1 = TDI_RedLine[1];
   double redLine2 = TDI_RedLine[2];
   
   //--- Green crosses below Red = exit longs
   bool exitLong = (greenLine1 < redLine1 && greenLine2 >= redLine2);
   
   //--- Green crosses above Red = exit shorts
   bool exitShort = (greenLine1 > redLine1 && greenLine2 <= redLine2);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i))
         continue;
      
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != MagicNumber)
         continue;
      
      if(posInfo.PositionType() == POSITION_TYPE_BUY && exitLong)
      {
         trade.PositionClose(posInfo.Ticket());
         Print("BUY position closed on TDI exit signal");
      }
      else if(posInfo.PositionType() == POSITION_TYPE_SELL && exitShort)
      {
         trade.PositionClose(posInfo.Ticket());
         Print("SELL position closed on TDI exit signal");
      }
   }
}

//+------------------------------------------------------------------+
//| Close all positions                                              |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i))
         continue;
      
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != MagicNumber)
         continue;
      
      trade.PositionClose(posInfo.Ticket());
      Print("Position closed - session end");
   }
}

//+------------------------------------------------------------------+
//| Create Information Panel                                         |
//+------------------------------------------------------------------+
void CreateInfoPanel()
{
   string prefix = "SS_Panel_";
   int x = 10, y = 30;
   int lineHeight = 18;
   
   //--- Create background
   ObjectCreate(0, prefix + "BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_XDISTANCE, x - 5);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_YDISTANCE, y - 5);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_XSIZE, 220);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_YSIZE, 200);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_BGCOLOR, PanelBgColor);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_BORDER_COLOR, clrGray);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   
   //--- Create labels
   CreateLabel(prefix + "Title", "SimpleSystem TF15", x, y, clrGold, 10);
   CreateLabel(prefix + "Line1", "-------------------", x, y + lineHeight, clrGray, 8);
   CreateLabel(prefix + "Status", "Status: Initializing", x, y + lineHeight*2, PanelTextColor, 9);
   CreateLabel(prefix + "Session", "Session: --", x, y + lineHeight*3, PanelTextColor, 9);
   CreateLabel(prefix + "TDI", "TDI: Green -- | Yellow --", x, y + lineHeight*4, PanelTextColor, 9);
   CreateLabel(prefix + "EMA10", "EMA10: --", x, y + lineHeight*5, PanelTextColor, 9);
   CreateLabel(prefix + "EMA200", "EMA200: --", x, y + lineHeight*6, PanelTextColor, 9);
   CreateLabel(prefix + "Spread", "Spread: --", x, y + lineHeight*7, PanelTextColor, 9);
   CreateLabel(prefix + "Trades", "Open Trades: 0", x, y + lineHeight*8, PanelTextColor, 9);
   CreateLabel(prefix + "Signal", "Signal: None", x, y + lineHeight*9, clrYellow, 9);
}

//+------------------------------------------------------------------+
//| Create label helper                                              |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color clr, int fontSize)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
}

//+------------------------------------------------------------------+
//| Update Information Panel                                         |
//+------------------------------------------------------------------+
void UpdateInfoPanel()
{
   if(!ShowInfoPanel)
      return;
   
   string prefix = "SS_Panel_";
   
   //--- Status
   string status = IsTradingAllowed() ? "Active" : "Waiting";
   ObjectSetString(0, prefix + "Status", OBJPROP_TEXT, "Status: " + status);
   ObjectSetInteger(0, prefix + "Status", OBJPROP_COLOR, IsTradingAllowed() ? clrLime : clrOrange);
   
   //--- Session
   string session = "Closed";
   if(IsTradingTime())
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      bool london = (dt.hour >= LondonOpenHour && dt.hour < LondonCloseHour);
      bool ny = (dt.hour >= NYOpenHour && dt.hour < NYCloseHour);
      if(london && ny) session = "London/NY Overlap";
      else if(london) session = "London";
      else if(ny) session = "New York";
   }
   ObjectSetString(0, prefix + "Session", OBJPROP_TEXT, "Session: " + session);
   
   //--- TDI
   if(ArraySize(TDI_GreenLine) > 0 && ArraySize(TDI_YellowLine) > 0)
   {
      string tdiText = StringFormat("TDI: G %.1f | Y %.1f", TDI_GreenLine[0], TDI_YellowLine[0]);
      ObjectSetString(0, prefix + "TDI", OBJPROP_TEXT, tdiText);
      color tdiColor = (TDI_GreenLine[0] > TDI_YellowLine[0]) ? clrLime : clrRed;
      ObjectSetInteger(0, prefix + "TDI", OBJPROP_COLOR, tdiColor);
   }
   
   //--- EMAs
   if(ArraySize(EMA10_Buffer) > 0)
      ObjectSetString(0, prefix + "EMA10", OBJPROP_TEXT, "EMA10: " + DoubleToString(EMA10_Buffer[0], _Digits));
   if(ArraySize(EMA200_Buffer) > 0)
      ObjectSetString(0, prefix + "EMA200", OBJPROP_TEXT, "EMA200: " + DoubleToString(EMA200_Buffer[0], _Digits));
   
   //--- Spread
   double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) / MathPow(10, pipDigits);
   ObjectSetString(0, prefix + "Spread", OBJPROP_TEXT, "Spread: " + DoubleToString(spread, 1) + " pips");
   
   //--- Open Trades
   ObjectSetString(0, prefix + "Trades", OBJPROP_TEXT, "Open Trades: " + IntegerToString(CountOpenTrades()));
   
   //--- Signal status
   string signalText = "Signal: None";
   color signalColor = clrYellow;
   
   if(ArraySize(TDI_GreenLine) >= 3 && ArraySize(TDI_YellowLine) >= 3 && ArraySize(EMA10_Buffer) >= 2)
   {
      double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
      bool bullish = (close1 > EMA10_Buffer[1]) && (TDI_GreenLine[1] > TDI_YellowLine[1]);
      bool bearish = (close1 < EMA10_Buffer[1]) && (TDI_GreenLine[1] < TDI_YellowLine[1]);
      
      if(bullish)
      {
         signalText = "Signal: BULLISH";
         signalColor = clrLime;
      }
      else if(bearish)
      {
         signalText = "Signal: BEARISH";
         signalColor = clrRed;
      }
   }
   ObjectSetString(0, prefix + "Signal", OBJPROP_TEXT, signalText);
   ObjectSetInteger(0, prefix + "Signal", OBJPROP_COLOR, signalColor);
}
//+------------------------------------------------------------------+
