# Quick Installation Guide

## Automatic Installation (Copy these commands)

### Windows (PowerShell):
```powershell
# Find your MT5 Data folder (usually):
# C:\Users\[YourName]\AppData\Roaming\MetaQuotes\Terminal\[HASH]\MQL5

# Copy the EA:
Copy-Item "TradingMadeSimple_EA.mq5" "C:\Users\$env:USERNAME\AppData\Roaming\MetaQuotes\Terminal\*\MQL5\Experts\"

# Copy indicators:
Copy-Item -Recurse "TMS_Indicators" "C:\Users\$env:USERNAME\AppData\Roaming\MetaQuotes\Terminal\*\MQL5\Indicators\"

# Copy template:
Copy-Item "*.tpl" "C:\Users\$env:USERNAME\AppData\Roaming\MetaQuotes\Terminal\*\MQL5\Profiles\Templates\"
```

## Manual Installation Steps

1. **Find your MT5 Data Folder:**
   - Open MT5
   - Go to File → Open Data Folder
   - Navigate to MQL5 folder

2. **Copy Expert Advisor:**
   - Copy `Experts/TradingMadeSimple_EA.mq5`
   - Paste into `MQL5/Experts/`

3. **Copy Indicators:**
   - Copy the entire `TMS_Indicators` folder
   - Paste into `MQL5/Indicators/`

4. **Copy Template (Optional):**
   - Copy `Templates/TMS_Template_4H.tpl`
   - Paste into `MQL5/Profiles/Templates/`

5. **Compile in MetaEditor:**
   - Press F4 in MT5 to open MetaEditor
   - In Navigator, find each .mq5 file
   - Press F7 to compile each file
   - Check for "0 errors" message

6. **Restart MT5:**
   - Close and reopen MT5
   - OR right-click Navigator → Refresh

7. **Apply Template (Optional):**
   - Right-click chart
   - Select Templates → TMS_Template_4H

8. **Attach EA:**
   - Find "TradingMadeSimple_EA" in Navigator
   - Drag it onto your chart
   - Configure settings
   - Click OK

## Quick Settings for Demo Testing

```
Trade Settings:
- Lot Size: 0.01 (mini lot)
- Risk Percent: 1.0
- Max Spread: 20

Entry Methods:
- Trade Crossovers: true
- Trade Continuation: true
- Require All Confirm: true

Exit Settings:
- Exit On Color Change: true
- Exit On HMA Cross: true
```

## Recommended Pairs
- EURUSD (lowest spread)
- GBPUSD
- USDJPY
- AUDUSD

## Recommended Timeframes
- H4 (4-hour) - Best balance
- D1 (Daily) - Fewer signals, larger moves
- H1 (1-hour) - More signals, more noise

## Trading Sessions (Server Time)
- London: 08:00 - 16:00
- New York: 13:00 - 21:00
- Best: 13:00 - 16:00 (Overlap)

## Checklist Before Going Live
- [ ] Tested on demo for at least 1 month
- [ ] Reviewed backtest results
- [ ] Understand all entry/exit rules
- [ ] Set appropriate lot size for account
- [ ] VPS connection stable (if using)
- [ ] Broker spread is reasonable
- [ ] Account type allows hedging (if needed)

## Support
Original strategy thread:
https://www.forexfactory.com/thread/917569-trading-made-simpler

Read the full README.md for detailed strategy explanation.
