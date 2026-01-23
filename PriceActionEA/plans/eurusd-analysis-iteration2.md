# EURUSD Backtest Analysis - Iteration 2

## Executive Summary

After implementing the previous recommendations, the EURUSD backtest results have **deteriorated further**:

| Metric | Previous | Current | Change |
|--------|----------|---------|--------|
| Net Profit | -$10,363 | -$11,447 | **-10.4%** |
| Profit Factor | 0.62 | 0.46 | **-25.8%** |
| Win Rate | 56.39% | 41.56% | **-26.3%** |
| Total Trades | 133 | 77 | -42% |
| Max Consec Losses | 13 | 15 | **+15%** |

The strategy is now in a worse state than before the optimizations.

---

## Critical Issues Identified

### Issue 1: MinimumRRFilter is Counterproductive

**Setting:** `MinimumRRFilter=2.0`

**Problem:** This filter is rejecting trades based on distance to S/R zones, but:
- The S/R detection uses only 20-bar lookback - too short to find meaningful levels
- When no S/R is found, it falls back to using the default R:R ratio, making the filter useless
- Good trade setups near minor S/R zones are being rejected

**Evidence:** Trade count dropped from 133 to 77 while performance got worse. Fewer trades did not mean better trades.

**Recommendation:** 
- Set `MinimumRRFilter=0` to disable, OR
- Set `MinimumRRFilter=1.0` for a much softer filter

### Issue 2: Extremely Fast Stop-Outs

Many trades are stopped out within seconds:

```
2025.11.05 11:30:00 → 11:30:13 = 13 seconds to SL
2026.01.06 11:00:00 → 11:01:30 = 90 seconds to SL  
2026.01.15 11:15:00 → 11:15:42 = 42 seconds to SL
```

**Root Causes:**
1. **Stop losses placed at signal candle extremes are too tight**
2. **Entry is at market price, not limit order at better level**
3. **Pattern detection is firing on noise, not strong reversals**

**Recommendation:**
- Increase ATR buffer from 0.1 to 0.3 for stop loss placement
- Consider using signal candle midpoint + ATR buffer instead of extreme
- Add minimum candle body size filter

### Issue 3: Bearish Bias in Wrong Market Conditions

**EURUSD context:** Oct 2025 - Jan 2026 was largely a ranging market with bullish bias.

**Strategy results:**
- Long trades: 32 taken, 31.25% win rate
- Short trades: 45 taken, 48.89% win rate

The EA is taking more bearish trades but both directions are losing money. The trend filter with EMA 100/50 may be generating false signals in ranging conditions.

**Recommendation:**
- Increase `TrendEMAPeriod` to 200
- Add ADX filter to avoid trading in low-trend environments
- OR disable trend filter entirely and rely only on S/R bounce

### Issue 4: Position Holding Time Too Short

**Average hold time:** 46 minutes

For a strategy targeting 2R on M15, positions need 4-8+ candles minimum to reach target. The short holding time suggests:
- Trades are getting stopped out before trends develop
- Trailing stop is too aggressive
- Market noise is shaking out valid positions

**Recommendation:**
- Increase `TrailingStopR` from 1.0 to 1.5
- Only trail after first partial close, not at breakeven
- Consider time-based exit instead of pure trailing

### Issue 5: Partial Close Math Still Negative EV

With current settings:
- `FirstTPMultiplier=1.5`
- `PartialClosePercent=33.0`
- `RiskRewardRatio=2.0`

**Full Win Scenario:**
- 33% × 1.5R = 0.50R
- 67% × 2.0R = 1.34R  
- Total: 1.84R

**Partial Win/Breakeven Scenario:**
- 33% × 1.5R = 0.50R
- 67% × 0R = 0 breakeven
- Total: 0.50R

**Full Loss:**
- 100% × -1R = -1.0R

**Expected Value Calculation:**
At 41.56% win rate, if 50% of wins reach full TP and 50% get trailed to breakeven:
- EV = 0.4156 × 0.5 × 1.84R + 0.4156 × 0.5 × 0.5R - 0.5844 × 1.0R
- EV = 0.382R + 0.104R - 0.584R
- EV = **-0.098R per trade** -- STILL NEGATIVE

To break even with current settings, need ~55% win rate.

---

## Recommended Parameter Changes

### Immediate Changes - High Priority

```ini
; Disable the counterproductive R:R filter
MinimumRRFilter=0.0

; Widen stop loss buffer
; CODE CHANGE REQUIRED - increase buffer from 0.1 to 0.3 ATR

; Less aggressive trailing
TrailingStopR=1.5

; Reduce trade frequency with stricter patterns
EngulfingMinRatio=2.0
PinBarRatio=3.0
```

### Code Changes Required

#### 1. Widen Stop Loss Buffer in ExecuteTrade function

Current code at line ~841:
```mql5
double buffer = atr[0] * 0.1; // Small buffer
```

Change to:
```mql5
double buffer = atr[0] * 0.3; // Wider buffer to avoid noise
```

#### 2. Add ADX Filter for Ranging Markets

Add new input:
```mql5
input bool UseADXFilter = true;
input int ADXPeriod = 14;
input double MinADXForTrend = 20.0;
```

Add check in trade validation:
```mql5
if(UseADXFilter)
{
    double adxValue = GetADXValue();
    if(adxValue < MinADXForTrend)
    {
        Print("Trade skipped: ADX ", adxValue, " below minimum ", MinADXForTrend);
        return false;
    }
}
```

#### 3. Add Minimum Body Size Filter

In DetectCandlestickPattern, add:
```mql5
double minBodyATR = atr[0] * 0.3;  // Body must be at least 30% of ATR
if(body1 < minBodyATR)
    return PATTERN_NONE;  // Skip tiny candles
```

#### 4. Improve Trend Filter for Ranging Markets

Current trend detection is too simple. Consider:
```mql5
// Add slope requirement
double slopeThreshold = atr[0] * 0.1;
if(MathAbs(ema50[0] - ema50[5]) < slopeThreshold)
    return TREND_NONE;  // Flat trend - no clear direction
```

---

## Alternative Strategy Approaches

### Option A: Counter-Trend Mean Reversion

Instead of trend-following on M15, consider:
- Trade against trend at extreme S/R levels
- Require 3+ touches on S/R zone
- Use RSI overbought/oversold confirmation

### Option B: Higher Timeframe Signals

- Use H1 or H4 for signal generation
- Use M15 only for entry timing
- This reduces noise and produces fewer, higher-quality signals

### Option C: Session-Based Trading

EURUSD has distinct behavior in:
- London session: Trending
- NY overlap: Volatile
- Asian session: Ranging

Adjust parameters or disable trading based on session.

---

## Test Plan

### Phase 1: Disable Harmful Filters
1. Set `MinimumRRFilter=0`
2. Backtest - expect more trades, similar or better results

### Phase 2: Widen Stop Losses  
1. Increase buffer to 0.3 ATR
2. Backtest - expect fewer immediate stop-outs

### Phase 3: Add ADX Filter
1. Skip trades when ADX < 20
2. Backtest - expect fewer trades, better win rate

### Phase 4: Stricter Patterns
1. Increase pattern ratios
2. Backtest - expect much fewer but higher quality trades

---

## Questions Before Proceeding

1. Would you like me to implement the code changes or just parameter tweaks first?

2. Should we try a completely different approach -higher timeframe signals or session filtering?

3. Do you have backtest data from the XAUUSD settings we can compare? The previous analysis showed XAUUSD was profitable.

4. Would you like to see a walk-forward optimization to find the best parameter combination?
