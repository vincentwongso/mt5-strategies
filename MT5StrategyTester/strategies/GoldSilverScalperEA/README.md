# GoldSilverScalper M15 - Expert Advisor

## Overview

M15 EMA trend-following scalper designed for Gold (XAUUSD) and Silver (XAGUSD) during NY session. Uses triple EMA alignment (20/50/200) for trend identification with ATR-based position sizing and comprehensive exit management.

## Key Features

- **Triple EMA trend filter** (20/50/200 stacking)
- **ATR-based dynamic SL/TP** (adapts to volatility)
- **News filter** using MT5 economic calendar (avoids high-impact USD events)
- **Session filter** (NY Open to Lunch)
- **Breakeven + trailing stop** management
- **2-candle reversal exit** logic
- **Daily drawdown protection** (auto-halt at limit)
- **Position limits** per symbol and total

---

## Installation

1. Copy `GoldSilverScalper_M15.mq5` to your MT5 `MQL5/Experts/` folder
2. Restart MT5 or refresh the Navigator panel
3. Attach to XAUUSD or XAGUSD M15 chart
4. Configure inputs and enable AutoTrading

### File Location
```
MT5 Terminal Directory/
└── MQL5/
    └── Experts/
        └── GoldSilverScalper_M15.mq5
```

---

## Configuration Guide

### Risk Management (Start Conservative)

| Parameter | Default | Conservative | Aggressive |
|-----------|---------|--------------|------------|
| InpRiskPercent | 0.25% | 0.15% | 0.50% |
| InpMaxDailyDrawdown | 3.0% | 2.0% | 5.0% |
| InpMaxTotalPositions | 5 | 3 | 7 |
| InpMaxPositionsSymbol | 3 | 2 | 4 |

### Trade Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| InpRiskRewardRatio | 1.5 | Target R:R (1:1.5) |
| InpATRMultiplierSL | 1.5 | SL distance = ATR × this value |
| InpATRPeriod | 14 | ATR calculation period |
| InpMinATRPeriod | 20 | Period for average ATR filter |
| InpMinATRMultiplier | 0.7 | Min ATR threshold (filters low volatility) |

### Session Settings (UTC)

| Parameter | Default | Description |
|-----------|---------|-------------|
| InpSessionStartHour | 14 | Session start (14:30 UTC = NY Open) |
| InpSessionStartMin | 30 | |
| InpSessionEndHour | 18 | Session end (18:00 UTC = NY Lunch) |
| InpSessionEndMin | 0 | |
| InpNoEntryBeforeEnd | 30 | No new trades 30 min before session end |

### News Filter

| Parameter | Default | Description |
|-----------|---------|-------------|
| InpUseNewsFilter | true | Enable/disable news avoidance |
| InpNewsMinutesBefore | 15 | Minutes before news to avoid |
| InpNewsMinutesAfter | 15 | Minutes after news to avoid |
| InpNewsCountries | "USD" | Currencies to monitor (comma-separated) |

### Exit Management

| Parameter | Default | Description |
|-----------|---------|-------------|
| InpBreakevenTrigger | 1.0 | Move to BE at X × risk in profit |
| InpTrailingDistance | 1.0 | Trail by X × initial risk |
| InpUseReversalExit | true | Enable 2-candle reversal exit |
| InpUsePartialClose | false | Enable partial close at 1R |
| InpPartialClosePercent | 50.0 | % to close at partial |

### Price Action Patterns

| Parameter | Default | Description |
|-----------|---------|-------------|
| InpUsePinBar | true | Enable pin bar entries |
| InpPinBarWickRatio | 2.0 | Min wick-to-body ratio |
| InpUseEngulfing | true | Enable engulfing entries |
| InpEngulfingMinSize | 0.5 | Min engulfing body size (× ATR) |

---

## Backtesting Recommendations

### Strategy Tester Settings

- **Mode**: Every tick based on real ticks (most accurate for scalping)
- **Period**: M15
- **Symbol**: XAUUSD or XAGUSD
- **Date range**: Minimum 1 year, ideally 2-3 years
- **Initial deposit**: $10,000 (matches your account size ratio)
- **Leverage**: 1:100

### Optimization Priority (in order)

1. **ATR Multiplier for SL** (`InpATRMultiplierSL`)
   - Range: 1.0 to 2.5, Step: 0.25
   - This has the biggest impact on win rate vs R:R balance

2. **ATR Period** (`InpATRPeriod`)
   - Range: 10 to 20, Step: 2
   - Affects SL/TP responsiveness to recent volatility

3. **Risk:Reward Ratio** (`InpRiskRewardRatio`)
   - Range: 1.2 to 2.0, Step: 0.1
   - Balance between win rate and profit factor

4. **Min ATR Filter** (`InpMinATRMultiplier`)
   - Range: 0.5 to 1.0, Step: 0.1
   - Filters low-volatility chop

5. **Breakeven Trigger** (`InpBreakevenTrigger`)
   - Range: 0.8 to 1.5, Step: 0.1
   - Earlier BE = more protection, later = more room to breathe

### Optimization Sets to Test

**Set A - Tighter Stops:**
```
InpATRMultiplierSL = 1.2
InpRiskRewardRatio = 1.8
InpMinATRMultiplier = 0.8
```

**Set B - Standard (Default):**
```
InpATRMultiplierSL = 1.5
InpRiskRewardRatio = 1.5
InpMinATRMultiplier = 0.7
```

**Set C - Wider Stops:**
```
InpATRMultiplierSL = 2.0
InpRiskRewardRatio = 1.3
InpMinATRMultiplier = 0.6
```

---

## Understanding the Signals

### Entry Logic Flow

```
1. Check: Within NY Session? 
   ↓ YES
2. Check: Near High-Impact News?
   ↓ NO
3. Check: Can Open Position (limits)?
   ↓ YES
4. Check: EMA Alignment (trend)?
   ↓ BULLISH or BEARISH
5. Check: ATR Above Minimum?
   ↓ YES
6. Check: Entry Signal?
   - EMA Touch (primary)
   - Pin Bar at EMA (secondary)
   - Engulfing at EMA (secondary)
   ↓ SIGNAL FOUND
7. Execute Trade
```

### Trend Identification

| Condition | Interpretation |
|-----------|----------------|
| Price > 20 > 50 > 200 | Strong Uptrend → Look for Buys |
| Price < 20 < 50 < 200 | Strong Downtrend → Look for Sells |
| Price between EMAs | Consolidation → No Trade |
| 20/50 cross but 200 not aligned | Early Warning → Defensive mode |

### Exit Priority

1. **Reversal Exit** (if enabled): 2 consecutive candles close on wrong side of 20 EMA
2. **Take Profit**: Automatic at target
3. **Trailing Stop**: Active after breakeven triggered
4. **Stop Loss**: Last resort protection

---

## Troubleshooting

### News Filter Not Working

The EA uses MT5's built-in economic calendar. Ensure:
- Calendar is accessible (check Tools > Options > Expert Advisors)
- Your broker provides calendar data
- Internet connection is stable

If news filter fails, the EA will print a warning but continue trading.

### No Trades Executing

Check these common issues:
1. **Session time**: Verify your broker's server time vs UTC offset
2. **EMA alignment**: May need clearer trends - wait for proper stacking
3. **ATR filter**: Might be filtering during low volatility
4. **Position limits**: May have max positions reached
5. **Daily drawdown**: Check if limit was hit earlier

### High Slippage

- Increase `InpSlippage` if orders frequently fail
- Avoid trading during extreme volatility (first 5 min of news)
- Check broker's typical spread during your session

---

## Risk Warnings

- **Demo test extensively** before live trading
- **Start with lower risk** (0.15%) until you trust the system
- Gold and Silver can have significant spread spikes during news
- Past backtesting results don't guarantee future performance
- The news filter relies on MT5 calendar accuracy

---

## Version History

- **v1.00** - Initial release with full feature set

---

## Support

This EA was built based on documented trading rules. For modifications or issues, review the source code comments which explain each function's purpose.
