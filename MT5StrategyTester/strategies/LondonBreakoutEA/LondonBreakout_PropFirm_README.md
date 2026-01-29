# London Breakout EA - Prop Firm Edition

## Strategy Overview

The **Asian Range London Breakout** strategy captures the volatility surge when London traders enter the market after the quiet Asian session. It identifies the price range formed during Asian hours (00:00-07:00 GMT) and places pending orders to catch the breakout in either direction.

### Why This Strategy Works for Prop Firms

1. **Defined Risk** - Stop loss is always the opposite side of the range (known before entry)
2. **No Overnight Positions** - All trades close by 16:00 GMT (prop firm compliant)
3. **Limited Trades** - Maximum 2 trades per day prevents overtrading
4. **Conservative Risk** - 0.5% per trade allows for losing streaks without breaching limits

---

## Installation

1. Copy `LondonBreakout_PropFirm_EA.mq5` to your MT5 `Experts` folder:
   - Typically: `C:\Users\[YourName]\AppData\Roaming\MetaQuotes\Terminal\[ID]\MQL5\Experts\`
   
2. Restart MT5 or right-click on Navigator → Refresh

3. Drag the EA onto a **GBP/USD M15** chart (recommended)

4. Enable AutoTrading in MT5 (click the AutoTrading button in toolbar)

---

## Time Zone Configuration

**CRITICAL:** You must configure the session times based on YOUR BROKER'S server time, not your local time or GMT.

### How to Find Your Broker's GMT Offset

1. Open a chart in MT5
2. Look at the time shown on the X-axis
3. Compare with current GMT time (search "GMT time now")
4. Calculate the offset

### Recommended Settings by Broker Type

#### GMT+0 Broker (Rare)
```
AsianStartHour = 0      // 00:00 GMT
AsianEndHour = 7        // 07:00 GMT (London Open)
TradeWindowEndHour = 11 // 11:00 GMT
HardExitHour = 16       // 16:00 GMT
```

#### GMT+2 Broker (Common - e.g., IC Markets, Pepperstone during winter)
```
AsianStartHour = 2      // 00:00 GMT = 02:00 Server
AsianEndHour = 9        // 07:00 GMT = 09:00 Server
TradeWindowEndHour = 13 // 11:00 GMT = 13:00 Server
HardExitHour = 18       // 16:00 GMT = 18:00 Server
```

#### GMT+3 Broker (Common - e.g., Most brokers during summer/DST)
```
AsianStartHour = 3      // 00:00 GMT = 03:00 Server
AsianEndHour = 10       // 07:00 GMT = 10:00 Server
TradeWindowEndHour = 14 // 11:00 GMT = 14:00 Server
HardExitHour = 19       // 16:00 GMT = 19:00 Server
```

---

## Prop Firm Specific Settings

### FTMO / MyForexFunds / Similar (Standard Rules)

| Parameter | Setting | Reason |
|-----------|---------|--------|
| RiskPercent | 0.5 | Conservative - allows 10 consecutive losses |
| MaxDailyDD | 4.0 | Stops before 5% daily limit |
| MaxTotalDD | 8.0 | Stops before 10% total limit |
| MaxTradesPerDay | 2 | Prevents overtrading |
| TradeFriday | false | Fridays have more fakeouts |

### Aggressive Settings (After Passing Challenge)

| Parameter | Setting | Reason |
|-----------|---------|--------|
| RiskPercent | 1.0 | Higher risk per trade |
| MaxDailyDD | 4.0 | Keep protective limits |
| MaxTotalDD | 8.0 | Keep protective limits |
| MaxTradesPerDay | 2 | Same limit |
| TradeFriday | true | Optional - more opportunities |

### During Challenge Phase

| Parameter | Setting | Reason |
|-----------|---------|--------|
| RiskPercent | 0.75 | Balance between growth and safety |
| MaxDailyDD | 3.5 | Extra safety margin |
| MaxTotalDD | 7.0 | Extra safety margin |
| MaxTradesPerDay | 1 | Ultra conservative |
| TradeFriday | false | Minimize risk |

---

## Recommended Instruments

### Primary (Best Performance)
- **GBP/USD** - Highest London session volatility
- **EUR/USD** - Tightest spreads, good movement

### Secondary (Also Suitable)
- **EUR/GBP** - Pure London play
- **GBP/JPY** - High volatility but wider spreads
- **EUR/JPY** - Good volatility

### Avoid
- **USD/JPY** - More influenced by Asian/US sessions
- **AUD/USD** - Asian session currency
- **Exotic pairs** - Wide spreads eat into profits

---

## Parameter Reference

### Session Times
| Parameter | Default | Description |
|-----------|---------|-------------|
| AsianStartHour | 0 | When to start measuring the range |
| AsianEndHour | 7 | When range ends (London open) |
| TradeWindowEndHour | 11 | Stop placing new orders after this |
| HardExitHour | 16 | Close ALL positions by this time |

### Range Filters
| Parameter | Default | Description |
|-----------|---------|-------------|
| MinRangePips | 15 | Skip if Asian range is smaller |
| MaxRangePips | 50 | Skip if Asian range is larger |
| BufferPips | 5 | Entry buffer above/below range |

### Risk Management
| Parameter | Default | Description |
|-----------|---------|-------------|
| RiskPercent | 0.5 | % of equity risked per trade |
| MaxDailyDD | 4.0 | Stop trading if daily DD reaches this |
| MaxTotalDD | 8.0 | Kill switch if total DD reaches this |
| MaxTradesPerDay | 2 | Maximum entries per day |

### Take Profit Settings
| Parameter | Default | Description |
|-----------|---------|-------------|
| UseScaledExit | true | Close 50% at TP1, trail the rest |
| TP1_Pips | 30 | First take profit level |
| TP2_RiskMultiple | 2.0 | Final TP as R multiple |
| UseTrailingStop | true | Trail stop after TP1 |
| TrailingStopPips | 15 | Trailing stop distance |

### Day Filters
| Parameter | Default | Description |
|-----------|---------|-------------|
| TradeMonday | true | Trade on Mondays |
| TradeTuesday | true | Trade on Tuesdays |
| TradeWednesday | true | Trade on Wednesdays |
| TradeThursday | true | Trade on Thursdays |
| TradeFriday | false | Trade on Fridays (often worse) |

---

## How the Strategy Works

### Phase 1: Asian Session (Range Formation)
- EA monitors price from 00:00-07:00 GMT
- Records the highest high and lowest low
- No orders placed yet

### Phase 2: London Open (Order Placement)
- At 07:00 GMT, Asian range is finalized
- If range is 15-50 pips, orders are placed:
  - **Buy Stop** = Asian High + 5 pip buffer
  - **Sell Stop** = Asian Low - 5 pip buffer
- Stop Loss = opposite side of range

### Phase 3: Breakout Execution
- When price breaks one level, that order triggers
- Opposite pending order is immediately cancelled (OCO)
- Position management begins

### Phase 4: Position Management
- If **UseScaledExit = true**:
  1. Close 50% at TP1 (30 pips default)
  2. Move SL to breakeven
  3. Trail remaining 50% with 15-pip trailing stop
- If **UseScaledExit = false**:
  - Hold for full TP (2R default)
  - Optional trailing stop

### Phase 5: Hard Exit
- At 16:00 GMT, ALL positions are closed
- No overnight exposure (prop firm compliant)

---

## Risk Calculations

### Position Sizing Example
With $100,000 account and 0.5% risk per trade:

```
Risk Amount = $100,000 × 0.5% = $500

If Asian Range = 40 pips (typical)
Stop Loss = Range + Buffer × 2 = 40 + 10 = 50 pips

Lot Size = $500 / (50 pips × $10/pip) = 1.0 lot
```

### Daily Drawdown Tracking
The EA tracks drawdown from daily start equity:

```
Daily Start Equity: $100,000
Current Equity: $96,500
Daily DD = ($100,000 - $96,500) / $100,000 = 3.5%

If MaxDailyDD = 4%, trading continues
If MaxDailyDD = 3%, trading stops for the day
```

### Total Drawdown Tracking
Tracked from initial starting balance (stored in Global Variables):

```
Starting Balance: $100,000
Current Equity: $92,000
Total DD = ($100,000 - $92,000) / $100,000 = 8%

If MaxTotalDD = 8%, KILL SWITCH activates
```

---

## Troubleshooting

### "Kill Switch Active" Message
The EA hit total drawdown limit and disabled itself.

**To Reset:**
1. In MT5, go to View → Toolbox → Experts tab
2. Find the EA's Global Variables (LB_Prop_KillSwitch)
3. Delete the variable
4. Reload the EA

**Or** add this code to a script and run it:
```mql5
GlobalVariableDel("LB_Prop_KillSwitch");
```

### No Trades Being Placed
1. Check if today is a trading day (Monday disabled by default)
2. Check if Asian range is within 15-50 pip limits
3. Check if AutoTrading is enabled in MT5
4. Verify time settings match your broker's GMT offset

### Orders Placed at Wrong Time
Your broker time offset is incorrect. Recalculate using the method above.

### Partial Close Not Working
Some brokers don't support partial closes. Set `UseScaledExit = false` and use fixed TP instead.

---

## Backtesting Tips

1. **Use "Every tick based on real ticks"** - Most accurate
2. **Test minimum 1 year of data** - Captures different market conditions
3. **Verify time settings** - Check that orders place at correct times
4. **Check the Orders tab** - Look for cancelled orders (range filter working)

### Expected Performance (Realistic)
- **Win Rate:** 45-55%
- **Risk:Reward:** 1:1.5 to 1:2
- **Profit Factor:** 1.2-1.5
- **Monthly Return:** 3-8% (with 0.5% risk)
- **Max Drawdown:** 5-10%

---

## Changelog

### v1.0 (2025-01-30)
- Initial release
- Prop firm risk management integration
- Scaled exit system with partial TP
- Kill switch for total drawdown protection
- Daily drawdown tracking
- Visual range display on chart

---

## Disclaimer

This EA is for educational purposes. Past performance does not guarantee future results. Always test thoroughly on demo accounts before using real money. Trading forex involves substantial risk of loss.
