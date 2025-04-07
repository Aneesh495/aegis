import pytest
import boa

WAD = 10**18

@pytest.fixture
def weth():
    return boa.load("contracts/core/MockERC20.vy", "Wrapped Ether", "WETH", 18)

@pytest.fixture
def usdc():
    return boa.load("contracts/core/MockERC20.vy", "USD Coin", "USDC", 6)

@pytest.fixture
def twap_oracle():
    return boa.load("contracts/oracles/TWAPOracle.vy", 64)

@pytest.fixture
def price_router(twap_oracle, weth, usdc):
    router = boa.load("contracts/oracles/PriceFeedRouter.vy", twap_oracle.address)

    empty_addr = "0x0000000000000000000000000000000000000000"
    # WETH oracle at $3,000 (8 decimals)
    mock_agg_weth = boa.load("contracts/oracles/MockAggregator.vy", 8, 300_000_000_000)
    adapter_weth = boa.load("contracts/oracles/ChainlinkAdapter.vy", mock_agg_weth.address, 3600, 10_000_000_000, 5_000_000_000_000)
    router.set_asset_feeds(weth.address, adapter_weth.address, empty_addr, int(0.05 * WAD), 1800)

    # USDC oracle at $1.00 (8 decimals)
    mock_agg_usdc = boa.load("contracts/oracles/MockAggregator.vy", 8, 100_000_000)
    adapter_usdc = boa.load("contracts/oracles/ChainlinkAdapter.vy", mock_agg_usdc.address, 3600, 50_000_000, 200_000_000)
    router.set_asset_feeds(usdc.address, adapter_usdc.address, empty_addr, int(0.05 * WAD), 1800)

    return router

@pytest.fixture
def vault():
    return boa.load("contracts/core/AegisVault.vy", 10)

@pytest.fixture
def risk_engine(price_router, weth, usdc):
    re = boa.load("contracts/core/RiskEngine.vy", price_router.address)
    # WETH: haircut 15%, liquidation threshold 85%, borrow factor 100%
    re.set_asset_risk_parameters(weth.address, int(0.15 * WAD), int(0.85 * WAD), WAD)
    # USDC: haircut 5%, liquidation threshold 95%, borrow factor 100%
    re.set_asset_risk_parameters(usdc.address, int(0.05 * WAD), int(0.95 * WAD), WAD)
    return re

@pytest.fixture
def credit_manager(vault, risk_engine):
    cm = boa.load("contracts/core/CreditManager.vy", vault.address)
    vault.set_credit_manager(cm.address)
    risk_engine.set_credit_manager(cm.address)
    cm.set_protocol_contracts(risk_engine.address, boa.env.generate_address(), boa.env.generate_address())
    return cm

def test_credit_account_lifecycle(credit_manager, vault, risk_engine, weth, usdc):
    borrower = boa.env.eoa
    # Deploy CreditAccount proxy for borrower
    account = boa.load("contracts/core/CreditAccount.vy", credit_manager.address, borrower)
    credit_manager.register_credit_account(borrower, account.address)

    assert credit_manager.get_credit_account(borrower) == account.address
    assert credit_manager.get_account_owner(account.address) == borrower

    # Support assets in vault
    vault.set_asset_status(weth.address, True, 0)
    vault.set_asset_status(usdc.address, True, 0)

    # Seed borrower with 10 WETH ($30,000)
    weth.mint(borrower, 10 * WAD)
    weth.approve(credit_manager.address, 10 * WAD)

    # Deposit 10 WETH collateral
    credit_manager.deposit_collateral(account.address, weth.address, 10 * WAD)
    assert account.asset_balance(weth.address) == 10 * WAD

    # Seed Vault with USDC liquidity (100,000 USDC)
    lender = boa.env.generate_address()
    usdc.mint(lender, 100_000 * 10**6)
    with boa.env.prank(lender):
        usdc.approve(vault.address, 100_000 * 10**6)
        vault.deposit_collateral(usdc.address, 100_000 * 10**6, lender)

    # Borrow 20,000 USDC against 10 WETH ($30,000 collat * 85% liq threshold = $25,500 borrowing power)
    credit_manager.borrow_credit(account.address, usdc.address, 20_000 * 10**6)
    assert credit_manager.get_account_debt(account.address, usdc.address) == 20_000 * 10**6
    assert account.asset_balance(usdc.address) == 20_000 * 10**6

    # Withdraw the borrowed 20,000 USDC to borrower's external wallet
    credit_manager.withdraw_collateral(account.address, usdc.address, 20_000 * 10**6, borrower)
    assert usdc.balanceOf(borrower) == 20_000 * 10**6
    assert account.asset_balance(usdc.address) == 0

    # Account now only has 10 WETH ($25,500 adjusted value) vs $20,000 debt
    # HF = 25,500 / 20,000 = 1.275 WAD
    hf = risk_engine.compute_account_health(account.address)
    assert hf == int(1.275 * WAD)
    assert risk_engine.is_account_liquidatable(account.address) is False

    # Attempt to withdraw 5 WETH ($15,000) leaving only $12,750 threshold < $20,000 debt
    with boa.reverts("CreditManager: withdrawal leaves account underwater"):
        credit_manager.withdraw_collateral(account.address, weth.address, 5 * WAD, borrower)

    # Repay 10,000 USDC from borrower's external wallet
    usdc.approve(credit_manager.address, 10_000 * 10**6)
    credit_manager.repay_credit(account.address, usdc.address, 10_000 * 10**6)
    assert credit_manager.get_account_debt(account.address, usdc.address) == 10_000 * 10**6

    # New HF = 25,500 / 10,000 = 2.55 WAD
    assert risk_engine.compute_account_health(account.address) == int(2.55 * WAD)
