"""
CSV Logger for MT5 Strategy Tester Results
"""
import csv
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Any, Optional

from models import BacktestResult, StrategyTestingSession, StrategyStatus


class ResultsLogger:
    """Logs backtest results to CSV"""
    
    def __init__(self, csv_path: Path):
        self.csv_path = csv_path
        self.csv_path.parent.mkdir(parents=True, exist_ok=True)
        self._ensure_headers()
    
    def _ensure_headers(self):
        """Ensure CSV file exists with headers"""
        if not self.csv_path.exists():
            headers = [
                "timestamp",
                "strategy_name",
                "iteration",
                "status",
                "symbol",
                "timeframe",
                "from_date",
                "to_date",
                "initial_deposit",
                "final_balance",
                "net_profit",
                "profit_factor",
                "monthly_return_pct",
                "annual_return_pct",
                "total_trades",
                "win_rate",
                "avg_win",
                "avg_loss",
                "max_drawdown_pct",
                "max_daily_drawdown_pct",
                "sharpe_ratio",
                "recovery_factor",
                "meets_criteria",
                "analysis_summary",
            ]
            with open(self.csv_path, 'w', newline='', encoding='utf-8') as f:
                writer = csv.writer(f)
                writer.writerow(headers)
    
    def log_result(
        self, 
        result: BacktestResult, 
        iteration: int,
        status: StrategyStatus,
        meets_criteria: bool,
        analysis_summary: str = ""
    ):
        """Log a single backtest result"""
        row = [
            datetime.now().isoformat(),
            result.strategy_name,
            iteration,
            status.value,
            result.symbol,
            result.timeframe,
            result.from_date,
            result.to_date,
            result.initial_deposit,
            result.final_balance,
            round(result.performance.net_profit, 2),
            round(result.performance.profit_factor, 2),
            round(result.performance.monthly_return_pct, 2),
            round(result.performance.annual_return_pct, 2),
            result.trades.total_trades,
            round(result.trades.win_rate, 2),
            round(result.trades.avg_win, 2),
            round(result.trades.avg_loss, 2),
            round(result.drawdown.max_drawdown_pct, 2),
            round(result.drawdown.max_daily_drawdown_pct, 2),
            round(result.performance.sharpe_ratio, 2),
            round(result.performance.recovery_factor, 2),
            meets_criteria,
            analysis_summary[:200],  # Truncate summary
        ]
        
        with open(self.csv_path, 'a', newline='', encoding='utf-8') as f:
            writer = csv.writer(f)
            writer.writerow(row)
    
    def log_session(self, session: StrategyTestingSession):
        """Log all iterations from a testing session"""
        for iteration in session.iterations:
            if iteration.backtest_result:
                meets = self._check_criteria(iteration.backtest_result)
                summary = iteration.llm_analysis.summary if iteration.llm_analysis else ""
                self.log_result(
                    iteration.backtest_result,
                    iteration.iteration_number,
                    session.status,
                    meets,
                    summary
                )
    
    def _check_criteria(self, result: BacktestResult) -> bool:
        """Quick check if result meets basic criteria"""
        return (
            result.performance.monthly_return_pct >= 3.0 and
            result.drawdown.max_drawdown_pct <= 10.0 and
            result.performance.profit_factor >= 1.5
        )
    
    def get_summary_stats(self) -> Dict[str, Any]:
        """Get summary statistics from logged results"""
        if not self.csv_path.exists():
            return {}
        
        stats = {
            "total_strategies": 0,
            "profitable_strategies": 0,
            "total_iterations": 0,
            "avg_iterations_per_strategy": 0,
            "best_monthly_return": 0,
            "best_strategy": "",
        }
        
        strategies = set()
        profitable = set()
        total_rows = 0
        
        with open(self.csv_path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                total_rows += 1
                strategies.add(row['strategy_name'])
                
                if row['meets_criteria'] == 'True':
                    profitable.add(row['strategy_name'])
                
                monthly_ret = float(row['monthly_return_pct'])
                if monthly_ret > stats['best_monthly_return']:
                    stats['best_monthly_return'] = monthly_ret
                    stats['best_strategy'] = row['strategy_name']
        
        stats['total_strategies'] = len(strategies)
        stats['profitable_strategies'] = len(profitable)
        stats['total_iterations'] = total_rows
        if len(strategies) > 0:
            stats['avg_iterations_per_strategy'] = total_rows / len(strategies)
        
        return stats


class SessionLogger:
    """Detailed logging for debugging and audit"""
    
    def __init__(self, log_dir: Path):
        self.log_dir = log_dir
        self.log_dir.mkdir(parents=True, exist_ok=True)
    
    def log_iteration(
        self, 
        session: StrategyTestingSession,
        iteration: int,
        code: str,
        result: Optional[BacktestResult],
        analysis_text: str,
        modifications: List[str]
    ):
        """Log detailed iteration data"""
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        session_dir = self.log_dir / session.strategy_name
        session_dir.mkdir(parents=True, exist_ok=True)
        
        # Save code version
        code_file = session_dir / f"iteration_{iteration}_code.mq5"
        code_file.write_text(code, encoding='utf-8')
        
        # Save analysis
        analysis_file = session_dir / f"iteration_{iteration}_analysis.txt"
        analysis_content = f"""
Strategy: {session.strategy_name}
Iteration: {iteration}
Timestamp: {timestamp}

=== BACKTEST RESULTS ===
{self._format_result(result) if result else "No results"}

=== LLM ANALYSIS ===
{analysis_text}

=== MODIFICATIONS MADE ===
{chr(10).join(modifications) if modifications else "None"}
"""
        analysis_file.write_text(analysis_content, encoding='utf-8')
    
    def _format_result(self, result: BacktestResult) -> str:
        """Format backtest result for logging"""
        return f"""
Net Profit: ${result.performance.net_profit:.2f}
Monthly Return: {result.performance.monthly_return_pct:.2f}%
Profit Factor: {result.performance.profit_factor:.2f}
Total Trades: {result.trades.total_trades}
Win Rate: {result.trades.win_rate:.1f}%
Max Drawdown: {result.drawdown.max_drawdown_pct:.2f}%
Sharpe Ratio: {result.performance.sharpe_ratio:.2f}
"""
