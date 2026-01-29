# SimpleSystem TF15 - Quick Reference Card

## ⚡ Entry Signals at a Glance

### 🟢 BUY SIGNAL
```
✓ Price closes ABOVE 10 EMA
✓ TDI Green crosses ABOVE Yellow
✓ Price is 15+ pips AWAY from 200 EMA
✓ Price above 800 EMA (if filter on)
✓ London or NY session active
```

### 🔴 SELL SIGNAL
```
✓ Price closes BELOW 10 EMA
✓ TDI Green crosses BELOW Yellow
✓ Price is 15+ pips AWAY from 200 EMA
✓ Price below 800 EMA (if filter on)
✓ London or NY session active
```

## 📊 Default Settings

| Setting | Value |
|---------|-------|
| Timeframe | M15 |
| Risk | 0.5% |
| Stop Loss | 20 pips |
| Take Profit | 40 pips |
| Breakeven | At 12 pips |

## 🕐 Best Trading Times (GMT)

| Session | Start | End |
|---------|-------|-----|
| London | 08:00 | 17:00 |
| New York | 13:00 | 22:00 |
| **Overlap** | **13:00** | **17:00** |

*Adjust for your broker's server time*

## 📈 TDI Quick Guide

- **Green Line** = RSI Price (fast)
- **Red Line** = Signal Line (slow)
- **Yellow Line** = Market Base (trend)

### TDI Signals:
- Green > Yellow = Bullish
- Green < Yellow = Bearish
- Green crossing Yellow = Entry trigger

## 🛡️ Risk Management Rules

1. ❌ Never risk more than 2% per trade
2. ✅ Move to breakeven at 12 pips
3. 📉 20 pip stop loss is FIXED
4. 🎯 Minimum 1:1 risk/reward

## ⚠️ Avoid Trading When:

- Major news events
- Market gaps
- Friday after 18:00 GMT
- Very wide spreads
- TDI in extreme zones (above 68 or below 32)

## 🔧 Troubleshooting

| Problem | Solution |
|---------|----------|
| No trades | Check session time |
| Wrong entries | Verify TDI cross |
| Large losses | Reduce risk % |
| Missing signals | Check EMA distance |

## 📁 Files Checklist

- [ ] SimpleSystem_TF15_EA.mq5 → MQL5/Experts/
- [ ] TDI_RedGreen.mq5 → MQL5/Indicators/
- [ ] RoundNumbers.mq5 → MQL5/Indicators/
- [ ] TradingTimes.mq5 → MQL5/Indicators/
- [ ] SimpleSystem_TF15.tpl → Profiles/Templates/

## 🎓 Remember

> "Trade during London/NY for momentum, 
>  away from 200 EMA for room to move,
>  with TDI confirmation for accuracy."

---
*Magic Number: 345586*
