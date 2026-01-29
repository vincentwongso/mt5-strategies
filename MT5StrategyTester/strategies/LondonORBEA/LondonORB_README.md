# London Opening Range Breakout EA v2.0 - Fixed

## What Was Fixed (v1 → v2)

### The Problem
In v1, orders were placed at **00:01 server time** (midnight) and immediately canceled because:

1. **GMT offset logic was broken** - The EA tried to convert server time to GMT using subtraction, but this didn't handle day boundary crossings correctly
2. **Expiration times were invalid** - Orders were created with expiration times already in the past
3. **Phase detection failed** - The EA thought it was "past" the range end when it was actually the wrong day

### The Solution
**v2 uses SERVER TIME directly** - no more GMT conversion gymnastics!

| Parameter | v1 (Broken) | v2 (Fixed) |
|-----------|-------------|------------|
| RangeStartHour | 4 (GMT) + GMTOffset conversion | 6 (direct server time) |
| RangeEndHour | 8 (GMT) + GMTOffset conversion | 10 (direct server time) |
| HardExitHour | 16 (GMT) + GMTOffset conversion | 18 (direct server time) |

**For a GMT+2 broker:**
- 04:00 GMT = 06:00 Server Time
- 08:00 GMT = 10:00 Server Time  
- 16:00 GMT = 18:00 Server Time

## Installation

1. Copy `LondonORB_EA_v2.mq5` to your MT5 `Experts` folder
2. Compile in MetaEditor
3. Attach to **M15 chart** (GBPUSD or GBPJPY)

## Configuration for Your Broker

### Step 1: Determine Your Broker's GMT Offset

Check your broker's server time:
- Most EU/UK brokers: GMT+2 (winter) / GMT+3 (summer)
- US brokers: Often GMT-5 or GMT-4

### Step 2: Set Times in SERVER TIME

| GMT Time | GMT+2 Server | GMT+3 Server |
|----------|--------------|--------------|
| 04:00 | 06:00 | 07:00 |
| 08:00 | 10:00 | 11:00 |
| 16:00 | 18:00 | 19:00 |

**Example for GMT+2 broker (like Fintrix):**
```
RangeStartHour = 6
RangeEndHour = 10
HardExitHour = 18
```

**Example for GMT+3 broker:**
```
RangeStartHour = 7
RangeEndHour = 11
HardExitHour = 19
```

## Key Parameters

### Time Settings (SERVER TIME)
| Parameter | Default | Description |
|-----------|---------|-------------|
| RangeStartHour | 6 | Range starts (04:00 GMT for GMT+2) |
| RangeEndHour | 10 | Range ends / Orders placed |
| HardExitHour | 18 | All positions closed |

### Risk Management
| Parameter | Default | Description |
|-----------|---------|-------------|
| RiskPercent | 1.0% | Risk per trade |
| MaxDailyDD | 3.0% | Daily drawdown limit |
| MaxTotalDD | 10.0% | Total drawdown (kill switch) |
| RiskRewardRatio | 1.5 | TP = SL × 1.5 |

### Range Filters
| Parameter | Default | Description |
|-----------|---------|-------------|
| MinRangePips | 10 | Skip if range < 10 pips |
| MaxRangePips | 50 | Skip if range > 50 pips |
| BufferPips | 3 | Entry buffer |

## Trading Flow (Server Time for GMT+2)

```
06:00 → Range calculation starts
        EA tracks High/Low of M15 candles
        
10:00 → Range finalized
        Buy Stop placed above range high + buffer
        Sell Stop placed below range low - buffer
        OCO logic active
        
10:00-18:00 → Trading window
        Monitor for breakout
        Manage positions (breakeven, trailing)
        
18:00 → Session end
        Close all positions
        Delete pending orders
        Wait for next day
```

## Backtesting Tips

1. **Use "Every tick based on real ticks"** for accurate stop order execution
2. **Verify times** - Check the Journal/Experts tab for "Range Finalized" messages
3. **Check order placement times** - Should be at RangeEndHour, not midnight

## Chart Display

The EA shows on-chart status including:
- Current phase (WAITING, RANGE FORMING, TRADING PHASE, SESSION ENDED)
- Range levels and size
- Daily/Total drawdown percentages
- Position status

## Troubleshooting

### No trades triggering?
1. Check RangeEndHour matches your broker's equivalent of 08:00 GMT
2. Verify MinRangePips isn't filtering out all ranges
3. Look for "Range too small" or "Range too large" in Experts log

### Orders still canceling immediately?
1. Ensure HardExitHour is AFTER RangeEndHour
2. Check that backtest period includes trading days (not just weekends)

### Kill switch triggered?
Call `ResetKillSwitch()` function or delete global variable `LondonORB_KillSwitch`
