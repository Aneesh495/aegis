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
def clearinghouse():
    # 60 second epoch duration
    return boa.load("contracts/core/BatchClearinghouse.vy", 60)

def test_batch_clearinghouse_uniform_settlement(clearinghouse, weth, usdc):
    buyer = boa.env.generate_address()
    seller = boa.env.generate_address()

    # Buyer has 10,000 USDC, submits buy order for 2 WETH at limit price $3,100 ($6,200 total)
    usdc.mint(buyer, 10_000 * 10**6)
    with boa.env.prank(buyer):
        usdc.approve(clearinghouse.address, 10_000 * 10**6)
        buy_id = clearinghouse.submit_order(
            weth.address,
            usdc.address,
            True,
            3_100 * WAD,
            2 * WAD
        )

    # Seller has 5 WETH, submits sell order for 2 WETH at limit price $2,900
    weth.mint(seller, 5 * WAD)
    with boa.env.prank(seller):
        weth.approve(clearinghouse.address, 5 * WAD)
        sell_id = clearinghouse.submit_order(
            weth.address,
            usdc.address,
            False,
            2_900 * WAD,
            2 * WAD
        )

    # Uniform clearing price is set to $3,000 (within [2900, 3100])
    clearing_price = 3_000 * WAD
    matched_base, matched_quote = clearinghouse.clear_pair(buy_id, sell_id, clearing_price)

    assert matched_base == 2 * WAD
    assert matched_quote == 6_000 * 10**6

    # Verify Buyer received 2 WETH
    assert weth.balanceOf(buyer) == 2 * WAD
    # Verify Buyer was refunded surplus $200 ($10,000 - $6,000 = $4,000 remaining USDC)
    assert usdc.balanceOf(buyer) == 4_000 * 10**6

    # Verify Seller received $6,000 USDC
    assert usdc.balanceOf(seller) == 6_000 * 10**6
    # Verify Seller remaining WETH = 3 WETH
    assert weth.balanceOf(seller) == 3 * WAD

def test_order_cancellation(clearinghouse, weth, usdc):
    trader = boa.env.generate_address()
    usdc.mint(trader, 5_000 * 10**6)

    with boa.env.prank(trader):
        usdc.approve(clearinghouse.address, 5_000 * 10**6)
        order_id = clearinghouse.submit_order(
            weth.address,
            usdc.address,
            True,
            3_000 * WAD,
            1 * WAD
        )
        assert usdc.balanceOf(trader) == 2_000 * 10**6

        # Cancel order
        clearinghouse.cancel_order(order_id)
        # 3,000 USDC refunded
        assert usdc.balanceOf(trader) == 5_000 * 10**6
