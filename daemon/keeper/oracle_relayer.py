"""
Oracle relayer daemon monitoring feed freshness, divergence, and TWAP updates.
"""

from dataclasses import dataclass
from typing import Dict, List
import time

@dataclass
class FeedStatus:
    asset: str
    primary_price: float
    secondary_price: float
    twap_price: float
    relative_divergence: float
    is_divergent: bool
    last_update_timestamp: float

class OracleRelayer:
    """
    Supervises oracle health, detects cross-feed arbitrage dislocations,
    and submits heartbeat TWAP accumulator snapshots.
    """
    def __init__(self, max_divergence_ratio: float = 0.03):
        self.max_divergence_ratio = max_divergence_ratio

    def check_feed(
        self,
        asset: str,
        primary_price: float,
        secondary_price: float,
        twap_price: float
    ) -> FeedStatus:
        diff = abs(primary_price - secondary_price)
        divergence = diff / primary_price if primary_price > 0 else 0.0
        is_divergent = divergence > self.max_divergence_ratio

        return FeedStatus(
            asset=asset,
            primary_price=primary_price,
            secondary_price=secondary_price,
            twap_price=twap_price,
            relative_divergence=divergence,
            is_divergent=is_divergent,
            last_update_timestamp=time.time()
        )
