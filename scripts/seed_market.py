import os
import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import boa
from scripts.deploy import deploy_aegis_protocol

WAD = 10**18

def seed_market():
    sys = deploy_aegis_protocol()
    print("Seeding market liquidity...")

    lp = boa.env.generate_address()
    sys.usdc.mint(lp, 1_000_000 * 10**6)

    # Fund debt engine tranches
    with boa.env.prank(lp):
        sys.usdc.approve(sys.debt_engine.address, 1_000_000 * 10**6)
        sys.debt_engine.deposit_tranche(sys.usdc.address, 0, 600_000 * 10**6, lp) # Senior
        sys.debt_engine.deposit_tranche(sys.usdc.address, 1, 250_000 * 10**6, lp) # Mezz
        sys.debt_engine.deposit_tranche(sys.usdc.address, 2, 150_000 * 10**6, lp) # Junior

    # Deposit liquidity directly into vault
    sys.usdc.mint(lp, 1_000_000 * 10**6)
    with boa.env.prank(lp):
        sys.usdc.approve(sys.vault.address, 1_000_000 * 10**6)
        sys.vault.deposit_collateral(sys.usdc.address, 1_000_000 * 10**6, lp)

    # Create active sample credit account
    trader = boa.env.generate_address()
    account = boa.load("contracts/core/CreditAccount.vy", sys.credit_manager.address, trader)
    with boa.env.prank(trader):
        sys.credit_manager.register_credit_account(trader, account.address)

    sys.weth.mint(trader, 15 * WAD)
    with boa.env.prank(trader):
        sys.weth.approve(sys.credit_manager.address, 15 * WAD)
        sys.credit_manager.deposit_collateral(account.address, sys.weth.address, 15 * WAD)
        sys.credit_manager.borrow_credit(account.address, sys.usdc.address, 25_000 * 10**6)

    hf = sys.risk_engine.compute_account_health(account.address)
    print(f"Sample credit account active with Health Factor: {hf / 10**18:.3f}")

if __name__ == "__main__":
    seed_market()
