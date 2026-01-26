# Trading Made Simple(r) - MT5 EA System

## Overview

This is a complete MetaTrader 5 implementation of RobinHood's "Trading Made Simple(r)" strategy from ForexFactory. The system includes a fully automated Expert Advisor (EA) and all necessary custom indicators.

**Original Thread:** https://www.forexfactory.com/thread/917569-trading-made-simpler

## Strategy Summary

The Trading Made Simple strategy is based on the work of "Big E" (Eric) and uses a combination of indicators to identify high-probability trade entries with the trend. The key principle is: **always trade with the trend**.

### Core Indicators Used

1. **EMA (Yellow Line)** - 5-period EMA with +2 shift applied to Close
2. **HMA (Hull Moving Average)** - 12-period, showing trend direction via color
   - Lime Green = Uptrend
   - Deep Pink = Downtrend
3. **Heiken Ashi Candles** - Smoothed candlesticks showing trend
   - Blue = Bullish
   - Maroon = Bearish
4. **Synergy APB** - Average Price Bar indicator
   - Dodger Blue = Bullish
   - Red = Bearish
5. **Stochastic (8,3,3)** - Fast stochastic for momentum
6. **Stochastic (14,3,3)** - Slow stochastic for confirmation
7. **RSI 14** - Relative Strength Index for trend confirmation
8. **Purple 50 Line** - Reference level for RSI and Stochastics

### Color Coding Rule
- **Green/Blue Colors** = Always mean "UP"
- **Red/Orange Colors** = Always mean "DOWN"

## Entry Methods

### 1. Crossover Trades

Entry conditions for LONG trades:
1. HMA Line turns Lime Green and crosses above the Yellow EMA
2. Candles change from Red/Maroon to Dodger Blue/Blue
3. Enter after the 1st bar closes above the Yellow EMA (within 3 bars max)
4. Both Stochastics above or crossing above the 50 level
5. RSI above the 50 level

Entry conditions for SHORT trades:
1. HMA Line turns Deep Pink and crosses below the Yellow EMA
2. Candles change from Dodger Blue/Blue to Red/Maroon
3. Enter after the 1st bar closes below the Yellow EMA (within 3 bars max)
4. Both Stochastics below or crossing below the 50 level
5. RSI below the 50 level

### 2. Continuation Trades

These are trades in the direction of an established trend after a brief pullback.

**Long Continuation:**
- Bar turns back to Dodger Blue/Blue after being Red/Maroon
- Close is above the Yellow EMA
- All other indicators confirm the long direction

**Short Continuation:**
- Bar turns back to Red/Maroon after being Dodger Blue/Blue
- Close is below the Yellow EMA
- All other indicators confirm the short direction

## Exit Methods

Multiple exit options are available in the EA:

1. **Candle Color Change** - Exit when candles change to opposite color
2. **HMA/EMA Cross** - Exit when HMA crosses back over EMA
3. **RSI Cross 50** - Exit when RSI crosses the 50 level against your position
4. **Stochastic Cross 50** - Exit when stochastic crosses 50 against your position
5. **Stop Loss Hit** - Automatic exit at stop loss
6. **Take Profit Reached** - Automatic exit at take profit target
7. **Trailing Stop** - Dynamic stop loss that follows price

## Stop Loss Placement

The EA uses the strategy's recommended stop placement:

- **Long Trades:** Stop placed below the low of the 2nd candle back from entry
- **Short Trades:** Stop placed above the high of the 2nd candle back from entry

A configurable buffer is added to prevent premature stop-outs.

## File Structure

```
TradingMadeSimple_MT5/
├── Experts/
│   └── TradingMadeSimple_EA.mq5      # Main Expert Advisor
├── Indicators/
│   └── TMS_Indicators/
│       ├── HMA_TMS.mq5               # Hull Moving Average
│       ├── Synergy_APB_TMS.mq5       # Synergy Average Price Bar
│       ├── Heiken_Ashi_TMS.mq5       # Heiken Ashi Candles
│       ├── Stochastic_Color_TMS.mq5  # Color Stochastic
│       ├── BarClock_TMS.mq5          # Bar Clock Timer
│       └── Magnified_Market_Price_TMS.mq5  # Price Display
└── README.md
```

## Installation

### Step 1: Copy Files

1. Copy `Experts/TradingMadeSimple_EA.mq5` to your MT5 `MQL5/Experts/` folder
2. Copy the entire `Indicators/TMS_Indicators/` folder to your MT5 `MQL5/Indicators/` folder

### Step 2: Compile

1. Open MetaEditor (F4 in MT5)
2. Navigate to each file and compile (F7) or use "Compile All"
3. Ensure no compilation errors

### Step 3: Restart MT5

1. Restart MetaTrader 5 or right-click Navigator and select "Refresh"
2. The EA should appear in Navigator under "Expert Advisors"
3. Indicators will appear under "Indicators > TMS_Indicators"

### Step 4: Attach to Chart

1. Open a chart (recommended: 4H or Daily timeframe)
2. Drag the EA onto the chart
3. Configure settings in the popup dialog
4. Enable "Allow Algo Trading" in MT5 settings

## EA Input Parameters

### Trade Settings
| Parameter | Default | Description |
|-----------|---------|-------------|
| Lot Size | 0.1 | Fixed lot size (0 = use risk-based calculation) |
| Risk Percent | 2.0 | Risk per trade as % of account (if Lot Size = 0) |
| Magic Number | 20240125 | Unique identifier for EA's trades |
| Max Spread | 30 | Maximum allowed spread in points |
| Use Trailing Stop | true | Enable/disable trailing stop |
| Trailing Start | 50 | Points in profit before trailing starts |
| Trailing Step | 20 | Points to trail behind price |

### Entry Methods
| Parameter | Default | Description |
|-----------|---------|-------------|
| Trade Crossovers | true | Enable crossover trade signals |
| Trade Continuation | true | Enable continuation trade signals |
| Max Bars After Cross | 3 | Maximum bars after crossover to enter |
| Require All Confirm | true | Require all indicators to confirm |

### Indicator Settings
| Parameter | Default | Description |
|-----------|---------|-------------|
| EMA Period | 5 | Yellow line EMA period |
| EMA Shift | 2 | EMA shift forward |
| HMA Period | 12 | Hull Moving Average period |
| Stoch1 K/D/Slow | 8/3/3 | Fast stochastic settings |
| Stoch2 K/D/Slow | 14/3/3 | Slow stochastic settings |
| RSI Period | 14 | RSI period |

### Exit Settings
| Parameter | Default | Description |
|-----------|---------|-------------|
| Exit On Color Change | true | Exit when candle colors change |
| Exit On HMA Cross | true | Exit when HMA crosses EMA |
| Exit On RSI Cross | false | Exit when RSI crosses 50 |
| Exit On Stoch Cross | false | Exit when Stochastic crosses 50 |

## Recommended Settings

### For 4-Hour Charts (Recommended)
- Use default settings
- Trade major pairs (EURUSD, GBPUSD, USDJPY)
- Trade during London and New York sessions
- Risk 1-2% per trade

### For Daily Charts
- Increase Trailing Start to 100-150 points
- Consider lower risk (1% per trade) due to larger stops
- Patience required - fewer signals

### For 1-Hour or Lower (Not Recommended)
- Enable Trading Hours filter
- Reduce risk to 0.5-1%
- Expect more whipsaws
- Use Template #2 with trading times

## Important Trading Tips

1. **Wait for bar close** - Never enter or exit before the setup bar closes
2. **Trade with the trend** - All indicators should agree on direction
3. **Enter early** - Best entries are on the 1st-3rd bar after crossover
4. **Avoid large bars** - Don't enter immediately after exceptionally large moves
5. **Use 4H or Daily** - Lower timeframes cause more whipsaws
6. **Filter by session** - Best during London-New York overlap
7. **Continuation trades are safer** - They follow established trends

## Backtesting

1. Open Strategy Tester (Ctrl+R)
2. Select "TradingMadeSimple_EA"
3. Choose symbol and timeframe (4H recommended)
4. Set test period (at least 1 year recommended)
5. Enable "Visual Mode" to see trades on chart
6. Run test and analyze results

## Risk Warning

Trading forex involves substantial risk. This EA is provided for educational purposes. Always:

- Test thoroughly on demo account first
- Never risk more than you can afford to lose
- Past performance doesn't guarantee future results
- Monitor the EA regularly
- Understand the strategy before using

## Troubleshooting

### EA Not Trading
1. Check "Algo Trading" is enabled in MT5
2. Verify spread is within limits
3. Check trading hours filter settings
4. Ensure indicators are compiled correctly

### Indicators Not Showing
1. Recompile all indicator files
2. Restart MT5
3. Check for compilation errors in MetaEditor

### Incorrect Signals
1. Verify indicator settings match strategy
2. Ensure timeframe matches your intentions
3. Check if all confirmations are required

## Credits

- **Original Strategy:** RobinHood (ForexFactory)
- **Inspiration:** Big E (Eric) - Trading Made Simple thread
- **MT5 Implementation:** Created for automated trading

## License

This implementation is provided free for personal use. Please respect the original strategy creator and do not sell or redistribute without permission.

## Version History

- **v1.00** (2024-01-25): Initial MT5 release
  - Complete EA with crossover and continuation trades
  - All custom indicators ported to MT5
  - Full configuration options
  - Trailing stop functionality
  - Multiple exit methods

---

*"If you cannot eventually learn to make money trading the Forex using these templates, then you should probably just give up trading the Forex."* - RobinHood
