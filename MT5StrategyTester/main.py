"""
MT5 Strategy Tester - Main Orchestrator

This is the main entry point that coordinates:
1. Loading strategies from the queue
2. Running backtests via MT5
3. Analyzing results with CrewAI
4. Modifying code based on analysis
5. Repeating up to 3 iterations
6. Logging results and moving to next strategy
"""
import argparse
import sys
from pathlib import Path
from datetime import datetime
from typing import Optional, List
import glob

from config import AppConfig, MT5Config, BacktestConfig, SuccessCriteria, OptimizationConfig
from models import (
    StrategyQueue, StrategyTestingSession, StrategyIteration,
    StrategyStatus, BacktestResult, LLMAnalysis
)
from mt5_automation import MT5Automation, MockMT5Automation
from crewai_agents import StrategyOptimizationCrew
from logger import ResultsLogger, SessionLogger


class StrategyTesterOrchestrator:
    """Main orchestrator for the strategy testing pipeline"""
    
    def __init__(
        self, 
        config: AppConfig,
        use_mock: bool = False
    ):
        self.config = config
        self.criteria = config.success
        
        # Initialize components
        if use_mock:
            self.mt5 = MockMT5Automation(config)
            print("⚠️  Using MOCK MT5 automation (no real backtests)")
        else:
            self.mt5 = MT5Automation(config)
        
        self.crew = StrategyOptimizationCrew(config)
        self.results_logger = ResultsLogger(config.optimization.results_csv)
        self.session_logger = SessionLogger(
            config.optimization.results_csv.parent / "sessions"
        )
        
        self.queue = StrategyQueue()
    
    def load_strategies(self, folder: Optional[Path] = None) -> int:
        """
        Load MQ5 strategies from folder into queue
        
        Args:
            folder: Path to strategies folder (uses config default if None)
            
        Returns:
            Number of strategies loaded
        """
        folder = folder or self.config.optimization.strategies_folder
        
        # Find all .mq5 files
        mq5_files = list(folder.glob("*.mq5"))
        
        for mq5_file in mq5_files:
            self.queue.add_strategy(str(mq5_file))
        
        print(f"📂 Loaded {len(mq5_files)} strategies from {folder}")
        return len(mq5_files)
    
    def check_criteria(self, result: BacktestResult) -> tuple[bool, List[str]]:
        """
        Check if backtest result meets success criteria
        
        Returns:
            tuple: (meets_criteria: bool, list of failed criteria)
        """
        failed = []
        
        if result.performance.monthly_return_pct < self.criteria.min_monthly_profit_pct:
            failed.append(
                f"Monthly return {result.performance.monthly_return_pct:.2f}% "
                f"< {self.criteria.min_monthly_profit_pct}%"
            )
        
        if result.drawdown.max_daily_drawdown_pct > self.criteria.max_daily_drawdown_pct:
            failed.append(
                f"Daily drawdown {result.drawdown.max_daily_drawdown_pct:.2f}% "
                f"> {self.criteria.max_daily_drawdown_pct}%"
            )
        
        if result.drawdown.max_drawdown_pct > self.criteria.max_total_drawdown_pct:
            failed.append(
                f"Total drawdown {result.drawdown.max_drawdown_pct:.2f}% "
                f"> {self.criteria.max_total_drawdown_pct}%"
            )
        
        if result.performance.profit_factor < self.criteria.min_profit_factor:
            failed.append(
                f"Profit factor {result.performance.profit_factor:.2f} "
                f"< {self.criteria.min_profit_factor}"
            )
        
        if result.trades.total_trades < self.criteria.min_trades:
            failed.append(
                f"Total trades {result.trades.total_trades} "
                f"< {self.criteria.min_trades}"
            )
        
        return len(failed) == 0, failed
    
    def run_iteration(
        self, 
        session: StrategyTestingSession,
        code: str,
        iteration: int
    ) -> tuple[Optional[BacktestResult], Optional[LLMAnalysis], str]:
        """
        Run a single optimization iteration
        
        Args:
            session: Current testing session
            code: MQL5 code to test
            iteration: Iteration number (1-3)
            
        Returns:
            tuple: (BacktestResult, LLMAnalysis, modified_code)
        """
        print(f"\n{'='*60}")
        print(f"🔄 Iteration {iteration}/{self.config.optimization.max_iterations}")
        print(f"   Strategy: {session.strategy_name}")
        print(f"{'='*60}")
        
        # Save current code to file for compilation
        temp_file = (
            self.config.optimization.modified_strategies_folder / 
            f"{session.strategy_name}_v{iteration}.mq5"
        )
        temp_file.parent.mkdir(parents=True, exist_ok=True)
        temp_file.write_text(code, encoding='utf-8')
        
        # Step 1: Run backtest
        print("\n📊 Running backtest...")
        success, result, msg = self.mt5.full_backtest_cycle(temp_file)
        
        if not success:
            print(f"❌ Backtest failed: {msg}")
            return None, None, code
        
        # Display results
        self._print_results(result)
        
        # Check criteria
        meets_criteria, failed = self.check_criteria(result)
        
        if meets_criteria:
            print("\n✅ Strategy MEETS all success criteria!")
            return result, None, code
        
        print(f"\n⚠️  Strategy does not meet {len(failed)} criteria:")
        for f in failed:
            print(f"   - {f}")
        
        # Step 2: Analyze with CrewAI (if not final iteration)
        if iteration >= self.config.optimization.max_iterations:
            print("\n🛑 Maximum iterations reached")
            return result, None, code
        
        print("\n🤖 Analyzing with CrewAI agents...")
        analysis = self.crew.analyze_results(result, code, iteration)
        
        print(f"\n📋 Analysis Summary:")
        print(f"   {analysis.summary[:200]}...")
        print(f"   Confidence: {analysis.confidence_score:.0%}")
        print(f"   Continue: {'Yes' if analysis.should_continue else 'No'}")
        
        if not analysis.should_continue:
            print("\n🚫 CrewAI recommends abandoning this strategy")
            return result, analysis, code
        
        # Step 3: Modify code based on analysis
        print("\n🔧 Modifying strategy code...")
        modified_code, modifications = self.crew.modify_code(code, analysis, result)
        
        print(f"   Made {len(modifications)} modifications:")
        for mod in modifications[:5]:
            print(f"   - {mod.description[:80]}")
        
        # Log this iteration
        self.session_logger.log_iteration(
            session,
            iteration,
            code,
            result,
            analysis.summary,
            [m.description for m in modifications]
        )
        
        return result, analysis, modified_code
    
    def test_strategy(self, strategy_path: str) -> StrategyTestingSession:
        """
        Test a single strategy through the optimization loop
        
        Args:
            strategy_path: Path to MQ5 file
            
        Returns:
            StrategyTestingSession with results
        """
        mq5_file = Path(strategy_path)
        
        # Create session
        session = StrategyTestingSession(
            strategy_name=mq5_file.stem,
            original_file_path=str(mq5_file),
            original_code=mq5_file.read_text(encoding='utf-8'),
            status=StrategyStatus.TESTING
        )
        
        print(f"\n{'#'*60}")
        print(f"# Starting test: {session.strategy_name}")
        print(f"{'#'*60}")
        
        current_code = session.original_code
        
        # Run optimization iterations
        for iteration in range(1, self.config.optimization.max_iterations + 1):
            session.status = StrategyStatus.OPTIMIZING
            
            result, analysis, modified_code = self.run_iteration(
                session, current_code, iteration
            )
            
            # Create iteration record
            iter_record = StrategyIteration(
                iteration_number=iteration,
                strategy_code=current_code,
                backtest_result=result,
                llm_analysis=analysis,
            )
            session.add_iteration(iter_record)
            
            # Log result
            if result:
                meets, _ = self.check_criteria(result)
                self.results_logger.log_result(
                    result,
                    iteration,
                    session.status,
                    meets,
                    analysis.summary if analysis else ""
                )
            
            # Check if we should continue
            if result is None:
                session.status = StrategyStatus.FAILED
                break
            
            meets_criteria, _ = self.check_criteria(result)
            if meets_criteria:
                session.status = StrategyStatus.PROFITABLE
                session.final_result = result
                break
            
            if analysis and not analysis.should_continue:
                session.status = StrategyStatus.UNPROFITABLE
                session.final_result = result
                break
            
            # Prepare for next iteration
            current_code = modified_code
        
        # Finalize session
        if session.status not in [StrategyStatus.PROFITABLE, StrategyStatus.UNPROFITABLE, StrategyStatus.FAILED]:
            session.status = StrategyStatus.UNPROFITABLE
            if session.iterations:
                session.final_result = session.iterations[-1].backtest_result
        
        session.completed_at = datetime.now()
        
        # Print final status
        self._print_session_summary(session)
        
        return session
    
    def run_queue(self) -> List[StrategyTestingSession]:
        """
        Process all strategies in the queue
        
        Returns:
            List of completed StrategyTestingSessions
        """
        print(f"\n{'='*60}")
        print(f"🚀 Starting queue processing")
        print(f"   Strategies: {len(self.queue.strategies)}")
        print(f"   Max iterations: {self.config.optimization.max_iterations}")
        print(f"{'='*60}")
        
        completed = []
        
        while True:
            strategy_path = self.queue.get_next()
            if strategy_path is None:
                break
            
            print(f"\n📈 Progress: {self.queue.current_index}/{len(self.queue.strategies)}")
            
            try:
                session = self.test_strategy(strategy_path)
                completed.append(session)
                self.queue.mark_completed(session)
            except Exception as e:
                print(f"❌ Error testing {strategy_path}: {e}")
                import traceback
                traceback.print_exc()
        
        # Print final summary
        self._print_final_summary(completed)
        
        return completed
    
    def _print_results(self, result: BacktestResult):
        """Print backtest results in a formatted way"""
        print(f"\n📈 Backtest Results:")
        print(f"   Net Profit:     ${result.performance.net_profit:,.2f}")
        print(f"   Monthly Return: {result.performance.monthly_return_pct:.2f}%")
        print(f"   Profit Factor:  {result.performance.profit_factor:.2f}")
        print(f"   Total Trades:   {result.trades.total_trades}")
        print(f"   Win Rate:       {result.trades.win_rate:.1f}%")
        print(f"   Max Drawdown:   {result.drawdown.max_drawdown_pct:.2f}%")
        print(f"   Sharpe Ratio:   {result.performance.sharpe_ratio:.2f}")
    
    def _print_session_summary(self, session: StrategyTestingSession):
        """Print session summary"""
        status_emoji = {
            StrategyStatus.PROFITABLE: "✅",
            StrategyStatus.UNPROFITABLE: "❌",
            StrategyStatus.FAILED: "💥",
        }.get(session.status, "❓")
        
        print(f"\n{'='*60}")
        print(f"{status_emoji} Session Complete: {session.strategy_name}")
        print(f"   Status: {session.status.value}")
        print(f"   Iterations: {session.current_iteration}")
        
        if session.final_result:
            print(f"   Final Monthly Return: {session.final_result.performance.monthly_return_pct:.2f}%")
            print(f"   Final Max Drawdown: {session.final_result.drawdown.max_drawdown_pct:.2f}%")
        print(f"{'='*60}")
    
    def _print_final_summary(self, sessions: List[StrategyTestingSession]):
        """Print final summary of all tested strategies"""
        profitable = [s for s in sessions if s.status == StrategyStatus.PROFITABLE]
        unprofitable = [s for s in sessions if s.status == StrategyStatus.UNPROFITABLE]
        failed = [s for s in sessions if s.status == StrategyStatus.FAILED]
        
        print(f"\n{'#'*60}")
        print(f"# FINAL SUMMARY")
        print(f"{'#'*60}")
        print(f"\n📊 Results Overview:")
        print(f"   Total Strategies: {len(sessions)}")
        print(f"   ✅ Profitable:    {len(profitable)}")
        print(f"   ❌ Unprofitable:  {len(unprofitable)}")
        print(f"   💥 Failed:        {len(failed)}")
        
        if profitable:
            print(f"\n🏆 Profitable Strategies:")
            for s in profitable:
                if s.final_result:
                    print(f"   - {s.strategy_name}: "
                          f"{s.final_result.performance.monthly_return_pct:.2f}% monthly")
        
        print(f"\n📁 Results saved to: {self.config.optimization.results_csv}")


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description="MT5 Strategy Tester with AI-powered optimization"
    )
    parser.add_argument(
        "--strategies", "-s",
        type=str,
        default="./strategies",
        help="Path to strategies folder"
    )
    parser.add_argument(
        "--symbol",
        type=str,
        default="EURUSD",
        help="Trading symbol (default: EURUSD)"
    )
    parser.add_argument(
        "--timeframe",
        type=str,
        default="H1",
        help="Timeframe (default: H1)"
    )
    parser.add_argument(
        "--from-date",
        type=str,
        default="2024.01.01",
        help="Backtest start date (default: 2024.01.01)"
    )
    parser.add_argument(
        "--to-date",
        type=str,
        default="2024.12.31",
        help="Backtest end date (default: 2024.12.31)"
    )
    parser.add_argument(
        "--deposit",
        type=float,
        default=100000,
        help="Initial deposit (default: 100000)"
    )
    parser.add_argument(
        "--max-iterations",
        type=int,
        default=3,
        help="Maximum optimization iterations per strategy (default: 3)"
    )
    parser.add_argument(
        "--mock",
        action="store_true",
        help="Use mock MT5 automation for testing"
    )
    parser.add_argument(
        "--single",
        type=str,
        help="Test a single strategy file instead of queue"
    )
    parser.add_argument(
        "--mt5-path",
        type=str,
        default=r"C:\Program Files\MetaTrader 5\terminal64.exe",
        help="Path to MT5 terminal"
    )
    parser.add_argument(
        "--terminal-id",
        type=str,
        default="",
        help="MT5 terminal ID (from data folder name)"
    )
    
    args = parser.parse_args()
    
    # Build configuration
    config = AppConfig()
    
    # Update paths
    config.optimization.strategies_folder = Path(args.strategies)
    config.mt5.mt5_path = Path(args.mt5_path)
    if args.terminal_id:
        config.mt5.terminal_id = args.terminal_id
    
    # Update backtest params
    config.backtest.symbol = args.symbol
    config.backtest.period = args.timeframe
    config.backtest.from_date = args.from_date
    config.backtest.to_date = args.to_date
    config.backtest.deposit = args.deposit
    
    # Update optimization params
    config.optimization.max_iterations = args.max_iterations
    
    # Create orchestrator
    orchestrator = StrategyTesterOrchestrator(config, use_mock=args.mock)
    
    # Run
    if args.single:
        # Test single strategy
        session = orchestrator.test_strategy(args.single)
        sys.exit(0 if session.is_profitable else 1)
    else:
        # Process queue
        orchestrator.load_strategies()
        sessions = orchestrator.run_queue()
        
        # Exit with success if any profitable
        profitable = [s for s in sessions if s.is_profitable]
        sys.exit(0 if profitable else 1)


if __name__ == "__main__":
    main()
