# SimpleSystem TF15 - Expert Advisor for MetaTrader 5

## Overview

This EA implements the "Another Simple System - Time Frame 15" strategy from ForexFactory, created by the community. It's a price action-based trading system that uses TDI (Traders Dynamic Index) for trade confirmation, designed specifically for the 15-minute timeframe.

**Original Strategy Thread:** https://www.forexfactory.com/thread/345586-another-simple-system-time-frame-15

## Strategy Concept

The strategy is based on the principle of trading **away from the 200 EMA** during high-momentum sessions (London/New York), using TDI for confirmation. The 200 EMA and 800 EMA act as dynamic support/resistance zones, while the 10 EMA serves as the entry filter.

### Key Principles

1. **Trade with the trend** - Use the 800 EMA as the major trend filter
2. **Trade during high momentum** - Focus on London and New York sessions
3. **Confirmation-based entries** - Wait for TDI Green to cross Yellow
4. **Defined risk** - Fixed 20-pip stop loss with breakeven management

## Entry Rules

### BUY Signal
1. Price closes **above** the 10 EMA
2. TDI Green line crosses **above** Yellow line
3. Price is at least 15 pips **away from** the 200 EMA
4. Price is **above** the 800 EMA (optional filter)
5. Currently within London or New York trading session

### SELL Signal
1. Price closes **below** the 10 EMA
2. TDI Green line crosses **below** Yellow line
3. Price is at least 15 pips **away from** the 200 EMA
4. Price is **below** the 800 EMA (optional filter)
5. Currently within London or New York trading session

## Exit Rules

- **Stop Loss:** 20 pips (default)
- **Take Profit:** 40 pips (default) or TDI cross-back exit
- **Breakeven:** Move SL to breakeven +1 pip after 12 pips profit
- **TDI Exit:** Close when Green crosses back over Red (optional)

## Indicators Used

| Indicator | Purpose | MT5 File |
|-----------|---------|----------|
| 10 EMA | Entry filter | Built-in |
| 200 EMA | Support/Resistance (1HR 50 equivalent) | Built-in |
| 800 EMA | Trend filter (4HR 50 equivalent) | Built-in |
| TDI | Trade confirmation | TDI_RedGreen.mq5 |
| Round Numbers | Visual S/R zones | RoundNumbers.mq5 |
| Trading Times | Session markers | TradingTimes.mq5 |

### TDI Lines Explained

- **Green Line (RSI Price Line):** Immediate price action direction
- **Red Line (Trade Signal Line):** Smoothed signal line
- **Yellow Line (Market Base Line):** Market trend direction
- **Blue Lines (Volatility Bands):** Market volatility

## Installation

### Step 1: Copy Files

1. Copy **Experts/SimpleSystem_TF15_EA.mq5** to:
   ```
   [MT5 Data Folder]\MQL5\Experts\
   ```

2. Copy all files from **Indicators/** to:
   ```
   [MT5 Data Folder]\MQL5\Indicators\
   ```

3. Copy **Templates/SimpleSystem_TF15.tpl** to:
   ```
   [MT5 Data Folder]\MQL5\Profiles\Templates\
   ```

### Step 2: Compile

1. Open MetaEditor (F4 in MT5)
2. Navigate to each `.mq5` file
3. Press F7 to compile
4. Ensure no errors

### Step 3: Apply to Chart

1. Open EURUSD or GBPUSD M15 chart
2. Right-click chart → Templates → SimpleSystem_TF15
3. Drag SimpleSystem_TF15_EA onto the chart
4. Configure settings and enable Auto Trading

## Input Parameters

### Strategy Settings
| Parameter | Default | Description |
|-----------|---------|-------------|
| EMA_Fast | 10 | Fast EMA for entry filter |
| EMA_200 | 200 | Medium-term S/R level |
| EMA_800 | 800 | Long-term trend filter |
| MinDistanceEMA | 15 | Min distance from 200 EMA (pips) |
| UseEMA800Filter | true | Enable 800 EMA trend filter |

### TDI Settings
| Parameter | Default | Description |
|-----------|---------|-------------|
| TDI_RSI_Period | 13 | RSI calculation period |
| TDI_Volatility_Band | 34 | Volatility band period |
| TDI_RSI_Price_Line | 2 | Green line smoothing |
| TDI_Trade_Signal | 7 | Red line period |

### Trading Session
| Parameter | Default | Description |
|-----------|---------|-------------|
| UseTradingHours | true | Enable session filter |
| LondonOpenHour | 8 | London open (server time) |
| LondonCloseHour | 17 | London close (server time) |
| NYOpenHour | 13 | NY open (server time) |
| NYCloseHour | 22 | NY close (server time) |
| TradeOnlyOverlap | false | Trade only London/NY overlap |

### Money Management
| Parameter | Default | Description |
|-----------|---------|-------------|
| RiskPercent | 0.5 | Risk per trade (%) |
| StopLossPips | 20 | Stop loss in pips |
| TakeProfitPips | 40 | Take profit in pips (0 = no TP) |
| UseBreakeven | true | Enable breakeven |
| BreakevenPips | 12 | Move to BE after X pips |
| BreakevenPlus | 1 | Additional pips above BE |
| UseTrailingStop | false | Enable trailing stop |

### Exit Options
| Parameter | Default | Description |
|-----------|---------|-------------|
| ExitOnTDICross | false | Exit when TDI crosses back |
| CloseAtSessionEnd | false | Close trades at session end |

## Recommended Settings

### Conservative
- Risk: 0.5%
- SL: 20 pips
- TP: 20 pips (1:1)
- BE: 12 pips

### Moderate (Default)
- Risk: 0.5%
- SL: 20 pips
- TP: 40 pips (1:2)
- BE: 12 pips

### Aggressive
- Risk: 1.0%
- SL: 20 pips
- TP: 60 pips (1:3) or TDI exit
- BE: 12 pips
- Trailing: Enabled

## Best Practices

1. **Demo First:** Always test on demo account for at least 1 month
2. **Session Awareness:** Best results during London-NY overlap (13:00-17:00 server time)
3. **News Avoidance:** Disable trading during major news releases
4. **Pair Selection:** Works best on major pairs (EURUSD, GBPUSD)
5. **Server Time:** Adjust session times based on your broker's server time

## Troubleshooting

### EA Not Trading
1. Check if Auto Trading is enabled (Ctrl+E)
2. Verify it's within trading hours
3. Check if max trades limit reached
4. Review Expert tab for error messages

### Indicators Not Loading
1. Ensure all indicators are compiled
2. Check MQL5 Journal for errors
3. Verify correct installation paths

### Wrong Session Times
1. Check broker's server time (displayed in MT5)
2. Adjust LondonOpenHour/NYOpenHour accordingly
3. Most brokers use GMT+2 or GMT+3

## File Structure

```
SimpleSystem_TF15/
├── Experts/
│   └── SimpleSystem_TF15_EA.mq5    # Main EA
├── Indicators/
│   ├── TDI_RedGreen.mq5            # TDI indicator
│   ├── RoundNumbers.mq5            # Round number levels
│   └── TradingTimes.mq5            # Session markers
├── Templates/
│   └── SimpleSystem_TF15.tpl       # Chart template
└── Documentation/
    └── README.md                    # This file
```

## Risk Disclaimer

Trading forex involves substantial risk of loss. This EA is provided for educational purposes. Past performance does not guarantee future results. Always use proper risk management and never risk more than you can afford to lose.

## Credits

- Original Strategy: ForexFactory Community (Thread #345586)
- TDI Indicator: Dean Malone (CompassFX)
- MT5 Conversion & EA Development: 2025

## Version History

- **1.00** - Initial release with full strategy implementation
