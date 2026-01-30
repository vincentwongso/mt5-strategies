"""
MT5 Strategy Tester Configuration Loader

Loads configuration from config.yaml and provides dataclass-based access.
"""
from pathlib import Path
from dataclasses import dataclass, field
from typing import Optional
import yaml
import os
import getpass


@dataclass
class MT5Config:
    """MetaTrader 5 paths and settings"""
    mt5_path: Path = Path(r"C:\Program Files\MetaTrader 5\terminal64.exe")
    metaeditor_path: Path = Path(r"C:\Program Files\MetaTrader 5\metaeditor64.exe")
    username: Optional[str] = None
    login: Optional[str] = None
    password: Optional[str] = None
    server: Optional[str] = None
    experts_path: Path = Path(r"C:\Users\{username}\AppData\Roaming\MetaQuotes\Terminal\{terminal_id}\MQL5\Experts")
    reports_path: Path = Path(r"C:\Users\{username}\AppData\Roaming\MetaQuotes\Terminal\{terminal_id}\reports")
    tester_ini_path: Path = Path(r"C:\Users\{username}\AppData\Roaming\MetaQuotes\Terminal\{terminal_id}\tester")
    terminal_id: str = "D0E8209F77C8CF37AD8BF550E51FF075"

    def resolve_paths(self, username: str):
        """Resolve paths with actual username"""
        self.experts_path = Path(str(self.experts_path).format(username=username, terminal_id=self.terminal_id))
        self.reports_path = Path(str(self.reports_path).format(username=username, terminal_id=self.terminal_id))
        self.tester_ini_path = Path(str(self.tester_ini_path).format(username=username, terminal_id=self.terminal_id))


@dataclass
class BacktestConfig:
    """Backtest parameters"""
    symbol: str = "EURUSD"
    period: str = "H1"
    from_date: str = "2024.01.01"
    to_date: str = "2024.12.31"
    deposit: float = 100000.0
    currency: str = "USD"
    leverage: int = 100
    delays: int = 0  # Execution delays in milliseconds (0=ideal, 100=realistic)
    model: int = 1
    optimization: int = 0
    visual: bool = False
    report_format: str = "xml"


@dataclass
class SuccessCriteria:
    """Criteria to determine if a strategy is profitable"""
    min_monthly_profit_pct: float = 3.0
    max_monthly_profit_pct: float = 5.0
    max_daily_drawdown_pct: float = 3.0
    max_total_drawdown_pct: float = 10.0
    min_profit_factor: float = 1.5
    min_trades: int = 30
    min_win_rate: float = 40.0


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
    anthropic_api_key: str = ""
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


def load_config(config_path: Optional[Path] = None) -> AppConfig:
    """
    Load configuration from YAML file.

    Args:
        config_path: Path to the YAML config file. If None, looks for config.yaml in the same directory.

    Returns:
        AppConfig instance populated with values from YAML file
    """
    if config_path is None:
        config_path = Path(__file__).parent / "config.yaml"

    # Start with default config
    config = AppConfig()

    # If YAML file exists, load and override defaults
    if config_path.exists():
        with open(config_path, 'r', encoding='utf-8') as f:
            data = yaml.safe_load(f)

        if data:
            # Load MT5 config
            if 'mt5' in data:
                mt5_data = data['mt5']
                login_env = os.getenv("MT5_LOGIN")
                password_env = os.getenv("MT5_PASSWORD")
                server_env = os.getenv("MT5_SERVER")
                config.mt5 = MT5Config(
                    mt5_path=Path(mt5_data.get('mt5_path', config.mt5.mt5_path)),
                    metaeditor_path=Path(mt5_data.get('metaeditor_path', config.mt5.metaeditor_path)),
                    username=mt5_data.get('username', config.mt5.username),
                    login=login_env or mt5_data.get('login', config.mt5.login),
                    password=password_env or mt5_data.get('password', config.mt5.password),
                    server=server_env or mt5_data.get('server', config.mt5.server),
                    experts_path=Path(mt5_data.get('experts_path', config.mt5.experts_path)),
                    reports_path=Path(mt5_data.get('reports_path', config.mt5.reports_path)),
                    tester_ini_path=Path(mt5_data.get('tester_ini_path', config.mt5.tester_ini_path)),
                    terminal_id=mt5_data.get('terminal_id', config.mt5.terminal_id)
                )

            # Load Backtest config
            if 'backtest' in data:
                bt_data = data['backtest']
                config.backtest = BacktestConfig(
                    symbol=bt_data.get('symbol', config.backtest.symbol),
                    period=bt_data.get('period', config.backtest.period),
                    from_date=bt_data.get('from_date', config.backtest.from_date),
                    to_date=bt_data.get('to_date', config.backtest.to_date),
                    deposit=bt_data.get('deposit', config.backtest.deposit),
                    currency=bt_data.get('currency', config.backtest.currency),
                    leverage=bt_data.get('leverage', config.backtest.leverage),
                    delays=bt_data.get('delays', config.backtest.delays),
                    model=bt_data.get('model', config.backtest.model),
                    optimization=bt_data.get('optimization', config.backtest.optimization),
                    visual=bt_data.get('visual', config.backtest.visual),
                    report_format=bt_data.get('report_format', config.backtest.report_format)
                )

            # Load Success criteria
            if 'success' in data:
                sc_data = data['success']
                config.success = SuccessCriteria(
                    min_monthly_profit_pct=sc_data.get('min_monthly_profit_pct', config.success.min_monthly_profit_pct),
                    max_monthly_profit_pct=sc_data.get('max_monthly_profit_pct', config.success.max_monthly_profit_pct),
                    max_daily_drawdown_pct=sc_data.get('max_daily_drawdown_pct', config.success.max_daily_drawdown_pct),
                    max_total_drawdown_pct=sc_data.get('max_total_drawdown_pct', config.success.max_total_drawdown_pct),
                    min_profit_factor=sc_data.get('min_profit_factor', config.success.min_profit_factor),
                    min_trades=sc_data.get('min_trades', config.success.min_trades),
                    min_win_rate=sc_data.get('min_win_rate', config.success.min_win_rate)
                )

            # Load Optimization config
            if 'optimization' in data:
                opt_data = data['optimization']
                config.optimization = OptimizationConfig(
                    max_iterations=opt_data.get('max_iterations', config.optimization.max_iterations),
                    strategies_folder=Path(opt_data.get('strategies_folder', config.optimization.strategies_folder)),
                    results_csv=Path(opt_data.get('results_csv', config.optimization.results_csv)),
                    modified_strategies_folder=Path(opt_data.get('modified_strategies_folder', config.optimization.modified_strategies_folder))
                )

            # Load CrewAI config
            if 'crewai' in data:
                crew_data = data['crewai']
                # Check environment variable first for API key
                api_key = os.getenv("ANTHROPIC_API_KEY", crew_data.get('anthropic_api_key', config.crewai.anthropic_api_key))
                config.crewai = CrewAIConfig(
                    anthropic_api_key=api_key,
                    model=crew_data.get('model', config.crewai.model),
                    temperature=crew_data.get('temperature', config.crewai.temperature),
                    max_tokens=crew_data.get('max_tokens', config.crewai.max_tokens)
                )

    # Resolve MT5 paths with actual username/terminal_id
    username = config.mt5.username or getpass.getuser()
    config.mt5.resolve_paths(username)
    print(
        "[MT5] resolved paths: "
        f"experts_path={config.mt5.experts_path} "
        f"reports_path={config.mt5.reports_path} "
        f"tester_ini_path={config.mt5.tester_ini_path}"
    )
    print(
        "[MT5] backtest config: "
        f"symbol={config.backtest.symbol} period={config.backtest.period} "
        f"from={config.backtest.from_date} to={config.backtest.to_date}"
    )

    # Trigger post-init to create directories
    config.__post_init__()

    return config
