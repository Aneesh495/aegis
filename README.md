# Aegis

Autonomous On-Chain Prime Brokerage, Dynamic Margin Risk Engine, Multi-Tranche Debt Waterfall, and MEV-Proof Batch Clearinghouse in Vyper.

## Overview

Aegis is an institutional-grade decentralized prime brokerage and risk clearing protocol implemented natively in Vyper (0.4.x). Aegis coordinates capital formation, cross-asset portfolio margining, and frequent batch auction settlement without exposure to frontrunning, toxic MEV, or monolithic liquidation cascades.

## Core Features

- Isolated Credit Account proxies with delegated adapter routing (Uniswap V3, Curve).
- Dynamic margin risk engine with volatility-adjusted haircuts and cross-asset correlation matrices.
- Structured multi-tranche debt pools (Senior AAA, Mezzanine BBB, Junior Equity) with deterministic cash flow waterfalls.
- Continuous two-phase Dutch auction liquidation engine eliminating atomic MEV sandwiching.
- Frequent Batch Auction (FBA) clearinghouse computing uniform market clearing prices over discrete block epochs.
- Multi-source oracle aggregator with TWAP fallback, medianization, and volatility circuit breakers.
- Full ERC-3156 flash lending and ERC-4626 yield accounting integration.
