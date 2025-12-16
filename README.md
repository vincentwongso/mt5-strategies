# Mean Reversion EA for MetaTrader 5

A professional Expert Advisor implementing a Mean Reversion strategy with Dynamic Regime-Based Risk Management for ES (E-mini S&P 500) and NQ (E-mini Nasdaq 100) futures.

## Strategy Overview

This EA implements a classic mean reversion strategy using Bollinger Bands and RSI, with adaptive risk management based on market regime (trending vs. consolidating) detected via ADX.

### Key Features

- **Mean Reversion Entry**: Trades when price closes outside Bollinger Bands with RSI confirmation
- **Dynamic Risk Management**: Stop loss distance adapts based on market regime (ADX)
- **Chandelier Exit**: Trailing stop that follows price action
- **Multiple Trade Filters**: Spread, volatility, news, cooldown, and daily loss limit
- **Position Sizing**: Risk-based position sizing (1% per trade default)

## Installation

1. Copy the `MQL5` folder contents to your MetaTrader 5 data folder:
   - `MQL5/Experts/MeanReversionEA/` → `[MT5 Data Folder]/MQL5/Experts/MeanReversionEA/`
   - `MQL5/Include/MeanReversionEA/` → `[MT5 Data Folder]/MQL5/Include/MeanReversionEA/`

2. Open MetaEditor and compile `MeanReversionEA.mq5`

3. Attach the EA to an ES or NQ chart (M15 or H1 recommended)

## Configuration

### Indicator Settings

| Parameter | Default | Description |
|-----------|---------|-------------|
| ADX Period | 14 | Period for ADX calculation |
| ATR Period | 14 | Period for ATR calculation |
| BB Period | 20 | Bollinger Bands period |
| BB Deviation | 2.0 | Bollinger Bands standard deviation |
| RSI Period | 14 | RSI period |
| RSI Oversold | 30 | RSI oversold threshold |
| RSI Overbought | 70 | RSI overbought threshold |
| ADX Threshold | 25 | Threshold for trend detection |

### Risk Management

| Parameter | Default | Description |
|-----------|---------|-------------|
| Risk Per Trade | 1.0% | Percentage of equity risked per trade |
| Daily Loss Limit | 3.0% | Stop trading if daily loss exceeds this |
| ATR Multiplier (Trend) | 2.5 | Stop distance multiplier in trending markets |
| ATR Multiplier (Range) | 1.5 | Stop distance multiplier in ranging markets |

### Trade Filters

| Parameter | Default | Description |
|-----------|---------|-------------|
| Spread Multiplier | 2.0 | Skip trade if spread > 2x average |
| Min ATR ES | 5.0 | Minimum ATR for ES trades |
| Min ATR NQ | 20.0 | Minimum ATR for NQ trades |
| Cooldown Bars | 3 | Bars to wait after a losing trade |
| News Buffer | 5 | Minutes to avoid around news events |
| Max Slippage | 3 | Maximum acceptable slippage in ticks |

### Trading Hours

| Parameter | Default | Description |
|-----------|---------|-------------|
| Trading Start Hour | 9 | Start hour (Eastern Time) |
| Trading Start Minute | 30 | Start minute |
| Trading End Hour | 16 | End hour (Eastern Time) |
| Trading End Minute | 0 | End minute |
| Broker GMT Offset | -5 | Your broker's GMT offset |

## Entry Rules

### Long Entry (All conditions must be true)
1. Price closes below Lower Bollinger Band
2. RSI < 30 (Oversold)
3. Entry bar closes bullish (Close > Open)

### Short Entry (All conditions must be true)
1. Price closes above Upper Bollinger Band
2. RSI > 70 (Overbought)
3. Entry bar closes bearish (Close < Open)

## Exit Rules

1. **Take Profit**: Middle Bollinger Band (20 SMA)
2. **Stop Loss**: Chandelier Exit (trailing stop)
   - Trending: 2.5 × ATR below highest high (longs) / above lowest low (shorts)
   - Ranging: 1.5 × ATR below highest high (longs) / above lowest low (shorts)

## File Structure

```
MQL5/
├── Experts/
│   └── MeanReversionEA/
│       └── MeanReversionEA.mq5      # Main EA file
├── Include/
│   └── MeanReversionEA/
│       ├── Indicators.mqh            # Indicator calculations
│       ├── RiskManager.mqh           # Position sizing & risk
│       ├── TradeFilters.mqh          # All trade filters
│       ├── TradeExecutor.mqh         # Order execution
│       ├── TrailingStop.mqh          # Chandelier exit logic
│       └── Logger.mqh                # Logging utilities
└── Scripts/
    └── MeanReversionEA/
        └── TestIndicators.mq5        # Indicator testing script
```

## Backtesting

1. Download historical data for ES/NQ (minimum 2 years recommended)
2. Open Strategy Tester in MT5
3. Select `MeanReversionEA`
4. Choose symbol (ES or NQ)
5. Set timeframe (M15 or H1)
6. Enable "Every tick based on real ticks" for accurate results
7. Run backtest

### Recommended Test Settings
- Period: 2+ years
- Modeling: Every tick based on real ticks
- Initial deposit: $10,000+
- Leverage: As per your broker

## Risk Warning

⚠️ **Trading futures involves substantial risk of loss and is not suitable for all investors.**

- Past performance is not indicative of future results
- Only trade with capital you can afford to lose
- This EA is provided for educational purposes
- Always test thoroughly on demo accounts before live trading

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2024-12-16 | Initial release |

## License

This project is provided as-is for educational purposes. Use at your own risk.

## Support

For issues or questions, please open an issue in the repository.