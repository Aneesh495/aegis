"""
Frequent Batch Auction (FBA) uniform price clearing solver and order crossing engine.
"""

from dataclasses import dataclass
from typing import List, Tuple, Optional

@dataclass
class LimitOrder:
    order_id: int
    trader: str
    is_buy: bool
    limit_price: float
    amount: float
    filled: float = 0.0

@dataclass
class ClearingResult:
    clearing_price: float
    matched_volume: float
    matched_pairs: List[Tuple[int, int, float]] # (buy_id, sell_id, matched_amount)

class BatchAuctionSolver:
    """
    Computes the optimal Uniform Clearing Price maximizing transaction volume
    for crossed order books over discrete auction epochs.
    """
    def solve_clearing_price(
        self,
        orders: List[LimitOrder]
    ) -> Optional[ClearingResult]:
        buys = [o for o in orders if o.is_buy and o.amount > o.filled]
        sells = [o for o in orders if not o.is_buy and o.amount > o.filled]

        if not buys or not sells:
            return None

        # Sort candidate prices from all limit prices
        candidate_prices = sorted(list(set([o.limit_price for o in orders])))

        best_price = 0.0
        best_volume = 0.0

        for p in candidate_prices:
            # Demand at price p: sum of all buys with limit_price >= p
            demand = sum([b.amount - b.filled for b in buys if b.limit_price >= p])
            # Supply at price p: sum of all sells with limit_price <= p
            supply = sum([s.amount - s.filled for s in sells if s.limit_price <= p])
            cleared_vol = min(demand, supply)

            if cleared_vol > best_volume:
                best_volume = cleared_vol
                best_price = p
            elif cleared_vol == best_volume and cleared_vol > 0:
                # Break ties towards median candidate price
                best_price = (best_price + p) / 2.0

        if best_volume == 0.0:
            return None

        # Generate matched order pairs (greedy match between eligible buys and sells)
        eligible_buys = sorted([b for b in buys if b.limit_price >= best_price], key=lambda x: -x.limit_price)
        eligible_sells = sorted([s for s in sells if s.limit_price <= best_price], key=lambda x: x.limit_price)

        matched_pairs: List[Tuple[int, int, float]] = []
        b_idx = 0
        s_idx = 0

        while b_idx < len(eligible_buys) and s_idx < len(eligible_sells):
            b_ord = eligible_buys[b_idx]
            s_ord = eligible_sells[s_idx]

            rem_b = b_ord.amount - b_ord.filled
            rem_s = s_ord.amount - s_ord.filled

            match_amt = min(rem_b, rem_s)
            matched_pairs.append((b_ord.order_id, s_ord.order_id, match_amt))

            b_ord.filled += match_amt
            s_ord.filled += match_amt

            if b_ord.filled >= b_ord.amount:
                b_idx += 1
            if s_ord.filled >= s_ord.amount:
                s_idx += 1

        return ClearingResult(
            clearing_price=best_price,
            matched_volume=best_volume,
            matched_pairs=matched_pairs
        )
