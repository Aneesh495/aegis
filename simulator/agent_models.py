"""
Agent behavioral models for simulated decentralized finance environments.
"""

from dataclasses import dataclass
from typing import List

@dataclass
class SimulatedBorrower:
    id: int
    collateral_weth: float
    debt_usdc: float
    target_leverage: float
    is_liquidated: bool = False

@dataclass
class SimulatedLiquidator:
    id: int
    capital_usdc: float
    min_profit_spread: float # e.g. 0.05 for 5% minimum spread
