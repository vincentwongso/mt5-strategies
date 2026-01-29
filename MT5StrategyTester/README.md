# MT5 Strategy Tester with AI-Powered Optimization

An automated system for backtesting and optimizing MetaTrader 5 Expert Advisors using CrewAI agents.

## Overview

This system automates the strategy testing loop:

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Load Strategy  │────▶│  Run Backtest   │────▶│  Parse Results  │
│     (.mq5)      │     │    (MT5)        │     │     (XML)       │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                                        │
                                                        ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Save Modified  │◀────│  Modify Code    │◀────│  Analyze with   │
│    Strategy     │     │    (LLM)        │     │   CrewAI        │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │                                               │
        │              Up to 3 iterations               │
        └───────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │  Log Results    │
                    │   (CSV)         │
                    └─────────────────┘
```

## Features

- **Automated Compilation**: Compiles MQ5 files using MetaEditor
- **Batch Backtesting**: Runs MT5 Strategy Tester via command line
- **AI Analysis**: CrewAI agents analyze results and identify improvements
- **Code Modification**: LLM modifies MQL5 code based on analysis
- **Iterative Optimization**: Up to 3 iterations per strategy
- **Results Logging**: CSV output for tracking all tests

## Success Criteria

Default criteria (configurable):
- Monthly profit: 3-5%
- Max daily drawdown: 3%
- Max total drawdown: 10%
- Min profit factor: 1.5
- Min trades: 30

## Installation

### Prerequisites

1. **Windows VPS** with MetaTrader 5 installed
2. **Python 3.14+**
3. **Anthropic API key** for Claude

### Setup

```bash
# Clone/copy files to your VPS
cd mt5_strategy_tester

# Create virtual environment
python -m venv venv
venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set environment variable
set ANTHROPIC_API_KEY=your-api-key-here
```

### Configuration

Edit `config.py` to set your MT5 paths:

```python
@dataclass
class MT5Config:
    mt5_path: Path = Path(r"C:\Program Files\MetaTrader 5\terminal64.exe")
    metaeditor_path: Path = Path(r"C:\Program Files\MetaTrader 5\metaeditor64.exe")
    terminal_id: str = "YOUR_TERMINAL_ID"  # Found in MT5 Help > About
```

To find your terminal_id:
1. Open MT5
2. Go to File > Open Data Folder
3. Note the folder name (e.g., `D0E8209F77C8CF37AD8BF550E51FF075`)

## Usage

### Basic Usage

```bash
# Test all strategies in ./strategies folder
python main.py

# Test with custom parameters
python main.py --symbol GBPUSD --timeframe M15 --from-date 2024.01.01 --to-date 2024.06.30

# Test a single strategy
python main.py --single ./strategies/MyStrategy.mq5

# Use mock mode for testing without MT5
python main.py --mock
```

### Command Line Options

```
--strategies, -s    Path to strategies folder (default: ./strategies)
--symbol           Trading symbol (default: EURUSD)
--timeframe        Timeframe: M1,M5,M15,M30,H1,H4,D1 (default: H1)
--from-date        Backtest start date (default: 2024.01.01)
--to-date          Backtest end date (default: 2024.12.31)
--deposit          Initial deposit (default: 100000)
--max-iterations   Max optimization iterations (default: 3)
--mock             Use mock MT5 for testing
--single           Test single strategy file
--mt5-path         Path to MT5 terminal
--terminal-id      MT5 terminal ID
```

### Programmatic Usage

```python
from config import AppConfig
from main import StrategyTesterOrchestrator

# Configure
config = AppConfig()
config.backtest.symbol = "EURUSD"
config.backtest.period = "H1"
config.optimization.max_iterations = 3

# Create orchestrator
tester = StrategyTesterOrchestrator(config)

# Load and run
tester.load_strategies()
sessions = tester.run_queue()

# Check results
for session in sessions:
    print(f"{session.strategy_name}: {session.status.value}")
```

## Output

### CSV Results

Results are saved to `./results/backtest_results.csv`:

| Field | Description |
|-------|-------------|
| timestamp | Test datetime |
| strategy_name | EA name |
| iteration | Optimization iteration (1-3) |
| status | profitable/unprofitable/failed |
| net_profit | Net profit in $ |
| monthly_return_pct | Monthly return % |
| max_drawdown_pct | Maximum drawdown % |
| meets_criteria | True/False |

### Session Logs

Detailed logs saved in `./results/sessions/{strategy_name}/`:
- `iteration_N_code.mq5` - Code version for each iteration
- `iteration_N_analysis.txt` - LLM analysis and modifications

## CrewAI Agents

### Strategy Analyst
- Analyzes backtest results
- Identifies strengths and weaknesses
- Recommends specific improvements

### Code Modifier
- Implements MQL5 code changes
- Adjusts parameters, entry/exit logic
- Maintains code quality

### Risk Assessor
- Evaluates drawdown and risk metrics
- Suggests position sizing changes
- Recommends risk controls

## Project Structure

```
mt5_strategy_tester/
├── config.py           # Configuration classes
├── models.py           # Data models
├── mt5_automation.py   # MT5 interaction
├── crewai_agents.py    # AI agents
├── logger.py           # CSV logging
├── main.py             # Main orchestrator
├── requirements.txt    # Dependencies
├── strategies/         # MQ5 files to test
│   └── SampleStrategy.mq5
└── results/            # Output folder
    ├── backtest_results.csv
    └── sessions/
```

## Troubleshooting

### Common Issues

1. **Compilation fails**
   - Check MetaEditor path in config
   - Ensure MQ5 file has no syntax errors
   - Look at `.log` file in Experts folder

2. **Backtest doesn't start**
   - Verify terminal_id is correct
   - Check MT5 is not already running
   - Ensure symbol data is downloaded

3. **CrewAI errors**
   - Verify ANTHROPIC_API_KEY is set
   - Check API quota and limits

### Debug Mode

```bash
# Run with verbose output
python main.py --mock  # Test without MT5 first
```

## Extending

### Adding New Criteria

Edit `config.py`:

```python
@dataclass 
class SuccessCriteria:
    min_monthly_profit_pct: float = 3.0
    # Add your criteria here
    min_sharpe_ratio: float = 1.0
```

### Custom Agents

Add new agents in `crewai_agents.py`:

```python
self.new_agent = Agent(
    role="Your Role",
    goal="Your Goal",
    backstory="Agent backstory",
    llm=self.llm
)
```
