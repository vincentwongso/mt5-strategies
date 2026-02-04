"""
Anthropic API Client for MT5 Strategy Improvement

Direct integration with Anthropic's Claude API for analyzing backtest results
and generating improved MQL5 code.
"""
import os
import re
from typing import Optional, Tuple

import anthropic

from config_loader import AnthropicConfig, SuccessCriteria
from models import BacktestResult


class StrategyImprover:
    """Handles strategy improvement using Anthropic's Claude API"""

    def __init__(self, config: AnthropicConfig, criteria: SuccessCriteria):
        """
        Initialize the strategy improver.

        Args:
            config: Anthropic API configuration
            criteria: Success criteria for strategy evaluation
        """
        self.config = config
        self.criteria = criteria

        # Use API key from config or environment variable
        api_key = config.api_key or os.getenv("ANTHROPIC_API_KEY")
        if not api_key:
            raise ValueError(
                "Anthropic API key not found. Set ANTHROPIC_API_KEY environment variable "
                "or provide api_key in config."
            )

        self.client = anthropic.Anthropic(api_key=api_key)

    def improve_strategy(
        self,
        strategy_code: str,
        backtest_result: BacktestResult,
        strategy_name: str,
    ) -> Tuple[str, str]:
        """
        Analyze backtest results and generate improved strategy code.

        Args:
            strategy_code: Current MQL5 source code
            backtest_result: Parsed backtest results
            strategy_name: Name of the strategy

        Returns:
            Tuple of (improved_code, analysis_summary)
        """
        # Build the prompt
        prompt = self._build_prompt(strategy_code, backtest_result, strategy_name)

        try:
            # Call Anthropic API
            message = self.client.messages.create(
                model=self.config.model,
                max_tokens=self.config.max_tokens,
                temperature=self.config.temperature,
                messages=[{"role": "user", "content": prompt}],
            )

            # Extract response text
            response_text = message.content[0].text

            # Parse response to extract code and summary
            return self._parse_response(response_text, strategy_code)

        except anthropic.APIConnectionError as e:
            error_msg = f"Failed to connect to Anthropic API: {e}"
            return strategy_code, f"ERROR: {error_msg}"

        except anthropic.RateLimitError as e:
            error_msg = f"Anthropic API rate limit exceeded: {e}"
            return strategy_code, f"ERROR: {error_msg}"

        except anthropic.APIStatusError as e:
            error_msg = f"Anthropic API error (status {e.status_code}): {e.message}"
            return strategy_code, f"ERROR: {error_msg}"

        except Exception as e:
            error_msg = f"Unexpected error calling Anthropic API: {e}"
            return strategy_code, f"ERROR: {error_msg}"

    def _build_prompt(
        self,
        strategy_code: str,
        result: BacktestResult,
        strategy_name: str,
    ) -> str:
        """Build the improvement prompt for Claude"""
        prompt = f"""You are an expert MQL5 developer specializing in forex trading strategies for prop firm challenges.

## Current Strategy Performance
- Strategy: {strategy_name}
- Symbol: {result.symbol}, Timeframe: {result.timeframe}
- Period: {result.from_date} to {result.to_date}
- Net Profit: ${result.performance.net_profit:.2f}
- Monthly Return: {result.performance.monthly_return_pct:.2f}%
- Profit Factor: {result.performance.profit_factor:.2f}
- Total Trades: {result.trades.total_trades}
- Win Rate: {result.trades.win_rate:.1f}%
- Max Drawdown: {result.drawdown.max_drawdown_pct:.2f}%
- Max Daily Drawdown: {result.drawdown.max_daily_drawdown_pct:.2f}%
- Sharpe Ratio: {result.performance.sharpe_ratio:.2f}

## Target Criteria (Prop Firm Requirements)
- Monthly Profit Target: ~3% (minimum {self.criteria.min_monthly_profit_pct}%)
- Maximum Daily Drawdown: {self.criteria.max_daily_drawdown_pct}%
- Maximum Total Drawdown: {self.criteria.max_total_drawdown_pct}%
- Minimum Profit Factor: {self.criteria.min_profit_factor}
- Minimum Trades: {self.criteria.min_trades}

## Current MQ5 Code
```mql5
{strategy_code}
```

## Instructions
Analyze the backtest results and improve the strategy to meet the target criteria.

Focus on:
1. Improving profitability while maintaining strict risk limits
2. Reducing drawdown if it exceeds the limits
3. Optimizing entry/exit logic for better win rate and profit factor
4. Adjusting position sizing and risk management
5. Adding or modifying filters to reduce losing trades

IMPORTANT:
- Return the COMPLETE improved MQL5 code wrapped in ```mql5 code blocks
- The code must compile without errors in MetaTrader 5
- Preserve all necessary includes and library references
- Add comments explaining significant changes

After the code, provide a brief summary of the changes made (2-3 paragraphs)."""

        return prompt

    def _parse_response(
        self, response_text: str, original_code: str
    ) -> Tuple[str, str]:
        """
        Parse Claude's response to extract code and summary.

        Args:
            response_text: Raw response from Claude
            original_code: Original strategy code (fallback if parsing fails)

        Returns:
            Tuple of (improved_code, analysis_summary)
        """
        # Try to extract code from ```mql5 code blocks
        mql5_pattern = r"```mql5\s*\n(.*?)```"
        mql5_matches = re.findall(mql5_pattern, response_text, re.DOTALL)

        if mql5_matches:
            # Use the first (or largest) code block found
            improved_code = max(mql5_matches, key=len).strip()
        else:
            # Try generic code blocks as fallback
            generic_pattern = r"```\s*\n(.*?)```"
            generic_matches = re.findall(generic_pattern, response_text, re.DOTALL)

            if generic_matches:
                # Find the largest code block (likely the full strategy)
                improved_code = max(generic_matches, key=len).strip()
            else:
                # No code block found, return original code with error
                return (
                    original_code,
                    "ERROR: Could not extract improved code from response. "
                    "No MQL5 code block found in Claude's response.",
                )

        # Extract summary (text after the last code block)
        # Find the position after the last code block
        last_code_block_end = response_text.rfind("```")
        if last_code_block_end != -1:
            # Find the closing ``` and get text after it
            closing_pos = response_text.find("```", last_code_block_end + 3)
            if closing_pos == -1:
                closing_pos = last_code_block_end
            summary = response_text[closing_pos + 3 :].strip()
        else:
            summary = ""

        # If summary is empty, try to extract any text before the code block
        if not summary:
            first_code_block = response_text.find("```")
            if first_code_block > 0:
                summary = response_text[:first_code_block].strip()

        # If still no summary, provide a default message
        if not summary:
            summary = "Strategy code has been improved. Please review the changes."

        return improved_code, summary


def create_strategy_improver(
    config: AnthropicConfig, criteria: SuccessCriteria
) -> StrategyImprover:
    """
    Factory function to create a StrategyImprover instance.

    Args:
        config: Anthropic API configuration
        criteria: Success criteria for strategy evaluation

    Returns:
        Configured StrategyImprover instance
    """
    return StrategyImprover(config, criteria)
