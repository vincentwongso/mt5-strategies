# PriceAction EA Backtest Analysis & Improvement Plan

## Executive Summary

After analyzing backtest results for EURUSD, XAUUSD (Gold), and XAGUSD (Silver) over the period October 2025 - January 2026, I have identified critical issues that need to be addressed to improve the strategy's performance.

**Key Finding:** The strategy has a fundamental problem with the **effective risk:reward ratio** - despite targeting 2R, the actual average profit:loss ratio is inverted across all instruments.

---

## Backtest Performance Summary

| Metric | EURUSD | XAUUSD (Gold) | XAGUSD (Silver) |
|--------|--------|---------------|-----------------|
| **Net Profit** | -$10,363.69 | +$5,133.23 | -$1,884.35 |
| **Profit Factor** | 0.62 | 1.22 | 0.94 |
| **Total Trades** | 133 | 170 | 169 |
| **Win Rate** | 56.39% | 67.65% | 63.31% |
| **Max Drawdown** | 12.99% | 4.85% | 5.37% |
| **Avg Profit Trade** | $224.55 | $250.53 | $258.12 |
| **Avg Loss Trade** | -$469.05 | -$430.50 | -$475.86 |
| **Max Consec. Losses** | 13 | 5 | 6 |
| **Sharpe Ratio** | -5.00 | 6.94 | -2.37 |
| **Recovery Factor** | -0.79 | 1.01 | -0.34 |

---

## Critical Issues Identified

### 1. Inverted Risk:Reward Ratio (CRITICAL)

**Problem:** Despite targeting a 2:1 R:R ratio, the actual results show losses are approximately **2x larger than profits** across all instruments.

| Instrument | Avg Profit | Avg Loss | Actual R:R |
|------------|-----------|----------|------------|
| EURUSD | $224.55 | $469.05 | **0.48:1** |
| XAUUSD | $250.53 | $430.50 | **0.58:1** |
| XAGUSD | $258.12 | $475.86 | **0.54:1** |

**Root Cause:** The 50% partial close at 1R combined with trailing stop losses at 1R effectively reduces the average winning trade size, while full stop losses remain at 1R for losing trades.

**Mathematical Breakdown:**
- Winner with partial close: 50% × 1R + 50% × (1R to 2R) = 0.5R + 0.5R to 1R = **~0.75R to 1.5R average**
- Loser: **Full 1R loss**

This explains why average losses are roughly 2x average profits.

### 2. EURUSD Severe Underperformance

**Problem:** EURUSD has 13 consecutive losses and a -10.36% total loss with profit factor 0.62.

**Potential Causes:**
- Price action patterns may not be suitable for EURUSD on M15 timeframe
- S/R zone detection may not align well with EURUSD market structure
- EMA trend filter (20/50) may generate whipsaws in ranging EURUSD markets

### 3. High Z-Score Indicating Streak Dependency

| Instrument | Z-Score | Interpretation |
|------------|---------|----------------|
| EURUSD | -4.59 (99.74%) | Wins and losses strongly cluster |
| XAGUSD | -3.66 (99.74%) | Wins and losses strongly cluster |
| XAUUSD | -1.39 (83.55%) | Moderate clustering |

A negative Z-score indicates that wins tend to follow wins and losses tend to follow losses. This suggests the strategy may be entering during unfavorable market conditions and staying too long.

### 4. Inside Bar Pattern Concerns

From order comments in the backtest, Inside Bar signals appear to generate many immediate stop-outs, particularly on XAGUSD where trades are stopped out within seconds (e.g., 2025.10.22 08:00:00 to 08:00:36 = 36 seconds).

---

## Improvement Recommendations

### Priority 1: Fix the Risk:Reward Execution

#### Option A: Reduce Partial Close Percentage
**Current:** `PartialClosePercent = 50.0`  
**Recommended:** `PartialClosePercent = 33.0` (close only 1/3 at 1R, keep 2/3 running)

**Expected Impact:**
- Winner average: 33% × 1R + 67% × (1R to 2R) ≈ 0.33R + 0.67R to 1.34R = **~1R to 1.67R**
- This brings actual R:R closer to 1:1 or better

#### Option B: Increase First TP Multiplier
**Current:** `FirstTPMultiplier = 1.0`  
**Recommended:** `FirstTPMultiplier = 1.5`

Take the first partial at 1.5R instead of 1R, allowing more profit to accumulate before scaling out.

#### Option C: Reduce Trailing Intensity
**Current:** Trailing activates at 1R and moves stop to breakeven  
**Recommended:** Add a `TrailingBuffer` parameter that keeps stop slightly below breakeven (e.g., -0.2R) to avoid being shaken out by noise.

### Priority 2: Add Minimum R:R Filter Before Entry

**New Parameter:** `MinimumRRFilter = 1.5`

Before entering a trade, calculate if the distance to the opposite S/R zone (potential target) is at least 1.5x the stop loss distance. Skip trades where reward potential is too low.

```mql5
// Pseudocode for new filter
double distanceToTarget = CalculateDistanceToOppositeZone();
double distanceToStop = MathAbs(entryPrice - stopLoss);
if(distanceToTarget / distanceToStop < MinimumRRFilter)
{
    // Skip this trade - reward potential too low
    return false;
}
```

### Priority 3: Disable or Improve Inside Bar Pattern

**Option A: Disable for problematic instruments**
```mql5
// Set for EURUSD and XAGUSD
UseInsideBar = false
```

**Option B: Add additional confirmation**
- Require the breakout candle to close beyond the Inside Bar range
- Add minimum bar size requirement relative to ATR

### Priority 4: Increase Pattern Detection Stringency

**Engulfing Pattern:**
- **Current:** `EngulfingMinRatio = 1.2`
- **Recommended:** `EngulfingMinRatio = 1.5` (require 50% larger body, not just 20%)

**Pin Bar:**
- **Current:** `PinBarRatio = 2.0`
- **Recommended:** `PinBarRatio = 2.5` (stronger rejection requirement)

### Priority 5: Add Volatility Filter

**New Parameter:** `MinATRFilter`

Avoid trading during low volatility periods where patterns may generate false signals.

```mql5
input double MinATRFilter = 0.5;  // Minimum ATR as % of current price

// In signal validation
double currentATR = atrBuffer[0];
double pricePercent = (currentATR / currentPrice) * 100;
if(pricePercent < MinATRFilter)
{
    // Skip - volatility too low
    return false;
}
```

### Priority 6: Instrument-Specific Parameters

Create optimized parameter sets for each instrument:

#### EURUSD Recommended Settings
```
UseTrendFilter = true
TrendEMAPeriod = 100  // Slower trend filter
FastEMAPeriod = 50
UseInsideBar = false
EngulfingMinRatio = 1.5
PartialClosePercent = 33.0
```

#### XAUUSD Recommended Settings (Best Performer - Minor Tweaks)
```
UseTrendFilter = true
TrendEMAPeriod = 50
FastEMAPeriod = 20
UseInsideBar = true
EngulfingMinRatio = 1.3
PartialClosePercent = 40.0
```

#### XAGUSD Recommended Settings
```
UseTrendFilter = true
TrendEMAPeriod = 50
FastEMAPeriod = 20
UseInsideBar = false
EngulfingMinRatio = 1.4
PartialClosePercent = 33.0
```

### Priority 7: Add Drawdown-Based Trade Filter

**New Feature:** Reduce trade size or pause trading after consecutive losses.

```mql5
input int MaxConsecutiveLosses = 5;  // Pause after N consecutive losses
input int PauseBarsAfterLosses = 20;  // Number of bars to pause
```

This would address the clustering effect shown by the Z-Score analysis.

---

## Implementation Roadmap

### Phase 1: Quick Wins (Low Risk Changes)
1. Reduce `PartialClosePercent` from 50 to 33
2. Increase `FirstTPMultiplier` from 1.0 to 1.5
3. Increase `EngulfingMinRatio` from 1.2 to 1.5
4. Increase `PinBarRatio` from 2.0 to 2.5

### Phase 2: Pattern Filtering
1. Add parameter to disable Inside Bar per instrument
2. Test with Inside Bar disabled on EURUSD and XAGUSD

### Phase 3: New Features
1. Add MinimumRRFilter check before entry
2. Add MinATRFilter for volatility screening
3. Add consecutive loss pause feature

### Phase 4: Advanced Optimization
1. Create instrument-specific .set files with optimized parameters
2. Consider adding higher timeframe confluence filter
3. Implement adaptive position sizing based on recent performance

---

## Expected Outcome

After implementing Priority 1-4 changes, expected improvements:

| Metric | Current Range | Target Range |
|--------|---------------|--------------|
| Profit Factor | 0.62 - 1.22 | > 1.30 |
| Actual R:R Ratio | 0.48:1 - 0.58:1 | > 0.8:1 |
| Max Consecutive Losses | 5 - 13 | < 6 |
| Win Rate | 56% - 68% | May decrease slightly |

**Note:** Win rate may decrease with stricter filters, but each winning trade should be larger, improving overall profitability.

---

## Code Changes Summary

The following files need modification:

1. **PriceActionEA.mq5** - Add new parameters and filters
   - New input: `MinimumRRFilter`
   - New input: `MinATRFilter`
   - New input: `MaxConsecutiveLosses`
   - Modify partial close logic
   - Add pre-entry R:R validation

2. **PriceActionEA_Default.set** - Update default parameters
   - Adjust `PartialClosePercent`
   - Adjust pattern ratios

3. **New files to create:**
   - `PriceActionEA_EURUSD.set`
   - `PriceActionEA_XAUUSD.set`
   - `PriceActionEA_XAGUSD.set`

---

## Questions for User

Before proceeding with implementation, please confirm:

1. **Priority Focus:** Would you like to start with the quick wins (partial close adjustment) or the new filter features?

2. **Testing Strategy:** Do you want to keep the changes backward-compatible (new features as optional parameters) or is it acceptable to change default behavior?

3. **Instrument Preference:** Should I focus on improving all three instruments equally, or prioritize the already-profitable XAUUSD?

4. **Timeframe Consideration:** The current tests are on M15 - would you also like to test on H1 or H4 for potentially better signals?
