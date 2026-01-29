"""
Data models for MT5 Strategy Tester
"""
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional, List, Dict, Any
from enum import Enum


class StrategyStatus(Enum):
    """Status of strategy in the testing pipeline"""
    PENDING = "pending"
    TESTING = "testing"
    OPTIMIZING = "optimizing"
    PROFITABLE = "profitable"
    UNPROFITABLE = "unprofitable"
    FAILED = "failed"


class OptimizationAction(Enum):
    """Types of modifications the LLM can make"""
    ADJUST_PARAMETERS = "adjust_parameters"
    MODIFY_ENTRY_LOGIC = "modify_entry_logic"
    MODIFY_EXIT_LOGIC = "modify_exit_logic"
    ADD_FILTER = "add_filter"
    REMOVE_FILTER = "remove_filter"
    ADJUST_RISK_MANAGEMENT = "adjust_risk_management"


@dataclass
class TradeStats:
    """Individual trade statistics from backtest"""
    total_trades: int = 0
    winning_trades: int = 0
    losing_trades: int = 0
    win_rate: float = 0.0
    avg_win: float = 0.0
    avg_loss: float = 0.0
    largest_win: float = 0.0
    largest_loss: float = 0.0
    avg_trade_duration: float = 0.0  # in hours
    consecutive_wins: int = 0
    consecutive_losses: int = 0


@dataclass
class DrawdownStats:
    """Drawdown statistics"""
    max_drawdown_pct: float = 0.0
    max_drawdown_abs: float = 0.0
    avg_drawdown_pct: float = 0.0
    max_daily_drawdown_pct: float = 0.0
    drawdown_duration_days: int = 0


@dataclass
class PerformanceMetrics:
    """Overall performance metrics"""
    net_profit: float = 0.0
    gross_profit: float = 0.0
    gross_loss: float = 0.0
    profit_factor: float = 0.0
    expected_payoff: float = 0.0
    sharpe_ratio: float = 0.0
    sortino_ratio: float = 0.0
    recovery_factor: float = 0.0
    total_return_pct: float = 0.0
    monthly_return_pct: float = 0.0
    annual_return_pct: float = 0.0


@dataclass
class BacktestResult:
    """Complete backtest result from MT5"""
    strategy_name: str
    symbol: str
    timeframe: str
    from_date: str
    to_date: str
    initial_deposit: float
    final_balance: float
    
    # Aggregated stats
    performance: PerformanceMetrics = field(default_factory=PerformanceMetrics)
    trades: TradeStats = field(default_factory=TradeStats)
    drawdown: DrawdownStats = field(default_factory=DrawdownStats)
    
    # Raw data
    raw_xml: str = ""
    parameters: Dict[str, Any] = field(default_factory=dict)
    
    # Metadata
    test_date: datetime = field(default_factory=datetime.now)
    iteration: int = 1
    
    def to_csv_row(self) -> Dict[str, Any]:
        """Convert to flat dictionary for CSV export"""
        return {
            "strategy_name": self.strategy_name,
            "symbol": self.symbol,
            "timeframe": self.timeframe,
            "from_date": self.from_date,
            "to_date": self.to_date,
            "initial_deposit": self.initial_deposit,
            "final_balance": self.final_balance,
            "net_profit": self.performance.net_profit,
            "profit_factor": self.performance.profit_factor,
            "monthly_return_pct": self.performance.monthly_return_pct,
            "total_trades": self.trades.total_trades,
            "win_rate": self.trades.win_rate,
            "max_drawdown_pct": self.drawdown.max_drawdown_pct,
            "max_daily_drawdown_pct": self.drawdown.max_daily_drawdown_pct,
            "sharpe_ratio": self.performance.sharpe_ratio,
            "test_date": self.test_date.isoformat(),
            "iteration": self.iteration,
        }


@dataclass
class LLMAnalysis:
    """LLM's analysis of backtest results"""
    summary: str = ""
    strengths: List[str] = field(default_factory=list)
    weaknesses: List[str] = field(default_factory=list)
    recommended_actions: List[OptimizationAction] = field(default_factory=list)
    specific_changes: List[str] = field(default_factory=list)
    confidence_score: float = 0.0  # 0-1 confidence in recommendations
    should_continue: bool = True  # Whether to continue optimizing
    reasoning: str = ""


@dataclass
class CodeModification:
    """Details of code modification made by LLM"""
    action: OptimizationAction
    description: str
    original_code: str
    modified_code: str
    line_numbers: tuple = (0, 0)  # Start, end line numbers affected


@dataclass
class StrategyIteration:
    """Single iteration of strategy testing and optimization"""
    iteration_number: int
    strategy_code: str
    backtest_result: Optional[BacktestResult] = None
    llm_analysis: Optional[LLMAnalysis] = None
    modifications: List[CodeModification] = field(default_factory=list)
    timestamp: datetime = field(default_factory=datetime.now)


@dataclass
class StrategyTestingSession:
    """Complete testing session for a strategy"""
    strategy_name: str
    original_file_path: str
    original_code: str
    status: StrategyStatus = StrategyStatus.PENDING
    iterations: List[StrategyIteration] = field(default_factory=list)
    final_result: Optional[BacktestResult] = None
    started_at: datetime = field(default_factory=datetime.now)
    completed_at: Optional[datetime] = None
    
    @property
    def current_iteration(self) -> int:
        return len(self.iterations)
    
    @property
    def is_profitable(self) -> bool:
        if self.final_result is None:
            return False
        return self.status == StrategyStatus.PROFITABLE
    
    def add_iteration(self, iteration: StrategyIteration):
        self.iterations.append(iteration)
    
    def get_latest_code(self) -> str:
        """Get the most recent version of the strategy code"""
        if not self.iterations:
            return self.original_code
        # Return the modified code from the last iteration if available
        last_iter = self.iterations[-1]
        if last_iter.modifications:
            return last_iter.modifications[-1].modified_code
        return last_iter.strategy_code


@dataclass
class StrategyQueue:
    """Queue of strategies to test"""
    strategies: List[str] = field(default_factory=list)  # File paths
    current_index: int = 0
    completed: List[StrategyTestingSession] = field(default_factory=list)
    
    def add_strategy(self, file_path: str):
        self.strategies.append(file_path)
    
    def get_next(self) -> Optional[str]:
        if self.current_index < len(self.strategies):
            strategy = self.strategies[self.current_index]
            self.current_index += 1
            return strategy
        return None
    
    def mark_completed(self, session: StrategyTestingSession):
        self.completed.append(session)
    
    @property
    def remaining(self) -> int:
        return len(self.strategies) - self.current_index
    
    @property
    def profitable_strategies(self) -> List[StrategyTestingSession]:
        return [s for s in self.completed if s.is_profitable]
