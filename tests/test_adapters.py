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
def mock_dex(weth, usdc):
    dex = boa.load("contracts/adapters/MockDEXAdapter.vy")
    # 1 WETH = 3,000 USDC. Rate for WETH -> USDC = 3,000 * 10^18
    dex.set_rate(weth.address, usdc.address, 3_000 * WAD)
    # 1 USDC = 1/3,000 WETH. Rate for USDC -> WETH = 10^18 / 3,000
    dex.set_rate(usdc.address, weth.address, WAD // 3_000)

    # Fund DEX with reserves (100 WETH and 300,000 USDC)
    user = boa.env.eoa
    weth.mint(dex.address, 100 * WAD)
    usdc.mint(dex.address, 300_000 * 10**6)
    return dex

def test_mock_dex_preview_and_swap(mock_dex, weth, usdc):
    user = boa.env.eoa
    weth.mint(user, 2 * WAD)
    weth.approve(mock_dex.address, 2 * WAD)

    # 2 WETH -> 6,000 USDC
    preview = mock_dex.preview_swap(weth.address, 2 * WAD, usdc.address, b"")
    assert preview == 6_000 * 10**6

    # Execute swap with min_out = 5,900 USDC (allows 100 USDC slippage)
    usdc_bal_before = usdc.balanceOf(user)
    out_amt = mock_dex.swap(
        weth.address,
        2 * WAD,
        usdc.address,
        5_900 * 10**6,
        user,
        b""
    )
    assert out_amt == 6_000 * 10**6
    assert usdc.balanceOf(user) == usdc_bal_before + 6_000 * 10**6

def test_mock_dex_slippage_revert(mock_dex, weth, usdc):
    user = boa.env.eoa
    weth.mint(user, 1 * WAD)
    weth.approve(mock_dex.address, 1 * WAD)

    # Output is 3,000 USDC, but we require 3,500 USDC
    with boa.reverts("MockDEX: slippage limit breached"):
        mock_dex.swap(
            weth.address,
            1 * WAD,
            usdc.address,
            3_500 * 10**6,
            user,
            b""
        )
