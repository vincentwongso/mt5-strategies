# Price Action Trading System EA for MT5

## Overview

This Expert Advisor implements a price action trading system that combines:
- **Candlestick Pattern Recognition** (Engulfing, Pin Bar, Morning/Evening Star, Inside Bar)
- **Support/Resistance Detection** using swing high/low analysis
- **Trend Following** with EMA-based trend filtering
- **Advanced Risk Management** with partial profits and trailing stops

---

## Key Features

### 1. Candlestick Patterns Detected

| Pattern | Description | Signal |
|---------|-------------|--------|
| **Bullish Engulfing** | Current bullish candle completely engulfs previous bearish candle | BUY |
| **Bearish Engulfing** | Current bearish candle completely engulfs previous bullish candle | SELL |
| **Bullish Pin Bar** | Long lower wick (>2x body), small body at top | BUY |
| **Bearish Pin Bar** | Long upper wick (>2x body), small body at bottom | SELL |
| **Morning Star** | 3-candle reversal pattern (bearish → small → bullish) | BUY |
| **Evening Star** | 3-candle reversal pattern (bullish → small → bearish) | SELL |
| **Inside Bar** | Current candle completely inside previous candle | Direction based on close |

### 2. Support/Resistance Detection

The EA automatically identifies:
- **Swing Highs/Lows** using configurable lookback period
- **Valid S/R Zones** based on multiple price touches
- **Zone Width** scaled by ATR for volatility adaptation

### 3. Trade Entry Conditions

For a trade to execute, the following must align:
1. ✅ Valid candlestick pattern detected
2. ✅ Pattern is near support (buys) or resistance (sells)
3. ✅ Trend filter confirms direction (optional)
4. ✅ Within trading hours (optional)
5. ✅ Max open trades not exceeded

### 4. Risk Management

```
Risk per Trade:     0.5% (configurable)
Max Open Trades:    3 (configurable)
Position Sizing:    Automatic based on stop loss distance
```

### 5. Trade Management Logic

```
Entry → Price hits 1.5R profit → Take 33% profit + Move SL to breakeven
                              → Continue trailing SL every 1R
                              → Final TP at configured R:R ratio
```

---

## Installation

1. **Copy Files:**
   - Place `PriceActionEA.mq5` in: `MT5/MQL5/Experts/`

2. **Compile:**
   - Open MetaEditor (F4 in MT5)
   - Open the EA file
   - Press F7 to compile

3. **Attach to Chart:**
   - Open a chart (recommended: M15 timeframe)
   - Drag EA from Navigator to chart
   - Configure settings and enable AutoTrading

---

## Input Parameters

### Risk Management
| Parameter | Default | Description |
|-----------|---------|-------------|
| `RiskPercent` | 0.5 | Risk per trade as % of balance |
| `MaxOpenTrades` | 3 | Maximum simultaneous trades |
| `RiskRewardRatio` | 2.0 | Final take profit R multiple |

### Trade Management
| Parameter | Default | Description |
|-----------|---------|-------------|
| `FirstTPMultiplier` | 1.5 | First TP at this R multiple |
| `PartialClosePercent` | 33.0 | % of position to close at first TP |
| `TrailingStopR` | 1.0 | Move SL every X R multiple |

### Pattern Settings
| Parameter | Default | Description |
|-----------|---------|-------------|
| `UseEngulfing` | true | Enable engulfing pattern detection |
| `UsePinBar` | true | Enable pin bar detection |
| `UseMorningStar` | true | Enable morning/evening star |
| `UseInsideBar` | true | Enable inside bar detection |
| `PinBarRatio` | 2.5 | Minimum wick/body ratio for pin bars |
| `EngulfingMinRatio` | 1.5 | Minimum engulfing body ratio |

### Support/Resistance Settings
| Parameter | Default | Description |
|-----------|---------|-------------|
| `SwingLookback` | 20 | Bars to analyze for S/R |
| `SwingStrength` | 3 | Bars on each side for swing validation |
| `SRZoneATRMultiple` | 0.5 | Zone width as ATR multiple |
| `MinTouchesForSR` | 2 | Minimum touches for valid level |

### Trend Filter
| Parameter | Default | Description |
|-----------|---------|-------------|
| `UseTrendFilter` | true | Enable trend filtering |
| `TrendEMAPeriod` | 50 | Slow EMA for trend |
| `FastEMAPeriod` | 20 | Fast EMA for trend confirmation |

### Time Filter
| Parameter | Default | Description |
|-----------|---------|-------------|
| `UseTimeFilter` | true | Enable trading hours filter |
| `StartHour` | 8 | Trading start hour (server time) |
| `EndHour` | 18 | Trading end hour (server time) |
| `TradeFriday` | true | Allow trading on Friday |

### Trade Quality Filters
| Parameter | Default | Description |
|-----------|---------|-------------|
| `MinimumRRFilter` | 1.5 | Minimum R:R ratio required before entry. The EA calculates actual R:R based on distance to nearest S/R zone. Set to 0 to disable. |
| `MinATRFilter` | 0.0 | Minimum ATR as percentage of current price. Skips trades during low volatility. Set to 0 to disable. |
| `MaxConsecutiveLosses` | 0 | Pause trading after N consecutive losses. Set to 0 to disable. |
| `PauseBarsAfterLosses` | 20 | Number of bars to pause trading after MaxConsecutiveLosses is reached. |

---

## Trading Logic Explained

### Entry Flow

```
OnNewBar()
    │
    ├── Update Support/Resistance Levels
    │
    ├── Check Time Filter ──► Skip if outside hours
    │
    ├── Check Max Trades ──► Skip if at limit
    │
    ├── Get Trend Direction
    │
    ├── Detect Candlestick Pattern
    │       │
    │       ├── Bullish patterns (near support + uptrend/neutral)
    │       │
    │       └── Bearish patterns (near resistance + downtrend/neutral)
    │
    └── Execute Trade if conditions met
```

### Position Management Flow

```
OnEveryTick()
    │
    ├── Calculate current profit in R multiples
    │
    ├── If profit >= 1.5R AND not yet partial closed:
    │       │
    │       ├── Close 33% of position
    │       │
    │       └── Move SL to breakeven (+5 pips buffer)
    │
    └── If partial closed AND profit crosses next R level:
            │
            └── Trail SL to (current R level - 1) * risk
```

### Stop Loss Placement

- **Bullish trades:** Below the signal candle low + small buffer
- **Bearish trades:** Above the signal candle high + small buffer
- **Multi-candle patterns:** Uses the extreme of all pattern candles

---

## Recommended Settings by Market

### Forex Majors (EURUSD, GBPUSD, etc.)
```
RiskPercent: 0.5%
SwingLookback: 20
SwingStrength: 3
TrendEMAPeriod: 50
```

### Forex Crosses
```
RiskPercent: 0.3%
SwingLookback: 25
SwingStrength: 4
TrendEMAPeriod: 50
```

### Indices (US30, NAS100)
```
RiskPercent: 0.5%
SwingLookback: 15
SwingStrength: 3
TrendEMAPeriod: 50
```

### Gold (XAUUSD)
```
RiskPercent: 0.3%
SwingLookback: 20
SwingStrength: 3
TrendEMAPeriod: 50
```

---

## Backtesting Guide

### Recommended Settings
- **Timeframe:** M15
- **Model:** Every tick based on real ticks
- **Period:** At least 6-12 months
- **Starting Balance:** $10,000 (or equivalent)
- **Leverage:** 1:100 or 1:500

### Optimization Tips

1. **Start with defaults** - Test baseline performance first
2. **Optimize in stages:**
   - First: Pattern settings
   - Then: S/R settings
   - Finally: Risk parameters
3. **Use walk-forward optimization** to avoid overfitting
4. **Test on multiple pairs** to ensure robustness

---

## Instrument-Specific Settings

The EA includes optimized settings files for different instruments based on backtest analysis:

| File | Instrument | Key Optimizations |
|------|------------|-------------------|
| `PriceActionEA_Default.set` | General | Balanced defaults for any instrument |
| `PriceActionEA_XAUUSD.set` | Gold | Best performer - Inside Bar enabled, R:R filter 1.5 |
| `PriceActionEA_XAGUSD.set` | Silver | Inside Bar disabled, moderate filters |
| `PriceActionEA_EURUSD.set` | EURUSD | Strictest settings - longer EMA periods, R:R filter 2.0, Inside Bar disabled |

**To use:** In MT5 Strategy Tester or when attaching to chart, click "Load" and select the appropriate `.set` file for your instrument.

---

## Important Notes

### Risk Warning
⚠️ **Trading forex and CFDs involves substantial risk of loss. Past performance is not indicative of future results. Only trade with money you can afford to lose.**

### Best Practices

1. **Always backtest** before live trading
2. **Start on demo account** for at least 1 month
3. **Monitor trades** during the first week of live trading
4. **Keep risk low** (0.5% or less per trade)
5. **Don't overtrade** - let the EA wait for high-probability setups

### Known Limitations

- Pattern detection relies on completed candles
- S/R levels update each new bar (not real-time)
- No news filter included (consider avoiding major news)
- Requires stable VPS for 24/5 operation

---

## Troubleshooting

### EA Not Trading?
1. Check if AutoTrading is enabled (green button)
2. Verify sufficient margin available
3. Check Expert tab for error messages
4. Ensure timeframe matches expected (M15)

### Trades Not Managing Properly?
1. Verify MagicNumber matches existing trades
2. Check Expert tab for modification errors
3. Ensure broker allows position modification

### High Slippage?
1. Increase `Slippage` parameter
2. Consider using limit orders (requires code modification)
3. Trade during liquid hours

---

## Version History

- **v1.00** - Initial release with core functionality
  - Candlestick pattern detection
  - S/R level identification
  - Partial profit taking
  - Trailing stop management

---

## Support

For questions, issues, or feature requests, please:
1. Check this documentation first
2. Review the Expert tab for error messages
3. Test on demo before reporting issues

---

*This EA is provided for educational purposes. Always conduct your own testing and due diligence before live trading.*
