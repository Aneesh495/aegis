//! Aegis Native Batch Auction Crossing and Uniform Clearing Price Solver
//!
//! Provides ultra-low-latency matching of discrete batch auction orders,
//! computing the clearing price that maximizes social surplus and filled volume.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Order {
    pub id: u64,
    pub is_buy: bool,
    pub limit_price: u64, // Scaled by 10^8
    pub amount: u64,      // Scaled by 10^8
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MatchResult {
    pub buy_id: u64,
    pub sell_id: u64,
    pub matched_amount: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BatchSolution {
    pub clearing_price: u64,
    pub total_volume: u64,
    pub matches: Vec<MatchResult>,
}

pub struct BatchSolver;

impl BatchSolver {
    /// Computes the uniform clearing price that maximizes volume for the given orders.
    pub fn solve(orders: Vec<Order>) -> Option<BatchSolution> {
        let mut buys: Vec<Order> = orders.iter().filter(|o| o.is_buy).cloned().collect();
        let mut sells: Vec<Order> = orders.iter().filter(|o| !o.is_buy).cloned().collect();

        if buys.is_empty() || sells.is_empty() {
            return None;
        }

        // Collect all distinct price points
        let mut candidate_prices: Vec<u64> = orders.iter().map(|o| o.limit_price).collect();
        candidate_prices.sort_unstable();
        candidate_prices.dedup();

        let mut best_price = 0u64;
        let mut max_volume = 0u64;

        for &price in &candidate_prices {
            let demand: u64 = buys
                .iter()
                .filter(|b| b.limit_price >= price)
                .map(|b| b.amount)
                .sum();

            let supply: u64 = sells
                .iter()
                .filter(|s| s.limit_price <= price)
                .map(|s| s.amount)
                .sum();

            let volume = std::cmp::min(demand, supply);
            if volume > max_volume {
                max_volume = volume;
                best_price = price;
            }
        }

        if max_volume == 0 {
            return None;
        }

        // Sort buys descending by limit price (highest willingness to pay first)
        buys.sort_by(|a, b| b.limit_price.cmp(&a.limit_price));
        // Sort sells ascending by limit price (lowest cost first)
        sells.sort_by(|a, b| a.limit_price.cmp(&b.limit_price));

        let mut matches = Vec::new();
        let mut b_idx = 0;
        let mut s_idx = 0;

        while b_idx < buys.len() && s_idx < sells.len() {
            if buys[b_idx].limit_price < best_price || sells[s_idx].limit_price > best_price {
                break;
            }

            let match_amt = std::cmp::min(buys[b_idx].amount, sells[s_idx].amount);
            if match_amt > 0 {
                matches.push(MatchResult {
                    buy_id: buys[b_idx].id,
                    sell_id: sells[s_idx].id,
                    matched_amount: match_amt,
                });
                buys[b_idx].amount -= match_amt;
                sells[s_idx].amount -= match_amt;
            }

            if buys[b_idx].amount == 0 {
                b_idx += 1;
            }
            if sells[s_idx].amount == 0 {
                s_idx += 1;
            }
        }

        Some(BatchSolution {
            clearing_price: best_price,
            total_volume: max_volume,
            matches,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_batch_solver_basic() {
        let orders = vec![
            Order { id: 1, is_buy: true, limit_price: 3100_00000000, amount: 2_00000000 },
            Order { id: 2, is_buy: false, limit_price: 2900_00000000, amount: 2_00000000 },
        ];

        let sol = BatchSolver::solve(orders).expect("solution exists");
        assert_eq!(sol.total_volume, 2_00000000);
        assert!(sol.clearing_price >= 2900_00000000 && sol.clearing_price <= 3100_00000000);
        assert_eq!(sol.matches.len(), 1);
    }
}
