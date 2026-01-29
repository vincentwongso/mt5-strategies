"""
MT5 Strategy Tester Configuration
"""
from pathlib import Path
from dataclasses import dataclass, field
from typing import Optional

@dataclass
class MT5Config:
    """MetaTrader 5 paths and settings"""
    mt5_path: Path = Path(r"C:\Program Files\MetaTrader 5\terminal64.exe")
    metaeditor_path: Path = Path(r"C:\Program Files\MetaTrader 5\metaeditor64.exe")
    experts_path: Path = Path(r"C:\Users\{username}\AppData\Roaming\MetaQuotes\Terminal\{terminal_id}\MQL5\Experts")
    reports_path: Path = Path(r"C:\Users\{username}\AppData\Roaming\MetaQuotes\Terminal\{terminal_id}\reports")
    tester_ini_path: Path = Path(r"C:\Users\{username}\AppData\Roaming\MetaQuotes\Terminal\{terminal_id}\tester")
    
    # You'll need to set these for your specific installation
    terminal_id: str = "D0E8209F77C8CF37AD8BF550E51FF075"  # Found in MT5 data folder
    
    def resolve_paths(self, username: str):
        """Resolve paths with actual username"""
        self.experts_path = Path(str(self.experts_path).format(username=username, terminal_id=self.terminal_id))
        self.reports_path = Path(str(self.reports_path).format(username=username, terminal_id=self.terminal_id))
        self.tester_ini_path = Path(str(self.tester_ini_path).format(username=username, terminal_id=self.terminal_id))


@dataclass
class BacktestConfig:
    """Backtest parameters"""
    symbol: str = "EURUSD"
    period: str = "H1"  # M1, M5, M15, M30, H1, H4, D1, W1, MN
    from_date: str = "2024.01.01"
    to_date: str = "2024.12.31"
    deposit: float = 100000.0
    currency: str = "USD"
    leverage: int = 100
    model: int = 1  # 0=Every tick, 1=1 minute OHLC, 2=Open prices only, 3=Math calculations, 4=Every tick based on real ticks
    optimization: int = 0  # 0=Disabled, 1=Slow complete, 2=Fast genetic
    visual: bool = False
    

@dataclass 
class SuccessCriteria:
    """Criteria to determine if a strategy is profitable"""
    min_monthly_profit_pct: float = 3.0  # Minimum 3% per month
    max_monthly_profit_pct: float = 5.0  # Target 5% per month
    max_daily_drawdown_pct: float = 3.0  # Max 3% daily drawdown
    max_total_drawdown_pct: float = 10.0  # Max 10% total drawdown
    min_profit_factor: float = 1.5  # Minimum profit factor
    min_trades: int = 30  # Minimum trades for statistical significance
    min_win_rate: float = 40.0  # Minimum win rate percentage


@dataclass
class OptimizationConfig:
    """Optimization loop settings"""
    max_iterations: int = 3
    strategies_folder: Path = Path("./strategies")
    results_csv: Path = Path("./results/backtest_results.csv")
    modified_strategies_folder: Path = Path("./strategies/modified")
    

@dataclass
class CrewAIConfig:
    """CrewAI agent settings"""
    anthropic_api_key: str = ""  # Set via environment variable ANTHROPIC_API_KEY
    model: str = "claude-sonnet-4-20250514"
    temperature: float = 0.3
    max_tokens: int = 8000


@dataclass
class AppConfig:
    """Main application configuration"""
    mt5: MT5Config = field(default_factory=MT5Config)
    backtest: BacktestConfig = field(default_factory=BacktestConfig)
    success: SuccessCriteria = field(default_factory=SuccessCriteria)
    optimization: OptimizationConfig = field(default_factory=OptimizationConfig)
    crewai: CrewAIConfig = field(default_factory=CrewAIConfig)
    
    def __post_init__(self):
        # Create necessary directories
        self.optimization.strategies_folder.mkdir(parents=True, exist_ok=True)
        self.optimization.modified_strategies_folder.mkdir(parents=True, exist_ok=True)
        self.optimization.results_csv.parent.mkdir(parents=True, exist_ok=True)
