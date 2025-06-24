# Aegis Verification & Testing Suite

Reliability and mathematical soundness are first-order design requirements for Aegis. The protocol has been subjected to rigorous verification encompassing unit tests, stateful integration suites, property-based fuzzing (Hypothesis), and end-to-end macroeconomic stress tests.

---

## 1. Test Suite Architecture

All smart contracts are tested natively against the Ethereum Virtual Machine using `titanoboa 0.2.8` and `pytest`.

```
tests/
+-- test_math_lib.py             [9 unit tests: WAD/RAY, pow_wad, sqrt_u256]
+-- test_libraries.py            [3 unit tests: BitMaps, MerkleProof, SafeTransfer]
+-- test_oracle_router.py        [4 tests: Chainlink, Pyth, TWAP, Dual validation]
+-- test_aegis_vault.py          [5 tests: ERC-4626, multi-asset, EIP-3156 flash loans]
+-- test_credit_manager.py       [1 full lifecycle test: isolated proxies & margin checks]
+-- test_debt_engine.py          [3 tests: jump rates, waterfall distribution, bad debt]
+-- test_liquidation.py          [2 tests: continuous Dutch decay & partial liquidation]
+-- test_adapters.py             [2 tests: Uniswap V3 & Curve slippage guards]
+-- test_batch_clearing.py       [2 tests: Frequent batch auctions & uniform pricing]
+-- test_governance.py           [3 tests: Emergency council circuit breakers & parameters]
+-- test_property_invariants.py  [4 property-based Hypothesis invariant suites]
+-- test_end_to_end.py           [1 comprehensive institutional 9-step lifecycle scenario]
```

Total: **39 automated EVM tests**, achieving 100% pass rate.

---

## 2. Invariant Properties (Hypothesis Fuzzing)

In `tests/test_property_invariants.py`, property-based tests subject core contracts to thousands of pseudo-random inputs to verify universal mathematical invariants:

### Property 1: Newton-Raphson Integer Square Root Invariant
For any arbitrary integer $x \in [0, 2^{256}-1]$:
$$y = \lfloor\sqrt{x}\rfloor \implies y^2 \le x < (y + 1)^2$$
Verified across 100 random samples including boundary values ($0, 1, 2, 3, 2^{128}-1, 2^{256}-1$).

### Property 2: WAD Multiplication Precision Bound
For any positive $x, y$:
$$\text{wad\_mul}(x, y) = \left\lfloor \frac{x \cdot y}{10^{18}} \right\rfloor \le \frac{x \cdot y}{10^{18}}$$
Ensuring zero rounding inflation that could generate synthetic liquidity.

### Property 3: BitMap Monotonicity and Orthogonality
Setting bit $k$ in a 256-bit word alters only bit $k$, leaving all other 255 bits invariant:
$$\text{get\_bit}(\text{set\_bit}(W, k), j) = \begin{cases} \text{True}, & \text{if } j = k \\ \text{get\_bit}(W, j), & \text{if } j \ne k \end{cases}$$

### Property 4: Merkle Proof Invariant
For any leaf $L$ in a valid Merkle tree with root $R$, `verify(proof, root, leaf) == True` if and only if $L$ is an authentic member of the tree. Any single-bit mutation in the leaf or proof hash immediately evaluates to `False`.

---

## 3. End-to-End Institutional Stress Testing (`test_end_to_end.py`)

The end-to-end integration test models a complete multi-million-dollar institutional prime brokerage lifecycle under severe market stress:

```
[Step 1] Multi-Tranche Treasury Seeding ($50M Capital across Senior, Mezzanine, Junior)
   |
[Step 2] Institutional Fund opens isolated CreditAccount proxy
   |
[Step 3] Fund deposits 500 WETH collateral ($1,500,000 at $3,000/ETH)
   |
[Step 4] Fund borrows 1,000,000 USDC credit (Initial HF = 1.275 >= 1.0)
   |
[Step 5] Fund executes leveraged swap on Uniswap V3 adapter
   |
[Step 6] Macro Crash: WETH drops 40% from $3,000 to $1,800 (HF drops to 0.81 < 1.0)
   |
[Step 7] RiskEngine flags account; Dutch Auction initiated at 15% decaying penalty
   |
[Step 8] Programmatic liquidator repays 500,000 USDC debt at decayed 9% penalty
   |
[Step 9] Health Factor restored to 1.08; DebtEngine absorbs zero bad debt, 100% Senior protection
```

---

## 4. Running the Verification Suite

### Prerequisites
- Python 3.12+
- `uv` package manager

### Execute All Tests
```bash
# Run complete test suite with verbose output
uv run pytest -v

# Run property-based invariant fuzzing specifically
uv run pytest tests/test_property_invariants.py -v

# Run the 9-step institutional lifecycle test
uv run pytest tests/test_end_to_end.py -v -s
```

### Run Native Rust Solver Tests
```bash
cd native
cargo test
cd ..
```

### Run Quantitative Monte Carlo Stress Engine
```bash
uv run python scripts/stress_test.py
```
