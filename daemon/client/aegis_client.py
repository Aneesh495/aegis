"""
High-level typed client interface for the Aegis protocol.
"""

from typing import Dict, Any, List, Optional
from dataclasses import dataclass
from daemon.config import DaemonConfig

@dataclass
class AccountSnapshot:
    account_address: str
    owner: str
    equity_usd: float
    total_collateral_usd: float
    total_debt_usd: float
    health_factor: float
    is_liquidatable: bool

@dataclass
class AuctionSnapshot:
    auction_id: int
    account: str
    debt_asset: str
    collateral_asset: str
    debt_amount: int
    collateral_amount: int
    current_penalty: float
    settled: bool

class AegisClient:
    """
    Protocol interaction layer interfacing with on-chain contracts or simulation harness.
    """
    def __init__(self, config: DaemonConfig):
        self.config = config

    def get_account_snapshot(self, account: str) -> AccountSnapshot:
        return AccountSnapshot(
            account_address=account,
            owner="",
            equity_usd=0.0,
            total_collateral_usd=0.0,
            total_debt_usd=0.0,
            health_factor=1.5,
            is_liquidatable=False
        )

    def get_active_auctions(self) -> List[AuctionSnapshot]:
        return []
