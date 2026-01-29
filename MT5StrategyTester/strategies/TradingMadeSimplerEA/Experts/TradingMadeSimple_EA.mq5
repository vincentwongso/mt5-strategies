//+------------------------------------------------------------------+
//|                                       TradingMadeSimple_EA.mq5   |
//|                        Based on RobinHood's Trading Made Simple(r)|
//|                        MT5 Implementation by Claude               |
//+------------------------------------------------------------------+
#property copyright "Based on RobinHood's TMS Strategy"
#property link      "https://www.forexfactory.com/thread/917569"
#property version   "1.00"
#property description "Trading Made Simple(r) EA - MT5 Version"
#property description "Implements Crossover and Continuation trade methods"
#property description "Uses HMA, Heiken Ashi, Synergy APB, RSI, and Stochastics"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input group "=== Trade Settings ==="
input double   InpLotSize           = 0.1;       // Lot Size (0 = Auto)
input double   InpRiskPercent       = 1.0;       // Risk % per Trade (if Lot=0)
input int      InpMagicNumber       = 20240125;  // Magic Number
input int      InpMaxSpread         = 50;        // Max Spread (points)
input bool     InpUseTrailingStop   = true;      // Use Trailing Stop
input int      InpTrailingStart     = 50;        // Trailing Start (points)
input int      InpTrailingStep      = 20;        // Trailing Step (points)

input group "=== Entry Methods ==="
input bool     InpTradeCrossovers   = true;      // Trade Crossover Signals
input bool     InpTradeContinuation = true;      // Trade Continuation Signals
input int      InpMaxBarsAfterCross = 3;         // Max Bars After Crossover
input bool     InpRequireAllConfirm = true;      // Require All Confirmations
input bool     InpUseCustomHMA      = true;      // Use Custom HMA Indicator (if false, uses built-in calc)
input bool     InpUseCustomHA       = true;      // Use Custom Heiken Ashi (if false, uses built-in calc)

input group "=== EMA Settings ==="
input int      InpEMA_Period        = 5;         // EMA Period (Yellow Line)
input int      InpEMA_Shift         = 2;         // EMA Shift
input ENUM_APPLIED_PRICE InpEMA_Price = PRICE_CLOSE; // EMA Applied Price

input group "=== HMA Settings ==="
input int      InpHMA_Period        = 12;        // HMA Period
input ENUM_MA_METHOD InpHMA_Method  = MODE_LWMA; // HMA MA Method
input ENUM_APPLIED_PRICE InpHMA_Price = PRICE_CLOSE; // HMA Applied Price

input group "=== Stochastic Settings ==="
input int      InpStoch1_K          = 8;         // Stochastic 1 K Period
input int      InpStoch1_D          = 3;         // Stochastic 1 D Period
input int      InpStoch1_Slow       = 3;         // Stochastic 1 Slowing
input int      InpStoch2_K          = 14;        // Stochastic 2 K Period
input int      InpStoch2_D          = 3;         // Stochastic 2 D Period
input int      InpStoch2_Slow       = 3;         // Stochastic 2 Slowing
input int      InpStochLevel        = 50;        // Stochastic Level (50 line)

input group "=== RSI Settings ==="
input int      InpRSI_Period        = 14;        // RSI Period
input ENUM_APPLIED_PRICE InpRSI_Price = PRICE_CLOSE; // RSI Applied Price
input int      InpRSI_Level         = 50;        // RSI Level (50 line)

input group "=== Stop Loss Settings ==="
input int      InpSL_Bars           = 2;         // SL Bars Back (1-3)
input int      InpSL_Buffer         = 10;        // SL Buffer (points)

input group "=== Take Profit Settings ==="
input bool     InpUseFixedTP        = false;     // Use Fixed TP
input double   InpTPRatio           = 1.5;       // TP:SL Ratio
input int      InpFixedTP           = 100;       // Fixed TP (points)

input group "=== Trading Sessions ==="
input bool     InpUseTradingHours   = false;     // Use Trading Hours Filter
input int      InpStartHour         = 8;         // Start Hour (Server Time)
input int      InpEndHour           = 20;        // End Hour (Server Time)

input group "=== Exit Settings ==="
input bool     InpExitOnColorChange = true;      // Exit on Candle Color Change
input bool     InpExitOnHMACross    = true;      // Exit on HMA/EMA Cross
input bool     InpExitOnRSICross    = false;     // Exit on RSI Cross 50
input bool     InpExitOnStochCross  = false;     // Exit on Stochastic Cross 50

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  positionInfo;
CSymbolInfo    symbolInfo;

// Indicator handles
int hEMA;
int hHMA;
int hStoch1;
int hStoch2;
int hRSI;
int hHeikenAshi;
int hWMA_Half;
int hWMA_Full;

// Indicator buffers
double bufEMA[];
double bufHMA_Up[];
double bufHMA_Down[];
double bufHMA_Main[];
double bufStoch1_Main[];
double bufStoch1_Signal[];
double bufStoch2_Main[];
double bufStoch2_Signal[];
double bufRSI[];
double bufHA_Open[];
double bufHA_Close[];

// Trade state
int lastCrossoverBar = -1;
ENUM_ORDER_TYPE lastCrossoverType = ORDER_TYPE_BUY;
bool waitingForEntry = false;
int barsSinceCrossover = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize symbol info
   if(!symbolInfo.Name(_Symbol))
   {
      Print("Failed to initialize symbol info");
      return INIT_FAILED;
   }
   
   // Initialize trade object
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetMarginMode();
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(10);
   
   // Create EMA indicator
   hEMA = iMA(_Symbol, PERIOD_CURRENT, InpEMA_Period, InpEMA_Shift, MODE_EMA, InpEMA_Price);
   if(hEMA == INVALID_HANDLE)
   {
      Print("Failed to create EMA indicator");
      return INIT_FAILED;
   }
   
   // Create HMA indicator (using custom indicator)
   string hmaPaths[] = {
      "TMS_Indicators\\HMA_TMS",
      "HMA_TMS",
      "TradingMadeSimplerEA\\Indicators\\TMS_Indicators\\HMA_TMS"
   };
   
   hHMA = INVALID_HANDLE;
   
   if(InpUseCustomHMA)
   {
      for(int i=0; i<ArraySize(hmaPaths); i++)
      {
         ResetLastError();
         hHMA = iCustom(_Symbol, PERIOD_CURRENT, hmaPaths[i], InpHMA_Period, InpHMA_Method, InpHMA_Price);
         if(hHMA != INVALID_HANDLE)
         {
            Print("Found HMA indicator at: ", hmaPaths[i]);
            break;
         }
      }
   }

   if(hHMA == INVALID_HANDLE)
   {
      // Try alternative - built-in implementation
      if(InpUseCustomHMA)
         Print("HMA custom indicator not found in common paths, using built-in calculation");
      else
         Print("Using built-in HMA calculation (Custom HMA disabled)");
         
      hHMA = INVALID_HANDLE; // Will calculate manually
      
      // Initialize handles for manual calculation
      hWMA_Half = iMA(_Symbol, PERIOD_CURRENT, InpHMA_Period/2, 0, InpHMA_Method, InpHMA_Price);
      hWMA_Full = iMA(_Symbol, PERIOD_CURRENT, InpHMA_Period, 0, InpHMA_Method, InpHMA_Price);
   }
   
   // Create Stochastic indicators
   hStoch1 = iStochastic(_Symbol, PERIOD_CURRENT, InpStoch1_K, InpStoch1_D, InpStoch1_Slow, MODE_SMA, STO_LOWHIGH);
   hStoch2 = iStochastic(_Symbol, PERIOD_CURRENT, InpStoch2_K, InpStoch2_D, InpStoch2_Slow, MODE_SMA, STO_LOWHIGH);
   
   if(hStoch1 == INVALID_HANDLE || hStoch2 == INVALID_HANDLE)
   {
      Print("Failed to create Stochastic indicators");
      return INIT_FAILED;
   }
   
   // Create RSI indicator
   hRSI = iRSI(_Symbol, PERIOD_CURRENT, InpRSI_Period, InpRSI_Price);
   if(hRSI == INVALID_HANDLE)
   {
      Print("Failed to create RSI indicator");
      return INIT_FAILED;
   }
   
   // Create Heiken Ashi indicator
   string haPaths[] = {
      "TMS_Indicators\\Heiken_Ashi_TMS",
      "Heiken_Ashi_TMS",
      "TradingMadeSimplerEA\\Indicators\\TMS_Indicators\\Heiken_Ashi_TMS",
      "Examples\\Heiken_Ashi"
   };
   
   hHeikenAshi = INVALID_HANDLE;
   
   if(InpUseCustomHA)
   {
      for(int i=0; i<ArraySize(haPaths); i++)
      {
         ResetLastError();
         hHeikenAshi = iCustom(_Symbol, PERIOD_CURRENT, haPaths[i]);
         if(hHeikenAshi != INVALID_HANDLE)
         {
            Print("Found Heiken Ashi indicator at: ", haPaths[i]);
            break;
         }
      }
   }
   
   if(hHeikenAshi == INVALID_HANDLE)
   {
      if(InpUseCustomHA)
         Print("Heiken Ashi indicator not found, using built-in calculation");
      else
         Print("Using built-in Heiken Ashi calculation (Custom HA disabled)");
         
      hHeikenAshi = INVALID_HANDLE;
   }
   
   // Set arrays as series
   ArraySetAsSeries(bufEMA, true);
   ArraySetAsSeries(bufHMA_Up, true);
   ArraySetAsSeries(bufHMA_Down, true);
   ArraySetAsSeries(bufHMA_Main, true);
   ArraySetAsSeries(bufStoch1_Main, true);
   ArraySetAsSeries(bufStoch1_Signal, true);
   ArraySetAsSeries(bufStoch2_Main, true);
   ArraySetAsSeries(bufStoch2_Signal, true);
   ArraySetAsSeries(bufRSI, true);
   ArraySetAsSeries(bufHA_Open, true);
   ArraySetAsSeries(bufHA_Close, true);
   
   Print("Trading Made Simple EA initialized successfully");
   Print("Symbol: ", _Symbol, " | Timeframe: ", EnumToString(Period()));
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(hEMA != INVALID_HANDLE) IndicatorRelease(hEMA);
   if(hHMA != INVALID_HANDLE) IndicatorRelease(hHMA);
   if(hStoch1 != INVALID_HANDLE) IndicatorRelease(hStoch1);
   if(hStoch2 != INVALID_HANDLE) IndicatorRelease(hStoch2);
   if(hRSI != INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hHeikenAshi != INVALID_HANDLE) IndicatorRelease(hHeikenAshi);
   if(hWMA_Half != INVALID_HANDLE) IndicatorRelease(hWMA_Half);
   if(hWMA_Full != INVALID_HANDLE) IndicatorRelease(hWMA_Full);
   
   Print("Trading Made Simple EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new bar
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   
   bool isNewBar = (currentBarTime != lastBarTime);
   if(isNewBar)
      lastBarTime = currentBarTime;
   
   // Update trailing stop every tick
   if(InpUseTrailingStop)
      ManageTrailingStop();
   
   // Only process signals on new bar
   if(!isNewBar)
      return;
   
   // Check trading hours
   if(InpUseTradingHours && !IsTradingTime())
      return;
   
   // Check spread
   if(!CheckSpread())
      return;
   
   // Get indicator values
   if(!GetIndicatorValues())
      return;
   
   // Check for exit signals first
   if(HasOpenPosition())
   {
      if(CheckExitSignals())
      {
         CloseAllPositions();
         return;
      }
   }
   
   // Check for entry signals
   if(!HasOpenPosition())
   {
      int signal = GetTradeSignal();
      if(signal != 0)
      {
         ExecuteTrade(signal);
      }
   }
}

//+------------------------------------------------------------------+
//| Get all indicator values                                          |
//+------------------------------------------------------------------+
bool GetIndicatorValues()
{
   int barsRequired = 10;
   
   // Get EMA values
   if(CopyBuffer(hEMA, 0, 0, barsRequired, bufEMA) < barsRequired)
      return false;
   
   // Get Stochastic 1 values
   if(CopyBuffer(hStoch1, MAIN_LINE, 0, barsRequired, bufStoch1_Main) < barsRequired)
      return false;
   if(CopyBuffer(hStoch1, SIGNAL_LINE, 0, barsRequired, bufStoch1_Signal) < barsRequired)
      return false;
   
   // Get Stochastic 2 values
   if(CopyBuffer(hStoch2, MAIN_LINE, 0, barsRequired, bufStoch2_Main) < barsRequired)
      return false;
   if(CopyBuffer(hStoch2, SIGNAL_LINE, 0, barsRequired, bufStoch2_Signal) < barsRequired)
      return false;
   
   // Get RSI values
   if(CopyBuffer(hRSI, 0, 0, barsRequired, bufRSI) < barsRequired)
      return false;
   
   // Get HMA values (or calculate if custom indicator not available)
   if(hHMA != INVALID_HANDLE)
   {
      if(CopyBuffer(hHMA, 0, 0, barsRequired, bufHMA_Up) < barsRequired)
         CalculateHMA(barsRequired);
      else
         if(CopyBuffer(hHMA, 1, 0, barsRequired, bufHMA_Down) < barsRequired)
            CalculateHMA(barsRequired);
   }
   else
   {
      CalculateHMA(barsRequired);
   }
   
   // Get Heiken Ashi values (or calculate if custom indicator not available)
   if(hHeikenAshi != INVALID_HANDLE)
   {
      if(CopyBuffer(hHeikenAshi, 2, 0, barsRequired, bufHA_Open) < barsRequired)
         CalculateHeikenAshi(barsRequired);
      else
         if(CopyBuffer(hHeikenAshi, 3, 0, barsRequired, bufHA_Close) < barsRequired)
            CalculateHeikenAshi(barsRequired);
   }
   else
   {
      CalculateHeikenAshi(barsRequired);
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Calculate LWMA on array                                           |
//+------------------------------------------------------------------+
void CalculateLWMAOnArray(const double &src[], int period, int bars, double &dst[])
{
   ArrayResize(dst, bars);
   ArraySetAsSeries(dst, true);
   
   for(int i = 0; i < bars; i++)
   {
      double sum = 0;
      double sumw = 0;
      
      for(int k = 0; k < period; k++)
      {
         if(i + k >= ArraySize(src)) break;
         
         double weight = period - k;
         sum += src[i + k] * weight;
         sumw += weight;
      }
      
      if(sumw > 0)
         dst[i] = sum / sumw;
      else
         dst[i] = 0;
   }
}

//+------------------------------------------------------------------+
//| Calculate HMA manually if indicator not available                 |
//+------------------------------------------------------------------+
void CalculateHMA(int bars)
{
   if(hWMA_Half == INVALID_HANDLE || hWMA_Full == INVALID_HANDLE)
      return;

   ArrayResize(bufHMA_Main, bars);
   ArrayResize(bufHMA_Up, bars);
   ArrayResize(bufHMA_Down, bars);
   ArraySetAsSeries(bufHMA_Main, true);
   ArraySetAsSeries(bufHMA_Up, true);
   ArraySetAsSeries(bufHMA_Down, true);
   
   int period = InpHMA_Period;
   int sqrtPeriod = (int)MathSqrt(period);
   
   // We need enough data for the final WMA
   int requiredRaw = bars + sqrtPeriod;
   
   double wma1[], wma2[];
   ArrayResize(wma1, requiredRaw);
   ArrayResize(wma2, requiredRaw);
   ArraySetAsSeries(wma1, true);
   ArraySetAsSeries(wma2, true);
   
   if(CopyBuffer(hWMA_Half, 0, 0, requiredRaw, wma1) < requiredRaw) return;
   if(CopyBuffer(hWMA_Full, 0, 0, requiredRaw, wma2) < requiredRaw) return;
   
   double rawHMA[];
   ArrayResize(rawHMA, requiredRaw);
   ArraySetAsSeries(rawHMA, true);
   
   for(int i = 0; i < requiredRaw; i++)
   {
      rawHMA[i] = 2 * wma1[i] - wma2[i];
   }
   
   // Now calculate WMA of rawHMA
   CalculateLWMAOnArray(rawHMA, sqrtPeriod, bars, bufHMA_Main);
   
   // Determine trend color
   for(int i = 0; i < bars; i++)
   {
      if(i < bars - 1)
      {
         if(bufHMA_Main[i] > bufHMA_Main[i+1])
         {
            bufHMA_Up[i] = bufHMA_Main[i];
            bufHMA_Down[i] = 0;
         }
         else
         {
            bufHMA_Down[i] = bufHMA_Main[i];
            bufHMA_Up[i] = 0;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate Heiken Ashi manually                                    |
//+------------------------------------------------------------------+
void CalculateHeikenAshi(int bars)
{
   ArrayResize(bufHA_Open, bars);
   ArrayResize(bufHA_Close, bars);
   ArraySetAsSeries(bufHA_Open, true);
   ArraySetAsSeries(bufHA_Close, true);
   
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   if(CopyRates(_Symbol, PERIOD_CURRENT, 0, bars + 1, rates) < bars + 1)
      return;
   
   // Calculate from oldest to newest
   for(int i = bars - 1; i >= 0; i--)
   {
      double haClose = (rates[i].open + rates[i].high + rates[i].low + rates[i].close) / 4.0;
      double haOpen;
      
      if(i == bars - 1)
         haOpen = (rates[i+1].open + rates[i+1].close) / 2.0;
      else
         haOpen = (bufHA_Open[i+1] + bufHA_Close[i+1]) / 2.0;
      
      bufHA_Open[i] = haOpen;
      bufHA_Close[i] = haClose;
   }
}

//+------------------------------------------------------------------+
//| Get candle color based on Heiken Ashi and Synergy APB logic       |
//+------------------------------------------------------------------+
int GetCandleColor(int bar)
{
   // Returns: 1 = Bullish (Blue/Green), -1 = Bearish (Red), 0 = Neutral
   
   if(bar >= ArraySize(bufHA_Open) || bar >= ArraySize(bufHA_Close))
      return 0;
   
   // Heiken Ashi color
   bool haBullish = bufHA_Close[bar] > bufHA_Open[bar];
   
   // Synergy APB style - check price action
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, PERIOD_CURRENT, bar, 1, rates) < 1)
      return 0;
   
   bool priceBullish = rates[0].close > rates[0].open;
   
   // Combined signal - both need to agree for strong signal
   if(haBullish && priceBullish)
      return 1;  // Strong bullish
   else if(!haBullish && !priceBullish)
      return -1; // Strong bearish
   else
      return 0;  // Mixed/neutral
}

//+------------------------------------------------------------------+
//| Get HMA trend direction                                           |
//+------------------------------------------------------------------+
int GetHMATrend(int bar)
{
   // Returns: 1 = Uptrend (Lime), -1 = Downtrend (Pink), 0 = Neutral
   
   if(bar >= ArraySize(bufHMA_Main) - 1)
      return 0;
   
   if(bufHMA_Main[bar] > bufHMA_Main[bar + 1])
      return 1;  // Uptrend
   else if(bufHMA_Main[bar] < bufHMA_Main[bar + 1])
      return -1; // Downtrend
   
   return 0;
}

//+------------------------------------------------------------------+
//| Check if HMA crossed EMA                                          |
//+------------------------------------------------------------------+
int CheckHMACross(int bar)
{
   // Returns: 1 = Bullish cross, -1 = Bearish cross, 0 = No cross
   
   if(bar >= ArraySize(bufHMA_Main) - 1 || bar >= ArraySize(bufEMA) - 1)
      return 0;
   
   double hmaCurrent = bufHMA_Main[bar];
   double hmaPrev = bufHMA_Main[bar + 1];
   double emaCurrent = bufEMA[bar];
   double emaPrev = bufEMA[bar + 1];
   
   // Bullish crossover
   if(hmaPrev <= emaPrev && hmaCurrent > emaCurrent)
      return 1;
   
   // Bearish crossover
   if(hmaPrev >= emaPrev && hmaCurrent < emaCurrent)
      return -1;
   
   return 0;
}

//+------------------------------------------------------------------+
//| Check Stochastic conditions                                       |
//+------------------------------------------------------------------+
bool CheckStochCondition(int direction, int bar)
{
   // direction: 1 = Long, -1 = Short
   
   if(bar >= ArraySize(bufStoch1_Main) || bar >= ArraySize(bufStoch2_Main))
      return false;
   
   double stoch1 = bufStoch1_Main[bar];
   double stoch2 = bufStoch2_Main[bar];
   int level = InpStochLevel;
   
   if(direction == 1) // Long
   {
      // Both stochastics above or crossing above 50
      bool stoch1OK = stoch1 > level || (bar < ArraySize(bufStoch1_Main) - 1 && 
                      bufStoch1_Main[bar + 1] <= level && stoch1 > level);
      bool stoch2OK = stoch2 > level || (bar < ArraySize(bufStoch2_Main) - 1 && 
                      bufStoch2_Main[bar + 1] <= level && stoch2 > level);
      
      // At least one crossed and other is close
      if(stoch1OK || (stoch1 > level - 10 && stoch2OK))
         if(stoch2OK || (stoch2 > level - 10 && stoch1OK))
            return true;
   }
   else // Short
   {
      bool stoch1OK = stoch1 < level || (bar < ArraySize(bufStoch1_Main) - 1 && 
                      bufStoch1_Main[bar + 1] >= level && stoch1 < level);
      bool stoch2OK = stoch2 < level || (bar < ArraySize(bufStoch2_Main) - 1 && 
                      bufStoch2_Main[bar + 1] >= level && stoch2 < level);
      
      if(stoch1OK || (stoch1 < level + 10 && stoch2OK))
         if(stoch2OK || (stoch2 < level + 10 && stoch1OK))
            return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check RSI condition                                               |
//+------------------------------------------------------------------+
bool CheckRSICondition(int direction, int bar)
{
   if(bar >= ArraySize(bufRSI))
      return false;
   
   double rsi = bufRSI[bar];
   int level = InpRSI_Level;
   
   if(direction == 1) // Long
      return rsi > level;
   else // Short
      return rsi < level;
}

//+------------------------------------------------------------------+
//| Check if price is on correct side of EMA                          |
//+------------------------------------------------------------------+
bool CheckPriceVsEMA(int direction, int bar)
{
   if(bar >= ArraySize(bufEMA))
      return false;
   
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, PERIOD_CURRENT, bar, 1, rates) < 1)
      return false;
   
   double closePrice = rates[0].close;
   double ema = bufEMA[bar];
   
   if(direction == 1) // Long
      return closePrice > ema;
   else // Short
      return closePrice < ema;
}

//+------------------------------------------------------------------+
//| Get trade signal                                                  |
//+------------------------------------------------------------------+
int GetTradeSignal()
{
   // Returns: 1 = Buy, -1 = Sell, 0 = No signal
   
   int signal = 0;
   
   // Check for Crossover signals
   if(InpTradeCrossovers)
   {
      signal = CheckCrossoverSignal();
      if(signal != 0)
      {
         Print("Crossover signal detected: ", signal == 1 ? "BUY" : "SELL");
         return signal;
      }
   }
   
   // Check for Continuation signals
   if(InpTradeContinuation)
   {
      signal = CheckContinuationSignal();
      if(signal != 0)
      {
         Print("Continuation signal detected: ", signal == 1 ? "BUY" : "SELL");
         return signal;
      }
   }
   
   return 0;
}

//+------------------------------------------------------------------+
//| Check for Crossover trade signals                                 |
//+------------------------------------------------------------------+
int CheckCrossoverSignal()
{
   // Bar 1 is the completed bar (setup bar), Bar 2 is previous
   int setupBar = 1;
   
   // 1. Check HMA cross EMA
   int crossSignal = 0;
   for(int i = 1; i <= InpMaxBarsAfterCross; i++)
   {
      crossSignal = CheckHMACross(i);
      if(crossSignal != 0)
      {
         barsSinceCrossover = i;
         break;
      }
   }
   
   if(crossSignal == 0)
      return 0;
   
   // 2. Check HMA trend color matches direction
   int hmaTrend = GetHMATrend(setupBar);
   if(hmaTrend != crossSignal)
   {
      Print("Crossover rejected: HMA trend mismatch. Signal: ", crossSignal, ", HMA: ", hmaTrend);
      return 0;
   }
   
   // 3. Check candle colors changed
   int currentColor = GetCandleColor(setupBar);
   int prevColor = GetCandleColor(setupBar + 1);
   
   // Colors should match trade direction
   if(crossSignal == 1 && currentColor != 1) // Need bullish for buy
   {
      Print("Crossover rejected: Candle color mismatch for Buy. Color: ", currentColor);
      return 0;
   }
   if(crossSignal == -1 && currentColor != -1) // Need bearish for sell
   {
      Print("Crossover rejected: Candle color mismatch for Sell. Color: ", currentColor);
      return 0;
   }
   
   // 4. Check price closed on correct side of EMA
   if(!CheckPriceVsEMA(crossSignal, setupBar))
   {
      Print("Crossover rejected: Price not on correct side of EMA");
      return 0;
   }
   
   // 5. Check Stochastic conditions
   if(InpRequireAllConfirm && !CheckStochCondition(crossSignal, setupBar))
   {
      Print("Crossover rejected: Stochastic condition failed");
      return 0;
   }
   
   // 6. Check RSI condition
   if(InpRequireAllConfirm && !CheckRSICondition(crossSignal, setupBar))
   {
      Print("Crossover rejected: RSI condition failed");
      return 0;
   }
   
   // 7. Check setup bar momentum (close vs open)
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, PERIOD_CURRENT, setupBar, 1, rates) < 1)
      return 0;
   
   if(crossSignal == 1 && rates[0].close <= rates[0].open)
   {
      Print("Crossover rejected: Setup bar not bullish");
      return 0; // Setup bar should be bullish for buy
   }
   if(crossSignal == -1 && rates[0].close >= rates[0].open)
   {
      Print("Crossover rejected: Setup bar not bearish");
      return 0; // Setup bar should be bearish for sell
   }
   
   return crossSignal;
}

//+------------------------------------------------------------------+
//| Check for Continuation trade signals                              |
//+------------------------------------------------------------------+
int CheckContinuationSignal()
{
   int setupBar = 1;
   int prevBar = 2;
   int prevPrevBar = 3;
   
   // Get current and previous candle colors
   int currentColor = GetCandleColor(setupBar);
   int prevColor = GetCandleColor(prevBar);
   int prevPrevColor = GetCandleColor(prevPrevBar);
   
   // Check for continuation pattern
   // Buy: Was bullish, turned bearish briefly, now bullish again
   // Sell: Was bearish, turned bullish briefly, now bearish again
   
   int signal = 0;
   
   // Bullish continuation
   if(currentColor == 1 && prevColor != 1 && prevPrevColor == 1)
   {
      signal = 1;
   }
   // Bearish continuation
   else if(currentColor == -1 && prevColor != -1 && prevPrevColor == -1)
   {
      signal = -1;
   }
   
   if(signal == 0)
      return 0;
   
   // Check price on correct side of EMA
   if(!CheckPriceVsEMA(signal, setupBar))
   {
      Print("Continuation rejected: Price not on correct side of EMA");
      return 0;
   }
   
   // Check HMA trend
   int hmaTrend = GetHMATrend(setupBar);
   if(hmaTrend != signal)
   {
      Print("Continuation rejected: HMA trend mismatch");
      return 0;
   }
   
   // Check stochastic conditions
   if(InpRequireAllConfirm && !CheckStochCondition(signal, setupBar))
   {
      Print("Continuation rejected: Stochastic condition failed");
      return 0;
   }
   
   // Check RSI condition
   if(InpRequireAllConfirm && !CheckRSICondition(signal, setupBar))
   {
      Print("Continuation rejected: RSI condition failed");
      return 0;
   }
   
   return signal;
}

//+------------------------------------------------------------------+
//| Check exit signals                                                |
//+------------------------------------------------------------------+
bool CheckExitSignals()
{
   int positionType = GetPositionType();
   if(positionType == 0)
      return false;
   
   int setupBar = 1;
   
   // Exit on candle color change
   if(InpExitOnColorChange)
   {
      int currentColor = GetCandleColor(setupBar);
      if(positionType == 1 && currentColor == -1) // Long position, bearish candle
      {
         Print("Exit signal: Candle color changed to bearish");
         return true;
      }
      if(positionType == -1 && currentColor == 1) // Short position, bullish candle
      {
         Print("Exit signal: Candle color changed to bullish");
         return true;
      }
   }
   
   // Exit on HMA/EMA cross
   if(InpExitOnHMACross)
   {
      int crossSignal = CheckHMACross(setupBar);
      if(positionType == 1 && crossSignal == -1)
      {
         Print("Exit signal: HMA crossed below EMA");
         return true;
      }
      if(positionType == -1 && crossSignal == 1)
      {
         Print("Exit signal: HMA crossed above EMA");
         return true;
      }
   }
   
   // Exit on RSI cross 50
   if(InpExitOnRSICross)
   {
      if(setupBar < ArraySize(bufRSI) - 1)
      {
         double rsiCurrent = bufRSI[setupBar];
         double rsiPrev = bufRSI[setupBar + 1];
         
         if(positionType == 1 && rsiPrev > InpRSI_Level && rsiCurrent < InpRSI_Level)
         {
            Print("Exit signal: RSI crossed below 50");
            return true;
         }
         if(positionType == -1 && rsiPrev < InpRSI_Level && rsiCurrent > InpRSI_Level)
         {
            Print("Exit signal: RSI crossed above 50");
            return true;
         }
      }
   }
   
   // Exit on Stochastic cross 50
   if(InpExitOnStochCross)
   {
      if(setupBar < ArraySize(bufStoch1_Main) - 1)
      {
         double stochCurrent = bufStoch1_Main[setupBar];
         double stochPrev = bufStoch1_Main[setupBar + 1];
         
         if(positionType == 1 && stochPrev > InpStochLevel && stochCurrent < InpStochLevel)
         {
            Print("Exit signal: Stochastic crossed below 50");
            return true;
         }
         if(positionType == -1 && stochPrev < InpStochLevel && stochCurrent > InpStochLevel)
         {
            Print("Exit signal: Stochastic crossed above 50");
            return true;
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Execute trade                                                     |
//+------------------------------------------------------------------+
void ExecuteTrade(int direction)
{
   if(direction == 0)
      return;
   
   symbolInfo.RefreshRates();
   
   double lotSize = CalculateLotSize(direction);
   if(lotSize <= 0)
   {
      Print("Invalid lot size calculated");
      return;
   }
   
   double sl = CalculateStopLoss(direction);
   double tp = CalculateTakeProfit(direction, sl);
   
   double price = (direction == 1) ? symbolInfo.Ask() : symbolInfo.Bid();
   ENUM_ORDER_TYPE orderType = (direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   
   string comment = "TMS_" + (direction == 1 ? "BUY" : "SELL");
   
   if(trade.PositionOpen(_Symbol, orderType, lotSize, price, sl, tp, comment))
   {
      Print("Trade opened successfully: ", comment, " | Lot: ", lotSize, " | SL: ", sl, " | TP: ", tp);
   }
   else
   {
      Print("Trade failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size                                                |
//+------------------------------------------------------------------+
double CalculateLotSize(int direction)
{
   if(InpLotSize > 0)
      return NormalizeLot(InpLotSize);
   
   // Calculate based on risk
   double sl = CalculateStopLoss(direction);
   double price = (direction == 1) ? symbolInfo.Ask() : symbolInfo.Bid();
   double slPoints = MathAbs(price - sl) / symbolInfo.Point();
   
   if(slPoints <= 0)
      return NormalizeLot(symbolInfo.LotsMin());
   
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * InpRiskPercent / 100.0;
   double tickValue = symbolInfo.TickValue();
   
   double lotSize = riskAmount / (slPoints * tickValue);
   
   return NormalizeLot(lotSize);
}

//+------------------------------------------------------------------+
//| Normalize lot size                                                |
//+------------------------------------------------------------------+
double NormalizeLot(double lots)
{
   double minLot = symbolInfo.LotsMin();
   double maxLot = symbolInfo.LotsMax();
   double lotStep = symbolInfo.LotsStep();
   
   lots = MathMax(minLot, lots);
   lots = MathMin(maxLot, lots);
   lots = MathFloor(lots / lotStep) * lotStep;
   
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Calculate stop loss                                               |
//+------------------------------------------------------------------+
double CalculateStopLoss(int direction)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   int barsToCheck = InpSL_Bars + 1; // +1 for current bar reference
   if(CopyRates(_Symbol, PERIOD_CURRENT, 1, barsToCheck, rates) < barsToCheck)
      return 0;
   
   double sl;
   double buffer = InpSL_Buffer * symbolInfo.Point();
   
   if(direction == 1) // Buy - SL below low of bars back
   {
      double lowestLow = rates[InpSL_Bars - 1].low;
      for(int i = 0; i < InpSL_Bars; i++)
      {
         if(rates[i].low < lowestLow)
            lowestLow = rates[i].low;
      }
      sl = lowestLow - buffer;
   }
   else // Sell - SL above high of bars back
   {
      double highestHigh = rates[InpSL_Bars - 1].high;
      for(int i = 0; i < InpSL_Bars; i++)
      {
         if(rates[i].high > highestHigh)
            highestHigh = rates[i].high;
      }
      sl = highestHigh + buffer;
   }
   
   return NormalizeDouble(sl, symbolInfo.Digits());
}

//+------------------------------------------------------------------+
//| Calculate take profit                                             |
//+------------------------------------------------------------------+
double CalculateTakeProfit(int direction, double sl)
{
   symbolInfo.RefreshRates();
   double price = (direction == 1) ? symbolInfo.Ask() : symbolInfo.Bid();
   double tp;
   
   if(InpUseFixedTP)
   {
      double tpDistance = InpFixedTP * symbolInfo.Point();
      tp = (direction == 1) ? price + tpDistance : price - tpDistance;
   }
   else
   {
      double slDistance = MathAbs(price - sl);
      double tpDistance = slDistance * InpTPRatio;
      tp = (direction == 1) ? price + tpDistance : price - tpDistance;
   }
   
   return NormalizeDouble(tp, symbolInfo.Digits());
}

//+------------------------------------------------------------------+
//| Check if has open position                                        |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Get position type (1=Buy, -1=Sell, 0=None)                        |
//+------------------------------------------------------------------+
int GetPositionType()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
         {
            if(positionInfo.PositionType() == POSITION_TYPE_BUY)
               return 1;
            else
               return -1;
         }
      }
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Close all positions                                               |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
         {
            trade.PositionClose(positionInfo.Ticket());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage trailing stop                                              |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!positionInfo.SelectByIndex(i))
         continue;
      
      if(positionInfo.Symbol() != _Symbol || positionInfo.Magic() != InpMagicNumber)
         continue;
      
      symbolInfo.RefreshRates();
      
      double currentSL = positionInfo.StopLoss();
      double openPrice = positionInfo.PriceOpen();
      double currentPrice;
      double newSL;
      
      if(positionInfo.PositionType() == POSITION_TYPE_BUY)
      {
         currentPrice = symbolInfo.Bid();
         double profit = (currentPrice - openPrice) / symbolInfo.Point();
         
         if(profit >= InpTrailingStart)
         {
            newSL = currentPrice - InpTrailingStep * symbolInfo.Point();
            newSL = NormalizeDouble(newSL, symbolInfo.Digits());
            
            if(newSL > currentSL + symbolInfo.Point())
            {
               trade.PositionModify(positionInfo.Ticket(), newSL, positionInfo.TakeProfit());
            }
         }
      }
      else // SELL
      {
         currentPrice = symbolInfo.Ask();
         double profit = (openPrice - currentPrice) / symbolInfo.Point();
         
         if(profit >= InpTrailingStart)
         {
            newSL = currentPrice + InpTrailingStep * symbolInfo.Point();
            newSL = NormalizeDouble(newSL, symbolInfo.Digits());
            
            if(newSL < currentSL - symbolInfo.Point() || currentSL == 0)
            {
               trade.PositionModify(positionInfo.Ticket(), newSL, positionInfo.TakeProfit());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check spread                                                      |
//+------------------------------------------------------------------+
bool CheckSpread()
{
   symbolInfo.RefreshRates();
   int currentSpread = symbolInfo.Spread();
   
   if(currentSpread > InpMaxSpread)
   {
      Print("Spread too high: ", currentSpread, " > ", InpMaxSpread);
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check trading time                                                |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   int currentHour = dt.hour;
   
   if(InpStartHour < InpEndHour)
   {
      return (currentHour >= InpStartHour && currentHour < InpEndHour);
   }
   else // Overnight session
   {
      return (currentHour >= InpStartHour || currentHour < InpEndHour);
   }
}

//+------------------------------------------------------------------+
