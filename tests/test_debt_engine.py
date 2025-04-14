import pytest
import boa

WAD = 10**18

@pytest.fixture
def usdc():
    return boa.load("contracts/core/MockERC20.vy", "USD Coin", "USDC", 6)

@pytest.fixture
def vault():
    return boa.load("contracts/core/AegisVault.vy", 10)

@pytest.fixture
def debt_engine(vault, usdc):
    de = boa.load("contracts/core/DebtEngine.vy", vault.address)
    # Interest model: Base 2%, Kink 80%, Slope1 4%, Slope2 60%
    de.configure_interest_model(
        usdc.address,
        int(0.02 * WAD), # 2% base
        int(0.80 * WAD), # 80% kink
        int(0.04 * WAD), # 4% slope 1
        int(0.60 * WAD)  # 60% slope 2
    )
    return de

def test_jump_rate_model(debt_engine, usdc):
    # At 0% utilization: borrow rate = base rate = 2%
    r0 = debt_engine.get_borrow_rate(usdc.address)
    assert r0 == int(0.02 * WAD)

    # Fake utilization by depositing and setting borrowed
    # Total supply 100,000
    # Deposit Senior 50,000, Mezz 30,000, Junior 20,000
    user = boa.env.eoa
    usdc.mint(user, 100_000 * 10**6)
    usdc.approve(debt_engine.address, 100_000 * 10**6)

    debt_engine.deposit_tranche(usdc.address, 0, 50_000 * 10**6, user) # Senior
    debt_engine.deposit_tranche(usdc.address, 1, 30_000 * 10**6, user) # Mezz
    debt_engine.deposit_tranche(usdc.address, 2, 20_000 * 10**6, user) # Junior

    assert debt_engine.get_total_supply(usdc.address) == 100_000 * 10**6

def test_waterfall_cashflow_distribution(debt_engine, usdc):
    user = boa.env.eoa
    usdc.mint(user, 100_000 * 10**6)
    usdc.approve(debt_engine.address, 100_000 * 10**6)

    # Senior: 50,000 USDC
    debt_engine.deposit_tranche(usdc.address, 0, 50_000 * 10**6, user)
    # Mezz: 30,000 USDC
    debt_engine.deposit_tranche(usdc.address, 1, 30_000 * 10**6, user)
    # Junior: 20,000 USDC
    debt_engine.deposit_tranche(usdc.address, 2, 20_000 * 10**6, user)

    # Distribute $10,000 cash flow
    # Senior 3% of 50,000 = $1,500
    # Mezz 7% of 30,000 = $2,100
    # Remaining = 10,000 - 1,500 - 2,100 = $6,400 flows entirely to Junior!
    debt_engine.distribute_cashflow(usdc.address, 10_000 * 10**6)

    assert debt_engine.get_tranche_supply(usdc.address, 0) == 51_500 * 10**6
    assert debt_engine.get_tranche_supply(usdc.address, 1) == 32_100 * 10**6
    assert debt_engine.get_tranche_supply(usdc.address, 2) == 26_400 * 10**6 # +32% return on Junior!

    # Check share price of Junior: 26,400 / 20,000 = 1.32 WAD
    junior_price = debt_engine.get_tranche_share_price(usdc.address, 2)
    assert junior_price == int(1.32 * WAD)

def test_bad_debt_loss_waterfall(debt_engine, usdc):
    user = boa.env.eoa
    usdc.mint(user, 100_000 * 10**6)
    usdc.approve(debt_engine.address, 100_000 * 10**6)

    debt_engine.deposit_tranche(usdc.address, 0, 50_000 * 10**6, user) # Senior 50k
    debt_engine.deposit_tranche(usdc.address, 1, 30_000 * 10**6, user) # Mezz 30k
    debt_engine.deposit_tranche(usdc.address, 2, 20_000 * 10**6, user) # Junior 20k

    # Case 1: Bad debt of $15,000. Junior absorbs all 15k!
    j_loss, m_loss, s_loss = debt_engine.absorb_bad_debt(usdc.address, 15_000 * 10**6)
    assert j_loss == 15_000 * 10**6
    assert m_loss == 0
    assert s_loss == 0
    assert debt_engine.get_tranche_supply(usdc.address, 2) == 5_000 * 10**6
    assert debt_engine.get_tranche_supply(usdc.address, 1) == 30_000 * 10**6
    assert debt_engine.get_tranche_supply(usdc.address, 0) == 50_000 * 10**6

    # Case 2: Additional catastrophic bad debt of $20,000.
    # Junior remaining 5k is wiped out. Mezz absorbs 15k. Senior remains 100% intact!
    j_loss2, m_loss2, s_loss2 = debt_engine.absorb_bad_debt(usdc.address, 20_000 * 10**6)
    assert j_loss2 == 5_000 * 10**6
    assert m_loss2 == 15_000 * 10**6
    assert s_loss2 == 0
    assert debt_engine.get_tranche_supply(usdc.address, 2) == 0
    assert debt_engine.get_tranche_supply(usdc.address, 1) == 15_000 * 10**6
    assert debt_engine.get_tranche_supply(usdc.address, 0) == 50_000 * 10**6
