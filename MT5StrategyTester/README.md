# MT5 Strategy Tester

Automated backtesting and AI-powered strategy improvement for MetaTrader 5 Expert Advisors.

## Overview

This tool provides two main scripts:
1. **run_backtest.py** - Run backtests on MQ5 strategies and save results
2. **improve_strategy.py** - Use AI (Anthropic Claude) to analyze results and generate improved code

## Requirements

- Windows with MetaTrader 5 installed
- Python 3.10+
- Anthropic API key (for strategy improvement)

## Installation

1. Clone the repository
2. Install dependencies:
   ```bash
   cd MT5StrategyTester
   pip install -r requirements.txt
   ```
3. Copy `.env.example` to `.env` and add your Anthropic API key:
   ```
   ANTHROPIC_API_KEY=your_api_key_here
   ```
4. Update `config.yaml` with your MT5 paths and settings

## Configuration

Edit `config.yaml` to configure:

- **mt5**: MetaTrader 5 paths and terminal settings
- **backtest**: Default backtest parameters (symbol, timeframe, dates, deposit)
- **success**: Target criteria for strategy evaluation
- **anthropic**: AI model settings

## Usage

### Step 1: Run a Backtest

```bash
# Basic usage
python run_backtest.py --strategy ./strategies/LondonBreakoutEA/LondonBreakout_PropFirm_EA.mq5

# Override backtest parameters
python run_backtest.py --strategy ./strategies/LondonBreakoutEA/LondonBreakout_PropFirm_EA.mq5 \
    --symbol EURUSD --timeframe H1 --from-date 2025.01.01 --to-date 2025.12.31

# Use mock mode for testing (no MT5 required)
python run_backtest.py --strategy ./strategies/LondonBreakoutEA/LondonBreakout_PropFirm_EA.mq5 --mock
```

**Output:**
- Displays results in console with pass/fail criteria check
- Saves HTM report to `{strategy_folder}/results/`
- Updates CSV log at `{strategy_folder}/results/backtest_results.csv`

### Step 2: Improve Strategy with AI

```bash
# Use most recent backtest results
python improve_strategy.py --strategy ./strategies/LondonBreakoutEA/LondonBreakout_PropFirm_EA.mq5

# Use specific HTM report
python improve_strategy.py --strategy ./strategies/LondonBreakoutEA/LondonBreakout_PropFirm_EA.mq5 \
    --report ./strategies/LondonBreakoutEA/results/report_20260130.htm
```

**Output:**
- Displays current performance metrics
- Shows AI-generated improvement summary
- Saves improved code to `{strategy_folder}/modified/{strategy_name}_v{N}.mq5`

### Step 3: Test Improved Version

```bash
python run_backtest.py --strategy ./strategies/LondonBreakoutEA/modified/LondonBreakout_PropFirm_EA_v2.mq5
```

## Directory Structure

```
MT5StrategyTester/
├── run_backtest.py          # Backtest runner script
├── improve_strategy.py      # AI strategy improvement script
├── anthropic_client.py      # Anthropic API integration
├── mt5_automation.py        # MT5 automation (compile, run, parse)
├── config_loader.py         # Configuration loading
├── config.yaml              # Configuration file
├── models.py                # Data models
├── logger.py                # Logging utilities
├── requirements.txt         # Python dependencies
└── strategies/
    └── YourStrategy/
        ├── YourStrategy.mq5
        ├── results/
        │   ├── backtest_results.csv
        │   └── YourStrategy_20260130_143022.htm
        └── modified/
            ├── YourStrategy_v1.mq5
            └── YourStrategy_v2.mq5
```

## Success Criteria

The default success criteria (configurable in `config.yaml`):

| Metric | Target |
|--------|--------|
| Monthly Profit | ≥3% |
| Daily Drawdown | ≤3% |
| Total Drawdown | ≤10% |
| Profit Factor | ≥1.5 |
| Minimum Trades | 30 |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `ANTHROPIC_API_KEY` | Your Anthropic API key |
| `MT5_LOGIN` | MT5 account login (optional) |
| `MT5_PASSWORD` | MT5 account password (optional) |
| `MT5_SERVER` | MT5 server name (optional) |

## License

MIT License
