"""
CrewAI Agents for MT5 Strategy Analysis and Optimization

Agents:
1. Strategy Analyst - Analyzes backtest results and identifies issues
2. Code Modifier - Modifies MQL5 code based on analysis recommendations
3. Risk Assessor - Evaluates risk metrics and suggests risk management improvements
"""
import os
from typing import Optional, List
from pathlib import Path

from crewai import Agent, Task, Crew, Process
from crewai.tools import tool
from langchain_anthropic import ChatAnthropic

from config import AppConfig, SuccessCriteria
from models import (
    BacktestResult, LLMAnalysis, CodeModification, 
    OptimizationAction, StrategyIteration
)


class StrategyOptimizationCrew:
    """CrewAI-based strategy optimization system"""
    
    def __init__(self, config: AppConfig):
        self.config = config
        self.criteria = config.success
        
        # Initialize LLM
        self.llm = ChatAnthropic(
            model=config.crewai.model,
            temperature=config.crewai.temperature,
            max_tokens=config.crewai.max_tokens,
            api_key=os.getenv("ANTHROPIC_API_KEY", config.crewai.anthropic_api_key)
        )
        
        # Initialize agents
        self._create_agents()
    
    def _create_agents(self):
        """Create the specialized agents"""
        
        # Strategy Analyst Agent
        self.analyst = Agent(
            role="MT5 Strategy Analyst",
            goal="""Analyze forex trading strategy backtest results to identify 
            strengths, weaknesses, and specific areas for improvement.""",
            backstory="""You are an expert quantitative analyst specializing in 
            algorithmic forex trading. You have extensive experience analyzing 
            MetaTrader 5 backtest reports and identifying patterns that lead to 
            profitable strategies. You understand technical indicators, price action, 
            and statistical analysis of trading systems.""",
            llm=self.llm,
            verbose=True,
            allow_delegation=False
        )
        
        # Code Modifier Agent
        self.coder = Agent(
            role="MQL5 Code Specialist",
            goal="""Implement precise code modifications to MQL5 Expert Advisors 
            based on analysis recommendations to improve strategy performance.""",
            backstory="""You are a senior MQL5 developer with 10+ years of experience 
            building profitable Expert Advisors. You understand MetaTrader 5's trading 
            functions, indicator calculations, order management, and risk controls. 
            You write clean, efficient, and well-documented MQL5 code.""",
            llm=self.llm,
            verbose=True,
            allow_delegation=False
        )
        
        # Risk Assessor Agent
        self.risk_assessor = Agent(
            role="Trading Risk Manager",
            goal="""Evaluate strategy risk metrics and ensure compliance with 
            risk management requirements while maintaining profitability.""",
            backstory="""You are a risk management specialist for algorithmic trading 
            systems. You focus on drawdown analysis, position sizing, and protecting 
            capital while still allowing strategies to be profitable. You understand 
            the balance between risk and reward in forex trading.""",
            llm=self.llm,
            verbose=True,
            allow_delegation=False
        )
    
    def analyze_results(
        self, 
        result: BacktestResult, 
        strategy_code: str,
        iteration: int = 1
    ) -> LLMAnalysis:
        """
        Analyze backtest results and generate improvement recommendations
        
        Args:
            result: BacktestResult from MT5 backtest
            strategy_code: Current MQL5 source code
            iteration: Current optimization iteration (1-3)
            
        Returns:
            LLMAnalysis with recommendations
        """
        # Create analysis task
        analysis_task = Task(
            description=f"""
            Analyze the following MT5 backtest results for iteration {iteration}/3:
            
            ## Strategy: {result.strategy_name}
            ## Symbol: {result.symbol}, Timeframe: {result.timeframe}
            ## Period: {result.from_date} to {result.to_date}
            
            ## Performance Metrics:
            - Net Profit: ${result.performance.net_profit:.2f}
            - Monthly Return: {result.performance.monthly_return_pct:.2f}%
            - Profit Factor: {result.performance.profit_factor:.2f}
            - Sharpe Ratio: {result.performance.sharpe_ratio:.2f}
            
            ## Trade Statistics:
            - Total Trades: {result.trades.total_trades}
            - Win Rate: {result.trades.win_rate:.1f}%
            - Avg Win: ${result.trades.avg_win:.2f}
            - Avg Loss: ${result.trades.avg_loss:.2f}
            
            ## Risk Metrics:
            - Max Drawdown: {result.drawdown.max_drawdown_pct:.2f}%
            - Max Daily Drawdown: {result.drawdown.max_daily_drawdown_pct:.2f}%
            
            ## Success Criteria:
            - Target Monthly Profit: {self.criteria.min_monthly_profit_pct}-{self.criteria.max_monthly_profit_pct}%
            - Max Daily Drawdown: {self.criteria.max_daily_drawdown_pct}%
            - Max Total Drawdown: {self.criteria.max_total_drawdown_pct}%
            - Min Profit Factor: {self.criteria.min_profit_factor}
            
            ## Current Strategy Code (excerpt):
            ```mql5
            {strategy_code[:3000]}...
            ```
            
            Provide a detailed analysis including:
            1. Summary of current performance vs targets
            2. Key strengths of the strategy
            3. Critical weaknesses that need addressing
            4. Specific recommended changes (be precise about parameters, logic, etc.)
            5. Confidence score (0-1) in your recommendations
            6. Whether to continue optimizing or abandon this strategy
            
            Format your response as a structured analysis.
            """,
            expected_output="""
            A structured analysis with:
            - Executive summary
            - List of strengths
            - List of weaknesses  
            - Specific recommended actions with details
            - Confidence score
            - Continue/abandon recommendation with reasoning
            """,
            agent=self.analyst
        )
        
        # Create risk assessment task
        risk_task = Task(
            description=f"""
            Review the following backtest results from a risk management perspective:
            
            - Max Drawdown: {result.drawdown.max_drawdown_pct:.2f}%
            - Max Daily Drawdown: {result.drawdown.max_daily_drawdown_pct:.2f}%
            - Consecutive Losses: {result.trades.consecutive_losses}
            - Largest Loss: ${result.trades.largest_loss:.2f}
            
            Risk Limits:
            - Max Daily Drawdown Allowed: {self.criteria.max_daily_drawdown_pct}%
            - Max Total Drawdown Allowed: {self.criteria.max_total_drawdown_pct}%
            
            Provide specific risk management recommendations including:
            1. Position sizing adjustments
            2. Stop loss modifications
            3. Daily/weekly loss limits
            4. Any circuit breakers needed
            """,
            expected_output="Risk management recommendations",
            agent=self.risk_assessor
        )
        
        # Run crew
        crew = Crew(
            agents=[self.analyst, self.risk_assessor],
            tasks=[analysis_task, risk_task],
            process=Process.sequential,
            verbose=True
        )
        
        crew_output = crew.kickoff()
        
        # Parse crew output into LLMAnalysis
        return self._parse_analysis_output(crew_output, result)
    
    def modify_code(
        self,
        strategy_code: str,
        analysis: LLMAnalysis,
        result: BacktestResult
    ) -> tuple[str, List[CodeModification]]:
        """
        Modify strategy code based on analysis recommendations
        
        Args:
            strategy_code: Current MQL5 source code
            analysis: LLMAnalysis with recommendations
            result: BacktestResult for context
            
        Returns:
            tuple: (modified_code, list of modifications)
        """
        # Build detailed modification instructions
        changes_description = "\n".join([
            f"- {change}" for change in analysis.specific_changes
        ])
        
        modification_task = Task(
            description=f"""
            Modify the following MQL5 Expert Advisor code based on these recommendations:
            
            ## Analysis Summary:
            {analysis.summary}
            
            ## Weaknesses to Address:
            {chr(10).join(['- ' + w for w in analysis.weaknesses])}
            
            ## Specific Changes Required:
            {changes_description}
            
            ## Current Performance Issues:
            - Monthly Return: {result.performance.monthly_return_pct:.2f}% (Target: {self.criteria.min_monthly_profit_pct}-{self.criteria.max_monthly_profit_pct}%)
            - Max Drawdown: {result.drawdown.max_drawdown_pct:.2f}% (Max Allowed: {self.criteria.max_total_drawdown_pct}%)
            - Win Rate: {result.trades.win_rate:.1f}%
            - Profit Factor: {result.performance.profit_factor:.2f}
            
            ## CURRENT CODE:
            ```mql5
            {strategy_code}
            ```
            
            ## INSTRUCTIONS:
            1. Make ONLY the changes necessary to address the identified issues
            2. Preserve all existing functionality that works well
            3. Add clear comments explaining each modification
            4. Ensure code compiles correctly in MT5
            5. Keep modifications focused and testable
            
            Return the COMPLETE modified code, not just snippets.
            Also provide a summary of each change made.
            """,
            expected_output="""
            1. Complete modified MQL5 code
            2. List of modifications with descriptions
            """,
            agent=self.coder
        )
        
        crew = Crew(
            agents=[self.coder],
            tasks=[modification_task],
            process=Process.sequential,
            verbose=True
        )
        
        crew_output = crew.kickoff()
        
        # Parse output to extract code and modifications
        return self._parse_code_output(crew_output, strategy_code)
    
    def _parse_analysis_output(
        self, 
        crew_output, 
        result: BacktestResult
    ) -> LLMAnalysis:
        """Parse crew output into structured LLMAnalysis"""
        output_text = str(crew_output)
        
        analysis = LLMAnalysis()
        
        # Extract summary (first paragraph or section)
        lines = output_text.split('\n')
        summary_lines = []
        for line in lines[:10]:
            if line.strip():
                summary_lines.append(line.strip())
        analysis.summary = ' '.join(summary_lines[:3])
        
        # Extract strengths
        analysis.strengths = self._extract_list_items(output_text, 
            ['strength', 'positive', 'working well', 'good'])
        
        # Extract weaknesses
        analysis.weaknesses = self._extract_list_items(output_text,
            ['weakness', 'issue', 'problem', 'concern', 'needs improvement'])
        
        # Extract specific changes
        analysis.specific_changes = self._extract_list_items(output_text,
            ['recommend', 'should', 'change', 'modify', 'adjust', 'increase', 'decrease'])
        
        # Determine recommended actions based on content
        analysis.recommended_actions = self._determine_actions(output_text)
        
        # Extract confidence score
        import re
        confidence_match = re.search(r'confidence[:\s]+(\d+\.?\d*)', output_text.lower())
        if confidence_match:
            analysis.confidence_score = min(1.0, float(confidence_match.group(1)))
        else:
            # Estimate based on language
            analysis.confidence_score = 0.7 if 'confident' in output_text.lower() else 0.5
        
        # Determine if should continue
        abandon_keywords = ['abandon', 'stop', 'not viable', 'move on', 'unprofitable']
        continue_keywords = ['continue', 'potential', 'promising', 'improve']
        
        abandon_count = sum(1 for k in abandon_keywords if k in output_text.lower())
        continue_count = sum(1 for k in continue_keywords if k in output_text.lower())
        
        analysis.should_continue = continue_count >= abandon_count
        
        # Check against hard criteria
        if (result.drawdown.max_drawdown_pct > self.criteria.max_total_drawdown_pct * 2 or
            result.performance.profit_factor < 0.5 or
            result.trades.total_trades < self.criteria.min_trades):
            analysis.should_continue = False
            analysis.reasoning = "Strategy fails critical criteria"
        
        analysis.reasoning = output_text[-500:] if len(output_text) > 500 else output_text
        
        return analysis
    
    def _parse_code_output(
        self, 
        crew_output, 
        original_code: str
    ) -> tuple[str, List[CodeModification]]:
        """Parse crew output to extract modified code and changes"""
        output_text = str(crew_output)
        
        # Extract code block
        import re
        code_pattern = r'```(?:mql5|mq5)?\s*(.*?)```'
        code_matches = re.findall(code_pattern, output_text, re.DOTALL)
        
        if code_matches:
            # Take the longest code block (likely the full modified code)
            modified_code = max(code_matches, key=len).strip()
        else:
            # No code block found, try to extract raw code
            modified_code = original_code  # Fallback to original
        
        # Extract modification descriptions
        modifications = []
        change_patterns = [
            r'(?:changed|modified|adjusted|added|removed)[:\s]+(.+?)(?:\n|$)',
            r'\d+\.\s*(.+?)(?:\n|$)',
        ]
        
        changes_found = []
        for pattern in change_patterns:
            matches = re.findall(pattern, output_text, re.IGNORECASE)
            changes_found.extend(matches)
        
        for change_desc in changes_found[:10]:  # Limit to 10 changes
            modifications.append(CodeModification(
                action=OptimizationAction.ADJUST_PARAMETERS,  # Default
                description=change_desc.strip(),
                original_code="",
                modified_code=""
            ))
        
        return modified_code, modifications
    
    def _extract_list_items(self, text: str, keywords: List[str]) -> List[str]:
        """Extract list items containing keywords"""
        items = []
        lines = text.split('\n')
        
        for line in lines:
            line = line.strip()
            if not line:
                continue
            # Check if line is a list item
            if line.startswith(('-', '*', '•', '1', '2', '3', '4', '5', '6', '7', '8', '9')):
                # Check if any keyword is present
                if any(k in line.lower() for k in keywords):
                    # Clean up the line
                    clean = line.lstrip('-*•0123456789. ')
                    if clean and len(clean) > 10:
                        items.append(clean)
        
        return items[:5]  # Limit to 5 items
    
    def _determine_actions(self, text: str) -> List[OptimizationAction]:
        """Determine recommended actions from analysis text"""
        actions = []
        text_lower = text.lower()
        
        action_keywords = {
            OptimizationAction.ADJUST_PARAMETERS: ['parameter', 'input', 'setting', 'period', 'level'],
            OptimizationAction.MODIFY_ENTRY_LOGIC: ['entry', 'signal', 'buy condition', 'sell condition'],
            OptimizationAction.MODIFY_EXIT_LOGIC: ['exit', 'take profit', 'close', 'trailing'],
            OptimizationAction.ADD_FILTER: ['filter', 'confirm', 'additional check'],
            OptimizationAction.REMOVE_FILTER: ['remove filter', 'simplify', 'too strict'],
            OptimizationAction.ADJUST_RISK_MANAGEMENT: ['stop loss', 'position size', 'risk', 'drawdown'],
        }
        
        for action, keywords in action_keywords.items():
            if any(k in text_lower for k in keywords):
                actions.append(action)
        
        return actions if actions else [OptimizationAction.ADJUST_PARAMETERS]


def create_optimization_crew(config: AppConfig) -> StrategyOptimizationCrew:
    """Factory function to create optimization crew"""
    return StrategyOptimizationCrew(config)
