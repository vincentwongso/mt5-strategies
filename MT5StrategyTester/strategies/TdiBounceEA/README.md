# TDI Bounce Trading System EA (MetaTrader 5)

## Overview

This Expert Advisor (EA) is based on the "Another Simple System - Time Frame 15" trading strategy from ForexFactory. The system uses the Traders Dynamic Index (TDI) indicator combined with multiple Exponential Moving Averages (EMAs) to identify high-probability bounce trades during the London and New York sessions.

## Files Included

| File | Description |
|------|-------------|
| `TDI_Bounce_EA.mq5` | Main Expert Advisor |
| `TDI_Indicator.mq5` | TDI Custom Indicator for visual confirmation |
| `README.md` | This documentation file |

## Strategy Rules

### Core Concept
Trade bounces AWAY from the 200 EMA using TDI confirmation. The strategy focuses on momentum continuation when price is trending away from the long-term average.

### Instruments & Timeframe
- **Pairs**: EURUSD and GBPUSD only
- **Timeframe**: 15-minute charts ONLY
- **Sessions**: London and New York sessions

### Indicators Used
1. **200 EMA** - Main trend filter (equivalent to 50 EMA on 1H chart)
2. **800 EMA** - Long-term trend reference (equivalent to 50 EMA on 4H chart)
3. **10 EMA** - Entry confirmation
4. **TDI (Traders Dynamic Index)** - Signal confirmation

### TDI Settings (Dean Malone's Original)
| Component | Setting | Color |
|-----------|---------|-------|
| RSI Period | 13 | - |
| Green Line (Price) | SMA(2) of RSI | Lime |
| Red Line (Signal) | SMA(7) of Green Line | Red |
| Yellow Line (Base) | SMA(34) of RSI | Yellow |
| Volatility Bands | BB(34, 1.618) on RSI | Blue |

### Entry Rules

#### BUY Setup
1. ✅ Price is ABOVE the 200 EMA (trading away from it)
2. ✅ Price closes ABOVE the 10 EMA
3. ✅ TDI Green line crosses ABOVE Yellow line
4. ✅ Green line is above Red line
5. ✅ Yellow line slope is pointing upward

#### SELL Setup
1. ✅ Price is BELOW the 200 EMA (trading away from it)
2. ✅ Price closes BELOW the 10 EMA
3. ✅ TDI Green line crosses BELOW Yellow line
4. ✅ Red line is above Green line
5. ✅ Yellow line slope is pointing downward

### Money Management
- **Stop Loss**: 20 pips (fixed)
- **Take Profit**: Options:
  - 1:1 Risk/Reward (20 pips) - Set TakeProfitPips = 20
  - TDI Exit (let it run until TDI crosses back) - Set TakeProfitPips = 0
- **Breakeven**: Move SL to BE after 12 pips in profit
- **Risk**: Never risk more than 2% per trade

---

## Installation (MetaTrader 5)

### Step 1: Copy Files
1. Open MetaTrader 5
2. Go to **File → Open Data Folder**
3. Navigate to **MQL5 → Experts**
4. Copy `TDI_Bounce_EA.mq5` into this folder
5. Navigate to **MQL5 → Indicators**
6. Copy `TDI_Indicator.mq5` into this folder

### Step 2: Compile
1. In MT5, open **MetaEditor** (press F4)
2. In the Navigator panel, find and open `TDI_Bounce_EA.mq5`
3. Press **F7** to compile (or click Compile button)
4. Ensure "0 errors" appears in the output
5. Repeat for `TDI_Indicator.mq5`

### Step 3: Attach to Chart
1. Open a **15-minute chart** (EURUSD or GBPUSD)
2. Add the TDI Indicator for visual reference:
   - Go to **Insert → Indicators → Custom → TDI_Indicator**
   - Or drag from Navigator window
3. Add the EA:
   - Go to **Navigator → Expert Advisors**
   - Double-click `TDI_Bounce_EA` or drag onto chart
4. Enable Auto Trading:
   - Click the **Algo Trading** button in toolbar
   - Ensure it shows green (enabled)

### Step 4: Configure Settings
In the EA properties dialog:
1. Check "Allow Algo Trading"
2. Adjust input parameters as needed
3. Click OK

---

## EA Input Parameters

### Trading Settings
| Parameter | Default | Description |
|-----------|---------|-------------|
| TradeEURUSD | true | Enable EURUSD trading |
| TradeGBPUSD | true | Enable GBPUSD trading |
| RiskPercent | 2.0 | Risk per trade (% of balance) |
| StopLossPips | 20.0 | Stop loss in pips |
| TakeProfitPips | 20.0 | Take profit in pips (0 = use TDI exit) |
| BreakevenPips | 12.0 | Move SL to BE after X pips profit |
| MagicNumber | 123456 | Unique identifier for EA trades |

### Session Settings
| Parameter | Default | Description |
|-----------|---------|-------------|
| TradeLondonSession | true | Trade during London session |
| TradeNewYorkSession | true | Trade during NY session |
| LondonStartHour | 8 | London session start (server time) |
| LondonEndHour | 12 | London session end |
| NewYorkStartHour | 13 | NY session start (server time) |
| NewYorkEndHour | 17 | NY session end |

### EMA Settings
| Parameter | Default | Description |
|-----------|---------|-------------|
| EMA_10_Period | 10 | Fast EMA for entry confirmation |
| EMA_200_Period | 200 | Main trend EMA |
| EMA_800_Period | 800 | Long-term trend EMA |
| MinDistanceFromEMA | 5 | Minimum pips away from 200 EMA |

### TDI Settings
| Parameter | Default | Description |
|-----------|---------|-------------|
| RSI_Period | 13 | RSI calculation period |
| RSI_Price | PRICE_CLOSE | RSI applied price |
| PriceLine_Period | 2 | Green line (Price) MA period |
| PriceLine_Type | MODE_SMA | Green line MA type |
| SignalLine_Period | 7 | Red line (Signal) MA period |
| SignalLine_Type | MODE_SMA | Red line MA type |
| BaseLine_Period | 34 | Yellow line (Base) MA period |
| BaseLine_Type | MODE_SMA | Yellow line MA type |

### Alert Settings
| Parameter | Default | Description |
|-----------|---------|-------------|
| EnableAlerts | true | Enable popup alerts |
| EnablePushNotification | false | Enable mobile push alerts |
| EnableEmailAlert | false | Enable email alerts |

---

## Session Time Adjustment

⚠️ **IMPORTANT**: Session hours are in SERVER TIME. Adjust based on your broker:

| Broker Server Time | London Session | NY Session |
|-------------------|----------------|------------|
| GMT+0 (UTC) | 8:00 - 12:00 | 13:00 - 17:00 |
| GMT+2 (EET) | 10:00 - 14:00 | 15:00 - 19:00 |
| GMT+3 (MSK) | 11:00 - 15:00 | 16:00 - 20:00 |

**To check your broker's server time:**
1. Look at the time displayed in MT5's Market Watch window
2. Compare to your local time to determine offset

---

## TDI Interpretation Guide

### Line Meanings
| Line | Color | Meaning |
|------|-------|---------|
| Price Line | Green | Short-term momentum (fast) |
| Signal Line | Red | Medium-term momentum filter |
| Base Line | Yellow | Overall market sentiment/trend |
| Volatility Bands | Blue | Market volatility range |

### Key Levels
| Level | Meaning |
|-------|---------|
| 68 | Overbought zone |
| 50 | Neutral / Equilibrium |
| 32 | Oversold zone |

### Signal Strength Guide
| Condition | Signal Strength |
|-----------|----------------|
| Green > Yellow, Yellow rising, Price > 200 EMA | Strong Buy |
| Green < Yellow, Yellow falling, Price < 200 EMA | Strong Sell |
| Green and Yellow tangled | Neutral / No Trade |

### TDI Cross Signals
- **Bullish**: Green crosses ABOVE Yellow (buy signal)
- **Bearish**: Green crosses BELOW Yellow (sell signal)

---

## Best Practices

### Do's ✅
1. **Demo test first** - Run for 1-2 weeks minimum before live
2. **Focus on one setup** - Master the basic entry before variations
3. **Be patient** - Wait for proper setups to develop
4. **Check spreads** - Ensure reasonable spread during trading hours
5. **Verify server time** - Adjust session hours for your broker

### Don'ts ❌
1. **Don't trade during high-impact news** - Avoid NFP, FOMC, etc.
2. **Don't override the system** - Trust the rules
3. **Don't increase risk** - Keep at 2% or less per trade
4. **Don't trade all pairs** - Stick to EURUSD and GBPUSD only
5. **Don't use on other timeframes** - 15-minute only

---

## Troubleshooting

### EA Not Trading
1. Check if Algo Trading is enabled (green button)
2. Verify you're on 15-minute timeframe
3. Check if current time is within trading sessions
4. Verify symbol is EURUSD or GBPUSD
5. Check if there's already an open position

### Compilation Errors
1. Ensure MT5 is updated to latest version
2. Check file is in correct folder (MQL5/Experts or MQL5/Indicators)
3. Verify no syntax errors in code

### Wrong Session Times
1. Identify your broker's server time zone
2. Adjust LondonStartHour, LondonEndHour, NewYorkStartHour, NewYorkEndHour accordingly

---

## Backtesting

### Strategy Tester Settings
1. Go to **View → Strategy Tester**
2. Select `TDI_Bounce_EA`
3. Symbol: EURUSD or GBPUSD
4. Period: M15
5. Model: Every tick based on real ticks (recommended)
6. Date range: At least 1 year of data
7. Deposit: Your typical account size
8. Leverage: Your broker's leverage

### Optimization Tips
- Test different StopLossPips (15-25 range)
- Test different BreakevenPips (10-15 range)
- Test session time variations
- Keep RiskPercent fixed at 2% for realistic results

---

## Risk Warning

⚠️ **IMPORTANT DISCLAIMER**

- Past performance is NOT indicative of future results
- This EA may generate losses
- Only trade with money you can afford to lose
- Forex trading involves substantial risk
- Backtest and demo test thoroughly before live trading
- No guarantee of profits is made or implied

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.00 | 2025 | Initial release for MT5 |

---

## Credits

- Original strategy: ForexFactory thread "Another Simple System - Time Frame 15"
- TDI Indicator: Based on Dean Malone's Traders Dynamic Index
- EA Development: Built for MetaTrader 5 platform

---

## Support

For questions or issues:
1. Verify installation steps were followed correctly
2. Check the troubleshooting section
3. Review MT5 Experts log for error messages
4. Ensure all input parameters are valid
