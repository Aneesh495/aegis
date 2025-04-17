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

    mock_agg_weth = boa.load("contracts/oracles/MockAggregator.vy", 8, 300_000_000_000) # $3,000
    adapter_weth = boa.load("contracts/oracles/ChainlinkAdapter.vy", mock_agg_weth.address, 3600, 10_000_000_000, 5_000_000_000_000)
    router.set_asset_feeds(weth.address, adapter_weth.address, empty_addr, int(0.05 * WAD), 1800)

    mock_agg_usdc = boa.load("contracts/oracles/MockAggregator.vy", 8, 100_000_000) # $1.00
    adapter_usdc = boa.load("contracts/oracles/ChainlinkAdapter.vy", mock_agg_usdc.address, 3600, 50_000_000, 200_000_000)
    router.set_asset_feeds(usdc.address, adapter_usdc.address, empty_addr, int(0.05 * WAD), 1800)

    return router

@pytest.fixture
def auction(price_router):
    return boa.load("contracts/core/LiquidationAuction.vy", price_router.address)

def test_auction_penalty_decay(auction, weth, usdc):
    account = boa.env.generate_address()
    debt_amount = 10_000 * 10**6 # 10,000 USDC
    collat_amount = 5 * WAD       # 5 WETH

    auc_id = auction.start_auction(
        account,
        usdc.address,
        weth.address,
        debt_amount,
        collat_amount
    )

    # At t=0: penalty = 15% (0.15 WAD)
    p0 = auction.get_current_penalty(auc_id)
    assert p0 == int(0.15 * WAD)

    # At t=150s: penalty = 9% (0.09 WAD)
    boa.env.time_travel(seconds=150)
    p150 = auction.get_current_penalty(auc_id)
    assert p150 == int(0.09 * WAD)

    # At t=300s: penalty = 3% (0.03 WAD)
    boa.env.time_travel(seconds=150)
    p300 = auction.get_current_penalty(auc_id)
    assert p300 == int(0.03 * WAD)

    # Past 300s: penalty remains clamped at floor 3%
    boa.env.time_travel(seconds=100)
    p400 = auction.get_current_penalty(auc_id)
    assert p400 == int(0.03 * WAD)

def test_auction_collateral_payout_calculation(auction, weth, usdc):
    account = boa.env.generate_address()
    debt_amount = 10_000 * 10**6 # 10,000 USDC
    collat_amount = 10 * WAD      # 10 WETH ($30,000)

    auc_id = auction.start_auction(
        account,
        usdc.address,
        weth.address,
        debt_amount,
        collat_amount
    )

    # At t=0, penalty = 15%
    # To cover 3,000 USDC (which is 1 WETH at spot $3,000)
    # With 15% penalty, liquidator receives 1.15 WETH
    payout = auction.get_collateral_payout(auc_id, 3_000 * 10**6)
    assert payout == (115 * WAD) // 100

    # Advance 150s, penalty = 9%
    boa.env.time_travel(seconds=150)
    payout_mid = auction.get_collateral_payout(auc_id, 3_000 * 10**6)
    assert payout_mid == (109 * WAD) // 100

    # Advance to 300s, penalty = 3%
    boa.env.time_travel(seconds=150)
    payout_end = auction.get_collateral_payout(auc_id, 3_000 * 10**6)
    assert payout_end == (103 * WAD) // 100
