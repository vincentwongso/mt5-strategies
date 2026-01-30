"""
MT5 Strategy Tester Automation Module

Handles:
- Compiling MQ5 files using MetaEditor
- Generating tester INI configuration
- Running backtests via MT5 command line
- Parsing XML and HTM report results
"""
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path
from datetime import datetime
from typing import Optional, Dict, Any
import shutil
import time
import re
from html.parser import HTMLParser

from config_loader import MT5Config, BacktestConfig, AppConfig, load_config
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
        if not self.mt5.experts_path.exists():
            return False, f"MT5 Experts path does not exist: {self.mt5.experts_path}"

        strategy_dir_name = mq5_file.parent.name
        target_dir = self.mt5.experts_path / strategy_dir_name
        target_dir.mkdir(parents=True, exist_ok=True)
        target_path = target_dir / mq5_file.name

        print(
            f"[MT5] compile_strategy: mq5_file={mq5_file} "
            f"-> target_path={target_path}"
        )
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
        expert_name: Optional[str] = None,
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
        report_format = (self.backtest.report_format or "xml").lower()
        if report_format not in {"xml", "htm", "html"}:
            report_format = "xml"
        # MT5 appends its own extension (.htm) to the Report path, so we use the base name
        # without extension in the INI file. The actual report will be at report_base_path + ".htm"
        report_base_path = self.mt5.reports_path / report_name
        report_base_path.parent.mkdir(parents=True, exist_ok=True)
        # Expected actual report path (MT5 adds .htm extension)
        report_path = Path(str(report_base_path) + ".htm")
        
        login = (self.mt5.login or "").strip()
        password = (self.mt5.password or "").strip()
        server = (self.mt5.server or "").strip()

        expert_name = expert_name or strategy_name

        # INI content for Strategy Tester
        # Note: Report= uses base path without extension; MT5 will append .htm
        ini_content = f"""[Tester]
Expert={expert_name}
Symbol={params.symbol}
Period={params.period}
Deposit={params.deposit}
Currency={params.currency}
Leverage={params.leverage}
ExecutionMode={params.delays}
Model={params.model}
Optimization={params.optimization}
FromDate={params.from_date}
ToDate={params.to_date}
Report=\\reports\\{report_name}.htm
ReplaceReport=1
UseLocal=1
Visual={1 if params.visual else 0}
ShutdownTerminal=1
"""

        if login and password and server:
            ini_content += (
                f"Login={login}\n"
                f"Password={password}\n"
                f"Server={server}\n"
            )
        else:
            print(
                "[MT5] tester.ini missing Login/Password/Server; "
                "MT5 may exit without running tester."
            )
        
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
        custom_params: Optional[Dict[str, Any]] = None,
        expert_name: Optional[str] = None
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
            expert_name=expert_name,
            custom_params=custom_params
        )
        
        print(
            f"[MT5] run_backtest: ini_path={ini_path} report_path={report_path} "
            f"exists(ini)={ini_path.exists()} exists(report)={report_path.exists()}"
        )
        if ini_path.exists():
            try:
                ini_size = ini_path.stat().st_size
            except OSError:
                ini_size = -1
            print(f"[MT5] tester.ini size={ini_size} bytes")
        
        # Run MT5 with tester config
        cmd = [
            str(self.mt5.mt5_path),
            f"/config:{ini_path}"
        ]
        print(f"[MT5] launch cmd: {' '.join(cmd)}")
        
        try:
            # Start MT5 process
            process = subprocess.Popen(cmd)
            print(f"[MT5] process started pid={process.pid}")
            
            # Wait for report file to appear (indicates completion)
            start_time = time.time()
            last_report_size = None
            early_exit_logged = False
            while time.time() - start_time < wait_timeout:
                poll = process.poll()
                if poll is not None and not early_exit_logged:
                    early_exit_logged = True
                    print(
                        f"[MT5] process exited with code={poll}; "
                        "waiting for report until timeout"
                    )
                
                # MT5 generates .htm reports; check for the expected path
                # report_path is already set to base_path + ".htm"
                candidate_reports = [
                    report_path,                          # Expected: base.htm
                    report_path.with_suffix('.html'),     # Alternative: base.html
                ]
                
                # Also check Tester folder for reports
                tester_folder = self.mt5.tester_ini_path
                tester_report_candidates = [
                    tester_folder / f"{report_path.stem}.htm",
                    tester_folder / f"{report_path.stem}.html",
                ]
                candidate_reports.extend(tester_report_candidates)
                
                # Debug: List all files in reports directory and Tester folder
                if not early_exit_logged or (time.time() - start_time) % 30 < 5:
                    try:
                        reports_dir = report_path.parent
                        if reports_dir.exists():
                            existing_files = list(reports_dir.glob("*.htm*"))
                            if existing_files:
                                print(f"[MT5] DEBUG: HTM files in {reports_dir}: {[f.name for f in existing_files[:10]]}")
                        if tester_folder.exists():
                            tester_files = list(tester_folder.glob("*.htm*"))
                            if tester_files:
                                print(f"[MT5] DEBUG: HTM files in {tester_folder}: {[f.name for f in tester_files[:10]]}")
                    except Exception as e:
                        print(f"[MT5] DEBUG: Error listing dirs: {e}")

                for candidate in candidate_reports:
                    if not candidate.exists():
                        continue
                    # Give it a moment to finish writing
                    time.sleep(2)
                    try:
                        report_size = candidate.stat().st_size
                    except OSError:
                        report_size = -1
                    if report_size != last_report_size:
                        print(f"[MT5] report file found: {candidate} size={report_size} bytes")
                        last_report_size = report_size
                    if report_size > 0:
                        # HTM/HTML reports are valid - return success
                        return True, candidate, "Backtest completed successfully"
                time.sleep(5)
            
            # Timeout - kill process if still running
            print(f"[MT5] timeout after {wait_timeout}s, terminating process")
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
    
    def parse_htm_report(self, report_path: Path) -> Optional[BacktestResult]:
        """
        Parse MT5 HTM report into BacktestResult
        
        Args:
            report_path: Path to HTM report file
            
        Returns:
            BacktestResult object or None if parsing fails
        """
        if not report_path.exists():
            return None
            
        try:
            # Try different encodings - MT5 often uses UTF-16
            content = None
            for encoding in ['utf-16', 'utf-16-le', 'utf-8', 'latin-1']:
                try:
                    content = report_path.read_text(encoding=encoding)
                    # Check if content looks valid (has HTML tags)
                    if '<html>' in content.lower() or '<table' in content.lower():
                        break
                except (UnicodeDecodeError, UnicodeError):
                    continue
            
            if content is None:
                print(f"Could not decode HTM file with any supported encoding")
                return None
            
            # Parse the HTML content
            data = self._extract_htm_data(content)
            
            if not data:
                print("Failed to extract data from HTM report")
                return None
            
            # Build BacktestResult from extracted data
            performance = PerformanceMetrics(
                net_profit=data.get('total_net_profit', 0.0),
                gross_profit=data.get('gross_profit', 0.0),
                gross_loss=data.get('gross_loss', 0.0),
                profit_factor=data.get('profit_factor', 0.0),
                expected_payoff=data.get('expected_payoff', 0.0),
                sharpe_ratio=data.get('sharpe_ratio', 0.0),
                recovery_factor=data.get('recovery_factor', 0.0),
            )
            
            # Calculate return percentages
            initial_deposit = data.get('initial_deposit', self.backtest.deposit)
            if initial_deposit > 0 and performance.net_profit != 0:
                performance.total_return_pct = (performance.net_profit / initial_deposit) * 100
            
            trades = TradeStats(
                total_trades=data.get('total_trades', 0),
                winning_trades=data.get('profit_trades', 0),
                losing_trades=data.get('loss_trades', 0),
                avg_win=data.get('average_profit_trade', 0.0),
                avg_loss=data.get('average_loss_trade', 0.0),
                largest_win=data.get('largest_profit_trade', 0.0),
                largest_loss=data.get('largest_loss_trade', 0.0),
                consecutive_wins=data.get('max_consecutive_wins', 0),
                consecutive_losses=data.get('max_consecutive_losses', 0),
            )
            
            # Calculate win rate
            if trades.total_trades > 0:
                trades.win_rate = (trades.winning_trades / trades.total_trades) * 100
            
            drawdown = DrawdownStats(
                max_drawdown_abs=data.get('balance_drawdown_absolute', 0.0),
                max_drawdown_pct=data.get('balance_drawdown_maximal_pct', 0.0),
                avg_drawdown_pct=data.get('balance_drawdown_relative_pct', 0.0),
            )
            
            # Also check equity drawdown if balance drawdown not available
            if drawdown.max_drawdown_abs == 0:
                drawdown.max_drawdown_abs = data.get('equity_drawdown_absolute', 0.0)
            if drawdown.max_drawdown_pct == 0:
                drawdown.max_drawdown_pct = data.get('equity_drawdown_maximal_pct', 0.0)
            
            final_balance = initial_deposit + performance.net_profit
            
            return BacktestResult(
                strategy_name=data.get('expert', 'Unknown'),
                symbol=data.get('symbol', self.backtest.symbol),
                timeframe=data.get('period', self.backtest.period),
                from_date=data.get('from_date', self.backtest.from_date),
                to_date=data.get('to_date', self.backtest.to_date),
                initial_deposit=initial_deposit,
                final_balance=final_balance,
                performance=performance,
                trades=trades,
                drawdown=drawdown,
                raw_xml=content,  # Store raw HTM content
                parameters=data.get('inputs', {})
            )
            
        except Exception as e:
            print(f"Error parsing HTM report: {e}")
            import traceback
            traceback.print_exc()
            return None
    
    def _extract_htm_data(self, content: str) -> Dict[str, Any]:
        """
        Extract data from MT5 HTM report content
        
        Args:
            content: HTML content string
            
        Returns:
            Dictionary with extracted values
        """
        data = {}
        
        # Clean up the content - remove extra whitespace between characters
        # MT5 UTF-16 files sometimes have spaces between chars when read incorrectly
        # But if we read with correct encoding, this shouldn't be needed
        
        # Helper function to extract value after a label
        def extract_value(label: str, pattern: str = r'<b>([^<]+)</b>') -> Optional[str]:
            """Extract value from HTML after a label"""
            # Look for the label followed by the value in bold
            label_pattern = re.escape(label) + r'[^<]*</td>\s*<td[^>]*>\s*' + pattern
            match = re.search(label_pattern, content, re.IGNORECASE | re.DOTALL)
            if match:
                return match.group(1).strip()
            return None
        
        def parse_number(value: Optional[str]) -> float:
            """Parse a number from string, handling various formats"""
            if value is None:
                return 0.0
            # Remove spaces, replace unicode minus
            value = value.replace(' ', '').replace('\xa0', '').replace('−', '-')
            # Handle percentage in parentheses like "1 958.19 (1.96%)"
            if '(' in value:
                value = value.split('(')[0].strip()
            try:
                return float(value)
            except ValueError:
                return 0.0
        
        def parse_percentage(value: Optional[str]) -> float:
            """Parse percentage value, extracting from formats like '1.96% (1 958.19)'"""
            if value is None:
                return 0.0
            # Look for percentage pattern
            match = re.search(r'([\d.,]+)\s*%', value.replace(' ', ''))
            if match:
                try:
                    return float(match.group(1).replace(',', '.'))
                except ValueError:
                    pass
            return 0.0
        
        # Extract Settings section
        # Expert name
        match = re.search(r'Expert:\s*</td>\s*<td[^>]*>\s*<b>([^<]+)</b>', content, re.IGNORECASE)
        if match:
            data['expert'] = match.group(1).strip()
        
        # Symbol
        match = re.search(r'Symbol:\s*</td>\s*<td[^>]*>\s*<b>([^<]+)</b>', content, re.IGNORECASE)
        if match:
            data['symbol'] = match.group(1).strip()
        
        # Period (includes date range)
        match = re.search(r'Period:\s*</td>\s*<td[^>]*>\s*<b>([^<]+)</b>', content, re.IGNORECASE)
        if match:
            period_str = match.group(1).strip()
            data['period'] = period_str
            # Extract date range if present: "M15 (2025.12.01 - 2025.12.31)"
            date_match = re.search(r'\((\d{4}\.\d{2}\.\d{2})\s*-\s*(\d{4}\.\d{2}\.\d{2})\)', period_str)
            if date_match:
                data['from_date'] = date_match.group(1)
                data['to_date'] = date_match.group(2)
        
        # Initial Deposit
        match = re.search(r'Initial\s+Deposit:\s*</td>\s*<td[^>]*>\s*<b>([^<]+)</b>', content, re.IGNORECASE)
        if match:
            data['initial_deposit'] = parse_number(match.group(1))
        
        # Leverage
        match = re.search(r'Leverage:\s*</td>\s*<td[^>]*>\s*<b>([^<]+)</b>', content, re.IGNORECASE)
        if match:
            data['leverage'] = match.group(1).strip()
        
        # Extract Results section
        # Total Net Profit
        match = re.search(r'Total\s+Net\s+Profit:\s*</td>\s*<td[^>]*>\s*<b>([^<]+)</b>', content, re.IGNORECASE)
        if match:
            data['total_net_profit'] = parse_number(match.group(1))
        
        # Gross Profit
        match = re.search(r'Gross\s+Profit:\s*</td>\s*<td[^>]*>\s*<b>([^<]+)</b>', content, re.IGNORECASE)
        if match:
            data['gross_profit'] = parse_number(match.group(1))
        
        # Gross Loss
        match = re.search(r'Gross\s+Loss:\s*</td>\s*<td[^>]*>\s*<b>([^<]+)</b>', content, re.IGNORECASE)
        if match:
            data['gross_loss'] = parse_number(match.group(1))
        
        # Profit Factor
        match = re.search(r'Profit\s+Factor:\s*</td>\s*<td[^>]*>\s*<b>([^<]+)</b>', content, re.IGNORECASE)
        if match:
            data['profit_factor'] = parse_number(match.group(1))
        
        # Expected Payoff
        match = re.search(r'Expected\s+Payoff:\s*</td>\s*<td[^>]*>\s*<b>([^<]+)</b>', content, re.IGNORECASE)
        if match:
            data['expected_payoff'] = parse_number(match.group(1))
        
        # Recovery Factor
        match = re.search(r'Recovery\s+Factor:\s*</td>\s*<td[^>]*>\s*<b>([^<]+)</b>', content, re.IGNORECASE)
        if match:
            data['recovery_factor'] = parse_number(match.group(1))
        
        # Sharpe Ratio
        match = re.search(r'Sharpe\s+Ratio:\s*</td>\s*<td[^>]*>\s*<b>([^<]+)</b>', content, re.IGNORECASE)
        if match:
            data['sharpe_ratio'] = parse_number(match.group(1))
        
        # Drawdown stats
        # Balance Drawdown Absolute
        match = re.search(r'Balance\s+Drawdown\s+Absolute:\s*</td>\s*<td[^>]*>\s*<b>([^<]+)</b>', content, re.IGNORECASE)
        if match:
            data['balance_drawdown_absolute'] = parse_number(match.group(1))
        
        # Balance Drawdown Maximal (with percentage)
        match = re.search(r'Balance\s+Drawdown\s+Maximal:\s*</td>\s*<td[^>]*>\s*<b>([^<]+)</b>', content, re.IGNORECASE)
        if match:
            value = match.group(1)
            data['balance_drawdown_maximal'] = parse_number(value)
            data['balance_drawdown_maximal_pct'] = parse_percentage(value)
        
        # Balance Drawdown Relative
        match = re.search(r'Balance\s+Drawdown\s+Relative:\s*</td>\s*<td[^>]*>\s*<b>([^<]+)</b>', content, re.IGNORECASE)
        if match:
            value = match.group(1)
            data['balance_drawdown_relative_pct'] = parse_percentage(value)
        
        # Equity Drawdown Absolute
        match = re.search(r'Equity\s+Drawdown\s+Absolute:\s*</td>\s*<td[^>]*>\s*<b>([^<]+)</b>', content, re.IGNORECASE)
        if match:
            data['equity_drawdown_absolute'] = parse_number(match.group(1))
        
        # Equity Drawdown Maximal
        match = re.search(r'Equity\s+Drawdown\s+Maximal:\s*</td>\s*<td[^>]*>\s*<b>([^<]+)</b>', content, re.IGNORECASE)
        if match:
            value = match.group(1)
            data['equity_drawdown_maximal'] = parse_number(value)
            data['equity_drawdown_maximal_pct'] = parse_percentage(value)
        
        # Trade statistics
        # Total Trades
        match = re.search(r'Total\s+Trades:\s*</td>\s*<td[^>]*>\s*<b>(\d+)</b>', content, re.IGNORECASE)
        if match:
            data['total_trades'] = int(match.group(1))
        
        # Total Deals
        match = re.search(r'Total\s+Deals:\s*</td>\s*<td[^>]*>\s*<b>(\d+)</b>', content, re.IGNORECASE)
        if match:
            data['total_deals'] = int(match.group(1))
        
        # Profit Trades (% of total)
        match = re.search(r'Profit\s+Trades\s*\([^)]*\):\s*</td>\s*<td[^>]*>\s*<b>([^<]+)</b>', content, re.IGNORECASE)
        if match:
            value = match.group(1)
            # Format: "3 (30.00%)"
            num_match = re.match(r'(\d+)', value.replace(' ', ''))
            if num_match:
                data['profit_trades'] = int(num_match.group(1))
        
        # Loss Trades (% of total)
        match = re.search(r'Loss\s+Trades\s*\([^)]*\):\s*</td>\s*<td[^>]*>\s*<b>([^<]+)</b>', content, re.IGNORECASE)
        if match:
            value = match.group(1)
            num_match = re.match(r'(\d+)', value.replace(' ', ''))
            if num_match:
                data['loss_trades'] = int(num_match.group(1))
        
        # Largest profit trade
        match = re.search(r'Largest\s+profit\s+trade:\s*</td>\s*<td[^>]*>\s*<b>([^<]+)</b>', content, re.IGNORECASE)
        if match:
            data['largest_profit_trade'] = parse_number(match.group(1))
        
        # Largest loss trade
        match = re.search(r'Largest\s+loss\s+trade:\s*</td>\s*<td[^>]*>\s*<b>([^<]+)</b>', content, re.IGNORECASE)
        if match:
            data['largest_loss_trade'] = parse_number(match.group(1))
        
        # Average profit trade
        match = re.search(r'Average\s+profit\s+trade:\s*</td>\s*<td[^>]*>\s*<b>([^<]+)</b>', content, re.IGNORECASE)
        if match:
            data['average_profit_trade'] = parse_number(match.group(1))
        
        # Average loss trade
        match = re.search(r'Average\s+loss\s+trade:\s*</td>\s*<td[^>]*>\s*<b>([^<]+)</b>', content, re.IGNORECASE)
        if match:
            data['average_loss_trade'] = parse_number(match.group(1))
        
        # Maximum consecutive wins
        match = re.search(r'Maximum\s+consecutive\s+wins\s*\([^)]*\):\s*</td>\s*<td[^>]*>\s*<b>([^<]+)</b>', content, re.IGNORECASE)
        if match:
            value = match.group(1)
            num_match = re.match(r'(\d+)', value.replace(' ', ''))
            if num_match:
                data['max_consecutive_wins'] = int(num_match.group(1))
        
        # Maximum consecutive losses
        match = re.search(r'Maximum\s+consecutive\s+losses\s*\([^)]*\):\s*</td>\s*<td[^>]*>\s*<b>([^<]+)</b>', content, re.IGNORECASE)
        if match:
            value = match.group(1)
            num_match = re.match(r'(\d+)', value.replace(' ', ''))
            if num_match:
                data['max_consecutive_losses'] = int(num_match.group(1))
        
        # Extract input parameters
        inputs = {}
        # Look for input parameters in the Inputs section
        # Format: parameter=value in bold tags
        input_matches = re.findall(r'<b>(\w+)=([^<]+)</b>', content)
        for name, value in input_matches:
            # Skip separator lines (just "=")
            if name and value and value.strip() != '':
                # Try to convert to appropriate type
                try:
                    if '.' in value:
                        inputs[name] = float(value)
                    elif value.lower() in ('true', 'false'):
                        inputs[name] = value.lower() == 'true'
                    else:
                        inputs[name] = int(value)
                except ValueError:
                    inputs[name] = value.strip()
        
        data['inputs'] = inputs
        
        return data
    
    def parse_report(self, report_path: Path) -> Optional[BacktestResult]:
        """
        Parse MT5 report file (auto-detects XML or HTM format)
        
        Args:
            report_path: Path to report file
            
        Returns:
            BacktestResult object or None if parsing fails
        """
        if not report_path.exists():
            return None
        
        suffix = report_path.suffix.lower()
        
        # Determine format based on extension
        if suffix in ['.htm', '.html']:
            return self.parse_htm_report(report_path)
        elif suffix == '.xml':
            return self.parse_xml_report(report_path)
        else:
            # Try to detect format from content
            try:
                # Read first few bytes to detect format
                with open(report_path, 'rb') as f:
                    header = f.read(100)
                
                # Check for XML declaration or HTML doctype
                if b'<?xml' in header:
                    return self.parse_xml_report(report_path)
                elif b'<!DOCTYPE' in header or b'<html' in header.lower() or b'< ! D O C T Y P E' in header:
                    return self.parse_htm_report(report_path)
                else:
                    # Default to HTM for MT5 reports
                    return self.parse_htm_report(report_path)
            except Exception as e:
                print(f"Error detecting report format: {e}")
                return None
    
    def full_backtest_cycle(
        self, 
        mq5_file: Path,
        custom_params: Optional[Dict[str, Any]] = None,
        expert_name: Optional[str] = None
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
        if not expert_name:
            parent_name = mq5_file.parent.name
            if parent_name:
                expert_name = f"{parent_name}\\{strategy_name}"
            else:
                expert_name = strategy_name
        
        # Step 1: Compile
        print(f"Compiling {strategy_name}...")
        success, msg = self.compile_strategy(mq5_file)
        if not success:
            return False, None, f"Compilation failed: {msg}"
        
        # Step 2: Run backtest
        print(f"Running backtest for {strategy_name}...")
        success, report_path, msg = self.run_backtest(
            strategy_name,
            custom_params=custom_params,
            expert_name=expert_name
        )
        if not success:
            return False, None, f"Backtest failed: {msg}"
        
        # Step 3: Parse results
        print(f"Parsing results for {strategy_name}...")
        result = self.parse_report(report_path)
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
