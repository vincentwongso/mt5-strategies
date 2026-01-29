"""
MT5 Strategy Tester Automation Module

Handles:
- Compiling MQ5 files using MetaEditor
- Generating tester INI configuration
- Running backtests via MT5 command line
- Parsing XML report results
"""
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path
from datetime import datetime
from typing import Optional, Dict, Any
import shutil
import time
import re

from config import MT5Config, BacktestConfig, AppConfig
from models import (
    BacktestResult, PerformanceMetrics, TradeStats, 
    DrawdownStats
)


class MT5Automation:
    """Automates MT5 Strategy Tester operations"""
    
    def __init__(self, config: AppConfig):
        self.config = config
        self.mt5 = config.mt5
        self.backtest = config.backtest
        
    def compile_strategy(self, mq5_file: Path) -> tuple[bool, str]:
        """
        Compile an MQ5 file using MetaEditor
        
        Returns:
            tuple: (success: bool, message: str)
        """
        if not mq5_file.exists():
            return False, f"File not found: {mq5_file}"
        
        # Copy to MT5 Experts folder if not already there
        target_path = self.mt5.experts_path / mq5_file.name
        if mq5_file != target_path:
            shutil.copy2(mq5_file, target_path)
        
        # Run MetaEditor compilation
        cmd = [
            str(self.mt5.metaeditor_path),
            "/compile:" + str(target_path),
            "/log"
        ]
        
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=60
            )
            
            # Check for compiled .ex5 file
            ex5_file = target_path.with_suffix('.ex5')
            if ex5_file.exists():
                return True, f"Successfully compiled: {ex5_file}"
            else:
                # Try to read log file for error details
                log_file = target_path.with_suffix('.log')
                error_msg = "Compilation failed"
                if log_file.exists():
                    error_msg = log_file.read_text(encoding='utf-16')
                return False, error_msg
                
        except subprocess.TimeoutExpired:
            return False, "Compilation timed out"
        except Exception as e:
            return False, f"Compilation error: {str(e)}"
    
    def generate_tester_ini(
        self, 
        strategy_name: str,
        output_path: Optional[Path] = None,
        custom_params: Optional[Dict[str, Any]] = None
    ) -> Path:
        """
        Generate tester.ini configuration file for MT5 backtesting
        
        Args:
            strategy_name: Name of the EA (without .ex5 extension)
            output_path: Custom path for INI file
            custom_params: Override default backtest parameters
            
        Returns:
            Path to generated INI file
        """
        params = self.backtest
        if custom_params:
            for key, value in custom_params.items():
                if hasattr(params, key):
                    setattr(params, key, value)
        
        report_name = f"{strategy_name}_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        report_path = self.mt5.reports_path / f"{report_name}.xml"
        
        # INI content for Strategy Tester
        ini_content = f"""[Tester]
Expert={strategy_name}
Symbol={params.symbol}
Period={params.period}
Deposit={params.deposit}
Currency={params.currency}
Leverage={params.leverage}
Model={params.model}
Optimization={params.optimization}
FromDate={params.from_date}
ToDate={params.to_date}
Report={report_path}
ReplaceReport=1
UseLocal=1
Visual={1 if params.visual else 0}
ShutdownTerminal=1
"""
        
        # Write INI file
        if output_path is None:
            output_path = self.mt5.tester_ini_path / "tester.ini"
        
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(ini_content, encoding='utf-8')
        
        return output_path, report_path
    
    def run_backtest(
        self, 
        strategy_name: str,
        wait_timeout: int = 300,
        custom_params: Optional[Dict[str, Any]] = None
    ) -> tuple[bool, Optional[Path], str]:
        """
        Run a backtest in MT5 Strategy Tester
        
        Args:
            strategy_name: Name of compiled EA
            wait_timeout: Maximum seconds to wait for backtest
            custom_params: Override backtest parameters
            
        Returns:
            tuple: (success, report_path, message)
        """
        # Generate INI configuration
        ini_path, report_path = self.generate_tester_ini(
            strategy_name, 
            custom_params=custom_params
        )
        
        # Run MT5 with tester config
        cmd = [
            str(self.mt5.mt5_path),
            f"/config:{ini_path}"
        ]
        
        try:
            # Start MT5 process
            process = subprocess.Popen(cmd)
            
            # Wait for report file to appear (indicates completion)
            start_time = time.time()
            while time.time() - start_time < wait_timeout:
                if report_path.exists():
                    # Give it a moment to finish writing
                    time.sleep(2)
                    if report_path.stat().st_size > 0:
                        return True, report_path, "Backtest completed successfully"
                time.sleep(5)
            
            # Timeout - kill process if still running
            process.terminate()
            return False, None, f"Backtest timed out after {wait_timeout} seconds"
            
        except Exception as e:
            return False, None, f"Backtest error: {str(e)}"
    
    def parse_xml_report(self, report_path: Path) -> Optional[BacktestResult]:
        """
        Parse MT5 XML report into BacktestResult
        
        Args:
            report_path: Path to XML report file
            
        Returns:
            BacktestResult object or None if parsing fails
        """
        if not report_path.exists():
            return None
            
        try:
            tree = ET.parse(report_path)
            root = tree.getroot()
            
            # Extract strategy info
            strategy_elem = root.find('.//Expert')
            strategy_name = strategy_elem.text if strategy_elem is not None else "Unknown"
            
            # Extract test settings
            settings = self._parse_settings(root)
            
            # Extract performance metrics
            performance = self._parse_performance(root)
            
            # Extract trade statistics
            trades = self._parse_trades(root)
            
            # Extract drawdown
            drawdown = self._parse_drawdown(root)
            
            # Get final balance
            balance_elem = root.find('.//Balance')
            final_balance = float(balance_elem.text) if balance_elem is not None else settings.get('deposit', 0)
            
            return BacktestResult(
                strategy_name=strategy_name,
                symbol=settings.get('symbol', self.backtest.symbol),
                timeframe=settings.get('period', self.backtest.period),
                from_date=settings.get('from_date', self.backtest.from_date),
                to_date=settings.get('to_date', self.backtest.to_date),
                initial_deposit=settings.get('deposit', self.backtest.deposit),
                final_balance=final_balance,
                performance=performance,
                trades=trades,
                drawdown=drawdown,
                raw_xml=report_path.read_text(encoding='utf-8'),
                parameters=self._parse_parameters(root)
            )
            
        except Exception as e:
            print(f"Error parsing XML report: {e}")
            return None
    
    def _parse_settings(self, root: ET.Element) -> Dict[str, Any]:
        """Parse test settings from XML"""
        settings = {}
        
        mappings = {
            'Symbol': 'symbol',
            'Period': 'period', 
            'FromDate': 'from_date',
            'ToDate': 'to_date',
            'Deposit': 'deposit',
        }
        
        for xml_name, key in mappings.items():
            elem = root.find(f'.//{xml_name}')
            if elem is not None:
                value = elem.text
                if key == 'deposit':
                    value = float(value)
                settings[key] = value
                
        return settings
    
    def _parse_performance(self, root: ET.Element) -> PerformanceMetrics:
        """Parse performance metrics from XML"""
        metrics = PerformanceMetrics()
        
        # Map XML element names to our fields
        mappings = {
            'Profit': 'net_profit',
            'GrossProfit': 'gross_profit',
            'GrossLoss': 'gross_loss',
            'ProfitFactor': 'profit_factor',
            'ExpectedPayoff': 'expected_payoff',
            'SharpeRatio': 'sharpe_ratio',
            'RecoveryFactor': 'recovery_factor',
        }
        
        for xml_name, attr in mappings.items():
            elem = root.find(f'.//{xml_name}')
            if elem is not None:
                try:
                    setattr(metrics, attr, float(elem.text))
                except (ValueError, TypeError):
                    pass
        
        # Calculate derived metrics
        deposit_elem = root.find('.//Deposit')
        deposit = float(deposit_elem.text) if deposit_elem is not None else self.backtest.deposit
        
        if deposit > 0 and metrics.net_profit != 0:
            metrics.total_return_pct = (metrics.net_profit / deposit) * 100
            
            # Calculate monthly return (approximate)
            from_elem = root.find('.//FromDate')
            to_elem = root.find('.//ToDate')
            if from_elem is not None and to_elem is not None:
                try:
                    from_date = datetime.strptime(from_elem.text, '%Y.%m.%d')
                    to_date = datetime.strptime(to_elem.text, '%Y.%m.%d')
                    months = max(1, (to_date - from_date).days / 30)
                    metrics.monthly_return_pct = metrics.total_return_pct / months
                    metrics.annual_return_pct = metrics.monthly_return_pct * 12
                except:
                    pass
        
        return metrics
    
    def _parse_trades(self, root: ET.Element) -> TradeStats:
        """Parse trade statistics from XML"""
        stats = TradeStats()
        
        mappings = {
            'TotalTrades': 'total_trades',
            'WinningTrades': 'winning_trades',
            'LosingTrades': 'losing_trades',
            'AverageProfit': 'avg_win',
            'AverageLoss': 'avg_loss',
            'LargestProfit': 'largest_win',
            'LargestLoss': 'largest_loss',
            'MaxConsecutiveWins': 'consecutive_wins',
            'MaxConsecutiveLosses': 'consecutive_losses',
        }
        
        for xml_name, attr in mappings.items():
            elem = root.find(f'.//{xml_name}')
            if elem is not None:
                try:
                    value = float(elem.text)
                    if attr in ['total_trades', 'winning_trades', 'losing_trades', 
                               'consecutive_wins', 'consecutive_losses']:
                        value = int(value)
                    setattr(stats, attr, value)
                except (ValueError, TypeError):
                    pass
        
        # Calculate win rate
        if stats.total_trades > 0:
            stats.win_rate = (stats.winning_trades / stats.total_trades) * 100
        
        return stats
    
    def _parse_drawdown(self, root: ET.Element) -> DrawdownStats:
        """Parse drawdown statistics from XML"""
        dd = DrawdownStats()
        
        mappings = {
            'MaxDrawdown': 'max_drawdown_abs',
            'MaxDrawdownPercent': 'max_drawdown_pct',
            'RelativeDrawdown': 'avg_drawdown_pct',
        }
        
        for xml_name, attr in mappings.items():
            elem = root.find(f'.//{xml_name}')
            if elem is not None:
                try:
                    value = float(elem.text)
                    # Convert to percentage if needed
                    if 'pct' in attr.lower() and value > 1:
                        value = value  # Already percentage
                    setattr(dd, attr, abs(value))
                except (ValueError, TypeError):
                    pass
        
        return dd
    
    def _parse_parameters(self, root: ET.Element) -> Dict[str, Any]:
        """Parse EA input parameters from XML"""
        params = {}
        
        inputs = root.find('.//Inputs')
        if inputs is not None:
            for param in inputs:
                name = param.get('name', param.tag)
                value = param.text
                # Try to convert to appropriate type
                try:
                    if '.' in value:
                        value = float(value)
                    else:
                        value = int(value)
                except (ValueError, TypeError):
                    pass
                params[name] = value
        
        return params
    
    def full_backtest_cycle(
        self, 
        mq5_file: Path,
        custom_params: Optional[Dict[str, Any]] = None
    ) -> tuple[bool, Optional[BacktestResult], str]:
        """
        Run complete backtest cycle: compile -> test -> parse results
        
        Args:
            mq5_file: Path to MQ5 source file
            custom_params: Override backtest parameters
            
        Returns:
            tuple: (success, BacktestResult or None, message)
        """
        strategy_name = mq5_file.stem
        
        # Step 1: Compile
        print(f"Compiling {strategy_name}...")
        success, msg = self.compile_strategy(mq5_file)
        if not success:
            return False, None, f"Compilation failed: {msg}"
        
        # Step 2: Run backtest
        print(f"Running backtest for {strategy_name}...")
        success, report_path, msg = self.run_backtest(
            strategy_name, 
            custom_params=custom_params
        )
        if not success:
            return False, None, f"Backtest failed: {msg}"
        
        # Step 3: Parse results
        print(f"Parsing results for {strategy_name}...")
        result = self.parse_xml_report(report_path)
        if result is None:
            return False, None, "Failed to parse backtest results"
        
        return True, result, "Backtest completed successfully"


class MockMT5Automation(MT5Automation):
    """
    Mock implementation for testing without actual MT5 installation
    """
    
    def compile_strategy(self, mq5_file: Path) -> tuple[bool, str]:
        """Mock compilation - always succeeds"""
        if not mq5_file.exists():
            return False, f"File not found: {mq5_file}"
        return True, f"Mock compiled: {mq5_file.stem}"
    
    def run_backtest(
        self, 
        strategy_name: str,
        wait_timeout: int = 300,
        custom_params: Optional[Dict[str, Any]] = None
    ) -> tuple[bool, Optional[Path], str]:
        """Mock backtest - generates sample results"""
        import random
        
        # Generate mock report
        report_path = self.mt5.reports_path / f"{strategy_name}_mock.xml"
        report_path.parent.mkdir(parents=True, exist_ok=True)
        
        # Create mock XML with randomized results
        net_profit = random.uniform(-5000, 15000)
        win_rate = random.uniform(35, 65)
        total_trades = random.randint(50, 200)
        winning = int(total_trades * win_rate / 100)
        
        mock_xml = f"""<?xml version="1.0" encoding="utf-8"?>
<Report>
    <Expert>{strategy_name}</Expert>
    <Symbol>{self.backtest.symbol}</Symbol>
    <Period>{self.backtest.period}</Period>
    <FromDate>{self.backtest.from_date}</FromDate>
    <ToDate>{self.backtest.to_date}</ToDate>
    <Deposit>{self.backtest.deposit}</Deposit>
    <Balance>{self.backtest.deposit + net_profit}</Balance>
    <Profit>{net_profit}</Profit>
    <GrossProfit>{abs(net_profit) * 1.5 if net_profit > 0 else random.uniform(5000, 10000)}</GrossProfit>
    <GrossLoss>{abs(net_profit) * 0.5 if net_profit > 0 else random.uniform(8000, 15000)}</GrossLoss>
    <ProfitFactor>{random.uniform(0.8, 2.5)}</ProfitFactor>
    <ExpectedPayoff>{net_profit / total_trades if total_trades > 0 else 0}</ExpectedPayoff>
    <SharpeRatio>{random.uniform(-0.5, 2.0)}</SharpeRatio>
    <TotalTrades>{total_trades}</TotalTrades>
    <WinningTrades>{winning}</WinningTrades>
    <LosingTrades>{total_trades - winning}</LosingTrades>
    <MaxDrawdown>{random.uniform(2000, 15000)}</MaxDrawdown>
    <MaxDrawdownPercent>{random.uniform(2, 15)}</MaxDrawdownPercent>
</Report>"""
        
        report_path.write_text(mock_xml, encoding='utf-8')
        return True, report_path, "Mock backtest completed"
