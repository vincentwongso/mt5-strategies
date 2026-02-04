"""
MT5 Strategy Backtest Runner

Runs a single strategy backtest and saves results.
Usage: python run_backtest.py --strategy <path_to_mq5_file>

Examples:
    # Basic usage
    python run_backtest.py --strategy ./strategies/LondonBreakoutEA/LondonBreakout_PropFirm_EA.mq5

    # With custom config
    python run_backtest.py --strategy ./strategies/LondonBreakoutEA/LondonBreakout_PropFirm_EA.mq5 --config ./config.yaml

    # Override backtest parameters
    python run_backtest.py --strategy ./strategies/LondonBreakoutEA/LondonBreakout_PropFirm_EA.mq5 --symbol EURUSD --timeframe H1 --from-date 2025.01.01 --to-date 2025.12.31

    # Use mock mode for testing
    python run_backtest.py --strategy ./strategies/LondonBreakoutEA/LondonBreakout_PropFirm_EA.mq5 --mock
"""
import argparse
import sys
from pathlib import Path
from datetime import datetime
from typing import Optional

from dotenv import load_dotenv

from config_loader import load_config, AppConfig, SuccessCriteria
from mt5_automation import MT5Automation, MockMT5Automation
from logger import ResultsLogger
from models import BacktestResult, StrategyStatus


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments"""
    parser = argparse.ArgumentParser(
        description="Run MT5 Strategy Backtest",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python run_backtest.py --strategy ./strategies/LondonBreakoutEA/LondonBreakout_PropFirm_EA.mq5
  python run_backtest.py --strategy ./strategies/MyEA.mq5 --symbol EURUSD --timeframe H1
  python run_backtest.py --strategy ./strategies/MyEA.mq5 --mock
        """
    )
    parser.add_argument(
        "--strategy", "-s",
        type=str,
        required=True,
        help="Path to MQ5 strategy file"
    )
    parser.add_argument(
        "--config", "-c",
        type=str,
        default=None,
        help="Path to config.yaml (default: MT5StrategyTester/config.yaml)"
    )
    parser.add_argument(
        "--symbol",
        type=str,
        default=None,
        help="Trading symbol (overrides config)"
    )
    parser.add_argument(
        "--timeframe",
        type=str,
        default=None,
        help="Timeframe (overrides config)"
    )
    parser.add_argument(
        "--from-date",
        type=str,
        default=None,
        help="Backtest start date YYYY.MM.DD (overrides config)"
    )
    parser.add_argument(
        "--to-date",
        type=str,
        default=None,
        help="Backtest end date YYYY.MM.DD (overrides config)"
    )
    parser.add_argument(
        "--deposit",
        type=float,
        default=None,
        help="Initial deposit (overrides config)"
    )
    parser.add_argument(
        "--mock",
        action="store_true",
        help="Use mock MT5 automation for testing"
    )
    return parser.parse_args()


def check_criteria(result: BacktestResult, criteria: SuccessCriteria) -> dict:
    """
    Check backtest results against success criteria.
    
    Returns:
        dict with criteria name, passed status, actual value, and target
    """
    checks = {}
    
    # Monthly Return
    checks['monthly_return'] = {
        'passed': result.performance.monthly_return_pct >= criteria.min_monthly_profit_pct,
        'actual': result.performance.monthly_return_pct,
        'target': f"≥{criteria.min_monthly_profit_pct}%",
        'label': 'Monthly Return'
    }
    
    # Daily Drawdown
    checks['daily_drawdown'] = {
        'passed': result.drawdown.max_daily_drawdown_pct <= criteria.max_daily_drawdown_pct,
        'actual': result.drawdown.max_daily_drawdown_pct,
        'target': f"≤{criteria.max_daily_drawdown_pct}%",
        'label': 'Daily Drawdown'
    }
    
    # Total Drawdown
    checks['total_drawdown'] = {
        'passed': result.drawdown.max_drawdown_pct <= criteria.max_total_drawdown_pct,
        'actual': result.drawdown.max_drawdown_pct,
        'target': f"≤{criteria.max_total_drawdown_pct}%",
        'label': 'Total Drawdown'
    }
    
    # Profit Factor
    checks['profit_factor'] = {
        'passed': result.performance.profit_factor >= criteria.min_profit_factor,
        'actual': result.performance.profit_factor,
        'target': f"≥{criteria.min_profit_factor}",
        'label': 'Profit Factor'
    }
    
    # Total Trades
    checks['total_trades'] = {
        'passed': result.trades.total_trades >= criteria.min_trades,
        'actual': result.trades.total_trades,
        'target': f"≥{criteria.min_trades}",
        'label': 'Total Trades'
    }
    
    # Win Rate (optional check)
    checks['win_rate'] = {
        'passed': result.trades.win_rate >= criteria.min_win_rate,
        'actual': result.trades.win_rate,
        'target': f"≥{criteria.min_win_rate}%",
        'label': 'Win Rate'
    }
    
    return checks


def print_results(result: BacktestResult, criteria: SuccessCriteria) -> bool:
    """
    Print backtest results to console with formatted output.
    
    Returns:
        bool: True if all criteria passed, False otherwise
    """
    print()
    print("📈 Results:")
    print(f"   Net Profit:     ${result.performance.net_profit:,.2f}")
    print(f"   Monthly Return: {result.performance.monthly_return_pct:.2f}%")
    print(f"   Profit Factor:  {result.performance.profit_factor:.2f}")
    print(f"   Total Trades:   {result.trades.total_trades}")
    print(f"   Win Rate:       {result.trades.win_rate:.1f}%")
    print(f"   Max Drawdown:   {result.drawdown.max_drawdown_pct:.2f}%")
    print(f"   Sharpe Ratio:   {result.performance.sharpe_ratio:.2f}")
    
    # Check criteria
    checks = check_criteria(result, criteria)
    
    print()
    print("📋 Criteria Check:")
    
    all_passed = True
    for key, check in checks.items():
        status = "✅" if check['passed'] else "❌"
        if not check['passed']:
            all_passed = False
        
        # Format actual value based on type
        actual = check['actual']
        if isinstance(actual, float):
            if 'pct' in key or 'return' in key or 'drawdown' in key or 'rate' in key:
                actual_str = f"{actual:.2f}%"
            else:
                actual_str = f"{actual:.2f}"
        else:
            actual_str = str(actual)
        
        print(f"   {status} {check['label']}: {actual_str} (target: {check['target']})")
    
    return all_passed


def run_backtest(
    args: argparse.Namespace, 
    config: AppConfig
) -> tuple[bool, Optional[BacktestResult], Optional[Path]]:
    """
    Run the backtest for a single strategy.
    
    Args:
        args: Parsed command-line arguments
        config: Application configuration
        
    Returns:
        tuple: (success, result, report_path)
    """
    strategy_path = Path(args.strategy).resolve()
    
    # Validate strategy file exists
    if not strategy_path.exists():
        print(f"❌ Strategy file not found: {strategy_path}")
        return False, None, None
    
    if not strategy_path.suffix.lower() == '.mq5':
        print(f"❌ Invalid file type: {strategy_path.suffix}. Expected .mq5 file.")
        return False, None, None
    
    # Initialize MT5 automation (mock or real)
    if args.mock:
        print("🔧 Using mock MT5 automation (testing mode)")
        mt5 = MockMT5Automation(config)
    else:
        mt5 = MT5Automation(config)
    
    # Print backtest info
    strategy_name = strategy_path.stem
    print()
    print(f"📊 Running backtest for: {strategy_name}")
    print(f"   Symbol: {config.backtest.symbol}, Timeframe: {config.backtest.period}")
    print(f"   Period: {config.backtest.from_date} - {config.backtest.to_date}")
    print()
    
    # Run full backtest cycle
    success, result, report_path, message = mt5.full_backtest_cycle(
        mq5_file=strategy_path,
        copy_report=True
    )
    
    if not success:
        print(f"❌ {message}")
        return False, None, report_path
    
    print("✅ Backtest completed")
    
    return True, result, report_path


def get_results_csv_path(strategy_path: Path) -> Path:
    """
    Get the path to the results CSV file for a strategy.
    
    Args:
        strategy_path: Path to the MQ5 strategy file
        
    Returns:
        Path to the backtest_results.csv file
    """
    strategy_dir = strategy_path.parent
    
    # Check if the strategy is in a dedicated subfolder
    if strategy_dir.name.lower() != 'strategies':
        # Strategy is in a subfolder like strategies/LondonBreakoutEA/
        results_folder = strategy_dir / 'results'
    else:
        # Strategy is directly in strategies folder
        results_folder = strategy_dir / 'results'
    
    return results_folder / 'backtest_results.csv'


def main() -> int:
    """
    Main entry point.
    
    Returns:
        Exit code: 0 if successful and criteria met, 1 otherwise
    """
    # Load environment variables
    load_dotenv()
    
    # Parse arguments
    args = parse_args()
    
    # Load configuration
    config_path = Path(args.config) if args.config else None
    try:
        config = load_config(config_path)
    except Exception as e:
        print(f"❌ Failed to load configuration: {e}")
        return 1
    
    # Apply command-line overrides
    if args.symbol:
        config.backtest.symbol = args.symbol
    if args.timeframe:
        config.backtest.period = args.timeframe
    if args.from_date:
        config.backtest.from_date = args.from_date
    if args.to_date:
        config.backtest.to_date = args.to_date
    if args.deposit:
        config.backtest.deposit = args.deposit
    
    # Run backtest
    success, result, report_path = run_backtest(args, config)
    
    if not success or result is None:
        print()
        print("❌ Backtest failed")
        return 1
    
    # Print results and check criteria
    all_criteria_passed = print_results(result, config.success)
    
    # Determine strategy status
    if all_criteria_passed:
        status = StrategyStatus.PROFITABLE
    else:
        status = StrategyStatus.UNPROFITABLE
    
    # Save to CSV using ResultsLogger
    strategy_path = Path(args.strategy).resolve()
    csv_path = get_results_csv_path(strategy_path)
    
    try:
        logger = ResultsLogger(csv_path)
        logger.log_result(
            result=result,
            iteration=1,
            status=status,
            meets_criteria=all_criteria_passed,
            analysis_summary="Initial backtest run"
        )
        print()
        print(f"📁 HTM Report: {report_path}")
        print(f"📁 CSV Updated: {csv_path}")
    except Exception as e:
        print(f"⚠️  Warning: Failed to save to CSV: {e}")
        print()
        print(f"📁 HTM Report: {report_path}")
    
    # Return appropriate exit code
    return 0 if all_criteria_passed else 1


if __name__ == "__main__":
    sys.exit(main())
