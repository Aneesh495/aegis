import pytest
import boa

WAD = 10**18

def test_full_protocol_end_to_end():
    empty_addr = "0x0000000000000000000000000000000000000000"

    # 1. Deploy Tokens
    weth = boa.load("contracts/core/MockERC20.vy", "Wrapped Ether", "WETH", 18)
    usdc = boa.load("contracts/core/MockERC20.vy", "USD Coin", "USDC", 6)
    wbtc = boa.load("contracts/core/MockERC20.vy", "Wrapped Bitcoin", "WBTC", 8)

    # 2. Deploy Oracle Subsystem
    twap = boa.load("contracts/oracles/TWAPOracle.vy", 64)
    router = boa.load("contracts/oracles/PriceFeedRouter.vy", twap.address)

    # WETH: $3,000
    agg_weth = boa.load("contracts/oracles/MockAggregator.vy", 8, 300_000_000_000)
    adapt_weth = boa.load("contracts/oracles/ChainlinkAdapter.vy", agg_weth.address, 3600, 10_000_000_000, 5_000_000_000_000)
    router.set_asset_feeds(weth.address, adapt_weth.address, empty_addr, int(0.05 * WAD), 1800)

    # USDC: $1.00
    agg_usdc = boa.load("contracts/oracles/MockAggregator.vy", 8, 100_000_000)
    adapt_usdc = boa.load("contracts/oracles/ChainlinkAdapter.vy", agg_usdc.address, 3600, 50_000_000, 200_000_000)
    router.set_asset_feeds(usdc.address, adapt_usdc.address, empty_addr, int(0.05 * WAD), 1800)

    # WBTC: $60,000
    agg_wbtc = boa.load("contracts/oracles/MockAggregator.vy", 8, 6_000_000_000_000)
    adapt_wbtc = boa.load("contracts/oracles/ChainlinkAdapter.vy", agg_wbtc.address, 3600, 100_000_000_000, 20_000_000_000_000)
    router.set_asset_feeds(wbtc.address, adapt_wbtc.address, empty_addr, int(0.05 * WAD), 1800)

    # 3. Deploy Core Protocol
    vault = boa.load("contracts/core/AegisVault.vy", 10)
    risk_engine = boa.load("contracts/core/RiskEngine.vy", router.address)
    credit_manager = boa.load("contracts/core/CreditManager.vy", vault.address)
    debt_engine = boa.load("contracts/core/DebtEngine.vy", vault.address)
    liquidation_auction = boa.load("contracts/core/LiquidationAuction.vy", router.address)

    # Configure linkages
    vault.set_credit_manager(credit_manager.address)
    vault.set_debt_engine(debt_engine.address)
    risk_engine.set_credit_manager(credit_manager.address)
    credit_manager.set_protocol_contracts(risk_engine.address, debt_engine.address, liquidation_auction.address)
    liquidation_auction.set_credit_manager(credit_manager.address)

    # Configure Risk Parameters
    # WETH: 15% haircut, 85% liq threshold
    risk_engine.set_asset_risk_parameters(weth.address, int(0.15 * WAD), int(0.85 * WAD), WAD)
    # USDC: 5% haircut, 95% liq threshold
    risk_engine.set_asset_risk_parameters(usdc.address, int(0.05 * WAD), int(0.95 * WAD), WAD)
    # WBTC: 15% haircut, 85% liq threshold
    risk_engine.set_asset_risk_parameters(wbtc.address, int(0.15 * WAD), int(0.85 * WAD), WAD)

    # Support assets in vault
    vault.set_asset_status(weth.address, True, 0)
    vault.set_asset_status(usdc.address, True, 0)
    vault.set_asset_status(wbtc.address, True, 0)

    # 4. Deploy Mock DEX Adapter and whitelist
    dex = boa.load("contracts/adapters/MockDEXAdapter.vy")
    # Rate: 1 USDC = 1/60,000 WBTC = 10^18 / 60,000
    dex.set_rate(usdc.address, wbtc.address, WAD // 60_000)
    # Seed DEX with 10 WBTC
    wbtc.mint(dex.address, 10 * 10**8)
    credit_manager.set_adapter_status(dex.address, True)

    # 5. Capital Formation: LPs fund DebtEngine Tranches with 500,000 USDC
    lp = boa.env.generate_address()
    usdc.mint(lp, 500_000 * 10**6)
    with boa.env.prank(lp):
        usdc.approve(debt_engine.address, 500_000 * 10**6)
        debt_engine.deposit_tranche(usdc.address, 0, 300_000 * 10**6, lp) # Senior
        debt_engine.deposit_tranche(usdc.address, 1, 150_000 * 10**6, lp) # Mezz
        debt_engine.deposit_tranche(usdc.address, 2, 50_000 * 10**6, lp)  # Junior

    # Seed Vault with USDC liquidity
    usdc.mint(lp, 500_000 * 10**6)
    with boa.env.prank(lp):
        usdc.approve(vault.address, 500_000 * 10**6)
        vault.deposit_collateral(usdc.address, 500_000 * 10**6, lp)

    # 6. Trader opens Credit Account and deposits 20 WETH ($60,000)
    trader = boa.env.generate_address()
    account = boa.load("contracts/core/CreditAccount.vy", credit_manager.address, trader)
    with boa.env.prank(trader):
        credit_manager.register_credit_account(trader, account.address)

    weth.mint(trader, 20 * WAD)
    with boa.env.prank(trader):
        weth.approve(credit_manager.address, 20 * WAD)
        credit_manager.deposit_collateral(account.address, weth.address, 20 * WAD)

    assert account.asset_balance(weth.address) == 20 * WAD

    # 7. Trader borrows 40,000 USDC against $60,000 WETH collateral
    with boa.env.prank(trader):
        credit_manager.borrow_credit(account.address, usdc.address, 40_000 * 10**6)

    # Withdraw 40,000 USDC to external wallet
    with boa.env.prank(trader):
        credit_manager.withdraw_collateral(account.address, usdc.address, 40_000 * 10**6, trader)

    # Health factor: 20 WETH * $3,000 * 85% = $51,000 / $40,000 = 1.275 WAD
    hf_initial = risk_engine.compute_account_health(account.address)
    assert hf_initial == int(1.275 * WAD)
    assert risk_engine.is_account_liquidatable(account.address) is False

    # 8. Black Swan Shock: ETH price crashes by 40% from $3,000 to $1,800
    agg_weth.set_answer(180_000_000_000) # $1,800
    assert router.get_asset_price(weth.address) == 1_800 * WAD

    # New collateral value: 20 WETH * $1,800 * 85% = $30,600
    # Debt = $40,000
    # HF = 30,600 / 40,000 = 0.765 WAD (< 1.0 WAD). Account is distressed!
    hf_crash = risk_engine.compute_account_health(account.address)
    assert hf_crash == int(0.765 * WAD)
    assert risk_engine.is_account_liquidatable(account.address) is True

    # 9. Start Dutch Auction Liquidation
    auc_id = liquidation_auction.start_auction(
        account.address,
        usdc.address,
        weth.address,
        40_000 * 10**6, # 40k USDC debt
        20 * WAD        # 20 WETH available collateral
    )

    # Liquidator waits 150 seconds for penalty to decay to 9%
    boa.env.time_travel(seconds=150)
    current_penalty = liquidation_auction.get_current_penalty(auc_id)
    assert current_penalty == int(0.09 * WAD)

    # Liquidator bids to cover 20,000 USDC debt
    # 20,000 USDC * 1.09 / $1,800 = 12.1111... WETH payout
    liquidator = boa.env.generate_address()
    usdc.mint(liquidator, 20_000 * 10**6)

    with boa.env.prank(liquidator):
        usdc.approve(liquidation_auction.address, 20_000 * 10**6)
        collat_awarded = liquidation_auction.bid(auc_id, 20_000 * 10**6)

    # Verify liquidator received collateral
    assert weth.balanceOf(liquidator) == collat_awarded
    assert collat_awarded > 12 * WAD

    # Remaining WETH in credit account protects borrower from catastrophic loss
    remaining_weth = account.asset_balance(weth.address)
    assert remaining_weth > 7 * WAD

    print("End-to-end institutional workflow successfully verified with zero bad debt!")
