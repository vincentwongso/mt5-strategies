"""
MT5 Strategy Improvement Script

Reads backtest results and generates improved EA code using Anthropic API.
Usage: python improve_strategy.py --strategy <path_to_mq5_file> [--report <path_to_htm_report>]
"""
import argparse
import sys
import re
from pathlib import Path
from datetime import datetime
from typing import Optional

from dotenv import load_dotenv

from config_loader import load_config, AppConfig
from mt5_automation import MT5Automation
from anthropic_client import StrategyImprover
from models import BacktestResult


def parse_args():
    """Parse command-line arguments"""
    parser = argparse.ArgumentParser(
        description="Improve MT5 Strategy using AI"
    )
    parser.add_argument(
        "--strategy", "-s",
        type=str,
        required=True,
        help="Path to MQ5 strategy file"
    )
    parser.add_argument(
        "--report", "-r",
        type=str,
        default=None,
        help="Path to HTM report file (default: most recent in results folder)"
    )
    parser.add_argument(
        "--config", "-c",
        type=str,
        default=None,
        help="Path to config.yaml"
    )
    return parser.parse_args()


def find_latest_report(strategy_path: Path) -> Optional[Path]:
    """
    Find the most recent HTM report in the strategy's results folder.
    
    Args:
        strategy_path: Path to the MQ5 strategy file
        
    Returns:
        Path to the most recent HTM report, or None if not found
    """
    # Determine results folder (strategy_folder/results/)
    strategy_folder = strategy_path.parent
    results_folder = strategy_folder / "results"
    
    if not results_folder.exists():
        return None
    
    # Find all .htm files
    htm_files = list(results_folder.glob("*.htm")) + list(results_folder.glob("*.html"))
    
    if not htm_files:
        return None
    
    # Sort by modification time (most recent first)
    htm_files.sort(key=lambda f: f.stat().st_mtime, reverse=True)
    
    # Return the most recent one
    return htm_files[0]


def get_next_version_number(strategy_path: Path) -> int:
    """
    Determine the next version number for the improved strategy.
    
    Looks at existing files in the modified folder and returns the next version.
    E.g., if v1 and v2 exist, returns 3.
    
    Args:
        strategy_path: Path to the MQ5 strategy file
        
    Returns:
        Next version number (1 if no versions exist)
    """
    # Look in strategy_folder/modified/
    strategy_folder = strategy_path.parent
    modified_folder = strategy_folder / "modified"
    
    if not modified_folder.exists():
        return 1
    
    # Get strategy name without extension
    strategy_name = strategy_path.stem
    
    # Find files matching {strategy_name}_v*.mq5
    pattern = f"{strategy_name}_v*.mq5"
    existing_files = list(modified_folder.glob(pattern))
    
    if not existing_files:
        return 1
    
    # Extract version numbers using regex
    version_pattern = re.compile(rf"{re.escape(strategy_name)}_v(\d+)\.mq5$")
    versions = []
    
    for file in existing_files:
        match = version_pattern.match(file.name)
        if match:
            versions.append(int(match.group(1)))
    
    if not versions:
        return 1
    
    # Return max + 1
    return max(versions) + 1


def save_improved_code(
    strategy_path: Path,
    improved_code: str,
    version: int
) -> Path:
    """
    Save the improved code to the modified folder with version number.
    
    Args:
        strategy_path: Path to original MQ5 file
        improved_code: The improved MQL5 code
        version: Version number for the new file
        
    Returns:
        Path to the saved file
    """
    # Create modified folder if needed
    strategy_folder = strategy_path.parent
    modified_folder = strategy_folder / "modified"
    modified_folder.mkdir(parents=True, exist_ok=True)
    
    # Generate filename: {strategy_name}_v{version}.mq5
    strategy_name = strategy_path.stem
    output_filename = f"{strategy_name}_v{version}.mq5"
    output_path = modified_folder / output_filename
    
    # Write the code
    output_path.write_text(improved_code, encoding='utf-8')
    
    return output_path


def main():
    """Main entry point"""
    load_dotenv()
    args = parse_args()
    
    # Validate strategy file exists
    strategy_path = Path(args.strategy)
    if not strategy_path.exists():
        print(f"❌ Strategy file not found: {strategy_path}")
        sys.exit(1)
    
    # Find or validate report file
    if args.report:
        report_path = Path(args.report)
        if not report_path.exists():
            print(f"❌ Report file not found: {report_path}")
            sys.exit(1)
    else:
        report_path = find_latest_report(strategy_path)
        if report_path is None:
            print(f"❌ No HTM reports found in results folder")
            print(f"   Run a backtest first: python run_backtest.py --strategy {strategy_path}")
            sys.exit(1)
    
    # Load configuration
    config = load_config(Path(args.config) if args.config else None)
    
    # Parse HTM report
    print(f"📊 Loading backtest results from: {report_path}")
    mt5 = MT5Automation(config)
    result = mt5.parse_htm_report(report_path)
    
    if result is None:
        print(f"❌ Failed to parse HTM report")
        sys.exit(1)
    
    # Display current performance
    print(f"\n📈 Current Performance:")
    print(f"   Net Profit:     ${result.performance.net_profit:,.2f}")
    print(f"   Monthly Return: {result.performance.monthly_return_pct:.2f}%")
    print(f"   Profit Factor:  {result.performance.profit_factor:.2f}")
    print(f"   Total Trades:   {result.trades.total_trades}")
    print(f"   Win Rate:       {result.trades.win_rate:.1f}%")
    print(f"   Max Drawdown:   {result.drawdown.max_drawdown_pct:.2f}%")
    
    # Read original strategy code
    print(f"\n📖 Reading strategy code from: {strategy_path}")
    strategy_code = strategy_path.read_text(encoding='utf-8')
    
    # Call Anthropic API for improvement
    print(f"\n🤖 Calling Anthropic API for strategy improvement...")
    improver = StrategyImprover(config.anthropic, config.success)
    improved_code, summary = improver.improve_strategy(
        strategy_code,
        result,
        strategy_path.stem
    )
    
    # Check if improvement failed
    if summary.startswith("ERROR:"):
        print(f"\n❌ {summary}")
        sys.exit(1)
    
    # Display summary
    print(f"\n📝 Changes Summary:")
    for line in summary.split('\n')[:10]:  # First 10 lines
        if line.strip():
            print(f"   {line.strip()}")
    
    # Determine version number and save
    version = get_next_version_number(strategy_path)
    output_path = save_improved_code(strategy_path, improved_code, version)
    
    print(f"\n✅ Improved strategy saved to: {output_path}")
    print(f"\n💡 Next steps:")
    print(f"   1. Review the changes in the improved code")
    print(f"   2. Run a backtest: python run_backtest.py --strategy {output_path}")


if __name__ == "__main__":
    main()
