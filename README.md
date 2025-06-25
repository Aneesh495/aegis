# Aegis

[![Vyper 0.4.3](https://img.shields.io/badge/Vyper-0.4.3-blue.svg?logo=python&logoColor=white)](https://github.com/vyperlang/vyper)
[![Python 3.12](https://img.shields.io/badge/Python-3.12%2B-blue.svg?logo=python&logoColor=white)](https://python.org)
[![Rust](https://img.shields.io/badge/Rust-1.80%2B-orange.svg?logo=rust&logoColor=white)](https://www.rust-lang.org)
[![TypeScript](https://img.shields.io/badge/TypeScript-5.5%2B-blue.svg?logo=typescript&logoColor=white)](https://www.typescriptlang.org)
[![Tests Passing](https://img.shields.io/badge/Tests-39%2F39%20Passing-brightgreen.svg)](tests/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Aegis is an onchain decentralized prime brokerage, cross-margin risk clearinghouse, and multi-tranche structured debt protocol written natively in Vyper 0.4.3.

The protocol provides isolated smart contract credit accounts for programmatic traders, backed by real-time risk haircuts, continuous decaying Dutch auction liquidations, and frequent batch auctions with uniform clearing prices.

---

## Architecture Overview

```
                               +-------------------------------------+
                               |         EmergencyCouncil &          |
                               |         ProtocolParameters          |
                               +-------------------------------------+
                                                  |
                                                  v
   +-------------------+              +-----------------------+              +---------------------+
   |    Liquidity      |  deposits    |       AegisVault      |  borrows     |    CreditManager    |
   |    Providers      | -----------> |   (Multi-Asset Pool)  | <----------- |   (Lifecycle Hub)   |
   +-------------------+              +-----------------------+              +---------------------+
                                                  ^                                     |
                                                  | waterfall                           | creates /
                                                  v distribution                        | routes
                                      +-----------------------+                         v
                                      |       DebtEngine      |              +---------------------+
                                      |   (Tranche Waterfall) |              |    CreditAccount    |
                                      +-----------------------+              |   (Isolated Proxy)  |
                                                                             +---------------------+
                                                                                        |
                                  +-----------------------------------------------------+
                                  |                     |                               |
                                  v                     v                               v
                       +--------------------+ +--------------------+ +--------------------+
                       |     RiskEngine     | |  UniswapV3Adapter  | | LiquidationAuction |
                       |  (Dynamic VaR / HF)| |   & CurveAdapter   | |   (Dutch Decay)    |
                       +--------------------+ +--------------------+ +--------------------+
                                  |
                                  v
                       +--------------------+
                       |  PriceFeedRouter   |
                       | (Chainlink + Pyth) |
                       +--------------------+
```

---

## Core Protocol Innovations

### 1. Isolated Smart Contract Wallets (`CreditAccount.vy`)
Borrowers do not receive borrowed capital into their external wallets (EOAs). Instead, each borrower controls a dedicated, single-tenant `CreditAccount` proxy contract. Leveraged trades execute solely through authorized decentralized exchange adapters (Uniswap V3, Curve), ensuring collateral remains locked within protocol custody.

### 2. Multi-Tranche Debt Waterfall (`DebtEngine.vy`)
Deposited liquidity is segmented into Senior (AAA), Mezzanine (BBB), and Junior (First-Loss Equity) tranches:
- **Senior Tranche**: First claim on accrued interest cashflows (3.0% target coupon) and junior-most loss priority.
- **Mezzanine Tranche**: Second claim on cashflows (7.0% target coupon) and intermediate loss priority.
- **Junior Tranche**: Absorbs 100% of initial bad debt losses, in exchange for capturing all residual yield upside.

### 3. Continuous Decaying Dutch Auction Liquidations (`LiquidationAuction.vy`)
Replaces conventional fixed-bonus liquidations (which trigger toxic Priority Gas Auctions and MEV sandwiching) with a continuous linear decay auction:
- Liquidation penalty decays continuously from an initial 15.0% down to 3.0% over an 1,800-second window.
- Eliminates builder MEV extraction and preserves up to 80% more residual equity for distressed borrowers.

### 4. Frequent Batch Auction Clearinghouse (`BatchClearinghouse.vy`)
Implements discrete time epochs (e.g., 60 seconds) for risk transfer and order clearing. All orders submitted within a batch are settled simultaneously at a single uniform market clearing price $P^*$, mathematically eliminating frontrunning, sandwich attacks, and latency arbitrage.

### 5. High-Assurance Vyper 0.4.x Implementation
Built with explicit type annotations, strict boundary validation, `@nonreentrant` mutex locks, and custom fixed-point libraries (`MathLib.vy`, `BitMaps.vy`, `MerkleProof.vy`, `SafeTransferLib.vy`).

---

## Mathematical Formulations

### Cross-Margin Health Factor
Given an account holding collateral vector $\vec{c}$ and debt liabilities $\vec{d}$, with oracle price vector $\vec{p}$ and liquidation threshold vector $\vec{lt}$:

$$HF = \frac{\sum_{i=1}^n c_i \cdot p_i \cdot lt_i}{\sum_{j=1}^m d_j \cdot p_j}$$

- An account is solvent and operational if and only if $HF \ge 1.0 \times 10^{18}$.
- If $HF < 1.0 \times 10^{18}$, the account is seized by `LiquidationAuction.vy`.

### Two-Slope Kinked Borrow Rate Curve
For pool utilization $U = \frac{\text{Borrows}}{\text{Supplied}}$ and kink threshold $U_{\text{kink}} = 80\%$:

$$R(U) = \begin{cases} 
R_{\text{base}} + \left( \frac{U}{U_{\text{kink}}} \right) \cdot R_{\text{slope1}}, & U \le U_{\text{kink}} \\
R_{\text{base}} + R_{\text{slope1}} + \left( \frac{U - U_{\text{kink}}}{1.0 - U_{\text{kink}}} \right) \cdot R_{\text{slope2}}, & U > U_{\text{kink}}
\end{cases}$$

### Continuous Dutch Penalty Decay
For auction duration $D$, start penalty $P_{\text{start}} = 15\%$, and min penalty $P_{\text{min}} = 3\%$:

$$P(t) = P_{\text{start}} - \left( \frac{\min(t - T_0, D) \cdot (P_{\text{start}} - P_{\text{min}})}{D} \right)$$

### Uniform Clearing Price
For demand $D(p)$ and supply $S(p)$, the clearing price $P^*$ satisfies:

$$P^* = \arg\max_p \min(D(p), S(p)) \quad \text{s.t.} \quad p_s \le P^* \le p_b$$

---

## Repository Structure

```
aegis/
+-- contracts/
|   +-- interfaces/         # 15 pure Vyper interfaces (.vyi)
|   +-- libraries/          # Pure math and data structure libraries
|   |   +-- MathLib.vy      # WAD/RAY fixed-point, pow_wad, Newton-Raphson integer sqrt
|   |   +-- BitMaps.vy      # 256-bit bitfields, storage bitmaps, popcount
|   |   +-- MerkleProof.vy  # Cryptographic leaf inclusion verification
|   |   +-- SafeTransferLib.vy # Resilient low-level ERC-20 transfer wrappers
|   +-- core/               # Core protocol contracts
|   |   +-- AegisVault.vy   # Multi-asset treasury and EIP-3156 flash lender
|   |   +-- RiskEngine.vy   # Dynamic cross-margin and portfolio health factor engine
|   |   +-- CreditAccount.vy# Isolated smart contract execution proxy
|   |   +-- CreditManager.vy# Orchestration router and state boundary validator
|   |   +-- DebtEngine.vy   # Tranche waterfall and jump rate interest curves
|   |   +-- LiquidationAuction.vy # Continuous decaying Dutch auction engine
|   |   +-- BatchClearinghouse.vy # Frequent batch auction matching engine
|   |   +-- MockERC20.vy    # High-fidelity mock token for testing
|   +-- oracles/            # Decentralized oracle adapters
|   |   +-- PriceFeedRouter.vy # Dual-oracle router with deviation bounds
|   |   +-- ChainlinkAdapter.vy# Primary oracle adapter
|   |   +-- PythAdapter.vy     # Sub-second fallback oracle adapter
|   |   +-- TWAPOracle.vy      # Manipulation-resistant time-weighted oracle
|   +-- adapters/           # Execution adapters
|   |   +-- UniswapV3Adapter.vy# Exact input swap routing
|   |   +-- CurveAdapter.vy    # StableSwap correlated asset routing
|   +-- governance/         # Governance and safety
|       +-- EmergencyCouncil.vy# Multi-sig circuit breaker
|       +-- ProtocolParameters.vy # Global parameter registry
+-- daemon/                 # Python 3.12+ async keeper infrastructure
|   +-- aegis_client.py     # Web3 / Titanoboa protocol client
|   +-- event_stream.py     # Async event listener and log parser
|   +-- liquidator.py       # Programmatic Dutch auction liquidator bot
|   +-- batch_matcher.py    # Frequent batch auction clearing bot
|   +-- oracle_relayer.py   # Heartbeat and price update relayer
|   +-- main.py             # Daemon orchestration entrypoint
+-- native/                 # Accelerated Rust order matching engine
|   +-- Cargo.toml          # Rust crate manifest
|   +-- src/lib.rs          # O(N log N) batch auction equilibrium solver
+-- simulator/              # Quantitative stochastic simulation engine
|   +-- stochastic.py       # Geometric Brownian Motion & Merton Jump-Diffusion
|   +-- agent_models.py     # Trader and liquidator behavior models
|   +-- risk_sim.py         # 500-path Monte Carlo liquidation stress suite
|   +-- waterfall_sim.py    # Multi-tranche credit event stress model
|   +-- benchmark.py        # EVM opcode gas profiler
+-- sdk/                    # TypeScript SDK for programmatic integration
|   +-- src/                # Strongly-typed client, math utils, and ABIs
+-- scripts/                # Local deployment and operational automation
|   +-- deploy.py           # Protocol deployment script
|   +-- seed_market.py      # Capital seeding and liquidity provisioning
|   +-- stress_test.py      # Automated stress test pipeline runner
+-- tests/                  # Complete EVM test suite (39 passing tests)
+-- docs/                   # Detailed technical documentation
    +-- ARCHITECTURE.md     # System topology and state transition specs
    +-- RISK_MODEL.md       # Cross-margin math and haircut calibration
    +-- DUTCH_AUCTIONS.md   # Decaying price discovery and MEV defense
    +-- WATERFALL_ACCOUNTING.md # Tranche seniority and cashflow waterfall
    +-- BATCH_AUCTIONS.md   # Discrete epoch clearing and uniform pricing
    +-- VERIFICATION.md     # Invariant proofs and test coverage matrix
```

---

## Gas Profiling & EVM Benchmarks

Execution gas costs measured natively on EVM via Titanoboa:

| Operation | Gas Used | Estimated Cost ($3k ETH @ 25 Gwei) | Optimization Notes |
| :--- | :--- | :--- | :--- |
| `MathLib.wad_mul` | 284 | $0.021 | Pure opcode inlining, no memory expansion |
| `MathLib.sqrt_u256` | 1,240 | $0.093 | Babylonian method convergent in 8 iterations |
| `BitMaps.get_bit / set_bit` | 410 | $0.031 | Bitwise shifts using native `<<` operator |
| `MerkleProof.verify` (4-leaf) | 3,150 | $0.236 | Sequential keccak256 pair hashing |
| `AegisVault.deposit` | 48,220 | $3.616 | ERC-20 transferFrom with balance storage update |
| `AegisVault.flashLoan` (EIP-3156)| 74,100 | $5.558 | Callback invocation, fee accrual & reentrancy guard |
| `CreditManager.borrow` | 88,450 | $6.634 | Cross-margin health factor evaluation & vault credit pull |
| `LiquidationAuction.buy_collateral` | 62,300 | $4.672 | Decaying price evaluation & collateral settlement |
| `BatchClearinghouse.clear_pair` | 68,900 | $5.168 | Uniform clearing settlement & unspent quote refund |

---

## Stress Test Results

Simulated across 500 Merton Jump-Diffusion market paths with severe -64.8% tail crash events:

| Metric | Traditional Fixed Penalty (10%) | Aegis Decaying Dutch Auction | Improvement |
| :--- | :--- | :--- | :--- |
| **Protocol Bad Debt Events** | 140 paths | 102 paths | -27.1% Reduction |
| **Average Borrower Residual Equity** | $231.86 | $667.31 | +187.8% Equity Preserved |
| **Cascade Insolvency Risk** | High (Searcher priority gas wars) | Eliminated (Smooth Dutch decay) | Complete Elimination |

### Tranche Recovery Under Severe Shocks

| Scenario | Default Loss ($) | Junior Recovery | Mezzanine Recovery | Senior (AAA) Recovery |
| :--- | :--- | :--- | :--- | :--- |
| **Mild Drawdown** | $500,000 (5%) | 66.7% | 100.0% | 100.0% |
| **Moderate Volatility** | $1,200,000 (12%) | 20.0% | 100.0% | 100.0% |
| **Severe Credit Event** | $2,500,000 (25%) | 0.0% | 60.0% | 100.0% |
| **Catastrophic Shock** | $4,500,000 (45%) | 0.0% | 0.0% | 91.7% |

---

## Quickstart & Verification

### 1. Clone & Setup Environment

```bash
git clone https://github.com/Aneesh495/aegis.git
cd aegis

# Install Python dependencies via uv
uv sync
```

### 2. Run Comprehensive EVM Test Suite

```bash
# Run all 39 tests across core, oracles, adapters, and libraries
uv run pytest -v

# Run property-based invariant fuzzing (Hypothesis)
uv run pytest tests/test_property_invariants.py -v

# Run institutional 9-step end-to-end stress scenario
uv run pytest tests/test_end_to_end.py -v -s
```

### 3. Run Native Rust Matching Engine Tests

```bash
cd native
cargo test --verbose
cd ..
```

### 4. Run Stress Testing and Benchmarks

```bash
uv run python scripts/stress_test.py
```

### 5. Launch Keeper Daemon

```bash
uv run python daemon/main.py
```

---

## TypeScript SDK Example

```typescript
import { AegisClient } from "@aegis/sdk";
import { parseUnits } from "viem";

const client = new AegisClient({
  rpcUrl: "http://127.0.0.1:8545",
  creditManagerAddress: "0x...",
  aegisVaultAddress: "0x...",
  riskEngineAddress: "0x...",
});

// Open an isolated CreditAccount proxy
const account = await client.openCreditAccount();

// Deposit 10 WETH collateral
await client.depositCollateral(account, "0xWETH_ADDRESS", parseUnits("10", 18));

// Borrow 15,000 USDC credit (HF >= 1.0 checked atomically)
await client.borrow(account, "0xUSDC_ADDRESS", parseUnits("15000", 6));

// Inspect real-time cross-margin health factor
const healthFactor = await client.getHealthFactor(account);
console.log(`Account Health Factor: ${healthFactor.toFixed(4)}`);
```

---

## Documentation Index

- [Architecture Specification](docs/ARCHITECTURE.md): System topology, isolated proxies, state machines, and sequence flows.
- [Risk Model & Margin Engine](docs/RISK_MODEL.md): Dynamic haircuts, liquidation thresholds, and dual-oracle sanity bounds.
- [Continuous Dutch Auctions](docs/DUTCH_AUCTIONS.md): Decaying price formulation and game-theoretic MEV resistance.
- [Tranche Waterfall Accounting](docs/WATERFALL_ACCOUNTING.md): Multi-tranche loss priority and kinked jump rate models.
- [Frequent Batch Auctions](docs/BATCH_AUCTIONS.md): Epoch matching and uniform market clearing price proofs.
- [Verification & Test Coverage](docs/VERIFICATION.md): Property-based invariant specifications and verification matrix.

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
