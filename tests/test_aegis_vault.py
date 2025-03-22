import pytest
import boa

WAD = 10**18

@pytest.fixture
def usdc():
    return boa.load("contracts/core/MockERC20.vy", "USD Coin", "USDC", 6)

@pytest.fixture
def weth():
    return boa.load("contracts/core/MockERC20.vy", "Wrapped Ether", "WETH", 18)

@pytest.fixture
def vault():
    # 10 bps flash fee = 0.10%
    return boa.load("contracts/core/AegisVault.vy", 10)

@pytest.fixture
def flash_borrower():
    return boa.load("contracts/core/MockFlashBorrower.vy")

def test_vault_deposit_and_withdraw(vault, usdc):
    user = boa.env.eoa
    # Configure asset
    vault.set_asset_status(usdc.address, True, 1_000_000 * 10**6)

    # Mint USDC to user and approve vault
    usdc.mint(user, 100_000 * 10**6)
    usdc.approve(vault.address, 100_000 * 10**6)

    # Deposit 50,000 USDC
    vault.deposit_collateral(usdc.address, 50_000 * 10**6, user)
    assert vault.total_reserve(usdc.address) == 50_000 * 10**6
    assert vault.available_liquidity(usdc.address) == 50_000 * 10**6
    assert usdc.balanceOf(vault.address) == 50_000 * 10**6

    # Withdraw 20,000 USDC
    vault.withdraw_collateral(usdc.address, 20_000 * 10**6, user)
    assert vault.total_reserve(usdc.address) == 30_000 * 10**6
    assert usdc.balanceOf(user) == 70_000 * 10**6

def test_vault_capacity_limit(vault, usdc):
    user = boa.env.eoa
    # Cap at 10,000 USDC
    vault.set_asset_status(usdc.address, True, 10_000 * 10**6)
    usdc.mint(user, 20_000 * 10**6)
    usdc.approve(vault.address, 20_000 * 10**6)

    # Exceeding capacity reverts
    with boa.reverts("AegisVault: capacity exceeded"):
        vault.deposit_collateral(usdc.address, 15_000 * 10**6, user)

def test_credit_allocation(vault, usdc):
    user = boa.env.eoa
    cm_mock = boa.env.generate_address()
    recipient = boa.env.generate_address()

    vault.set_asset_status(usdc.address, True, 0)
    vault.set_credit_manager(cm_mock)

    usdc.mint(user, 100_000 * 10**6)
    usdc.approve(vault.address, 100_000 * 10**6)
    vault.deposit_collateral(usdc.address, 100_000 * 10**6, user)

    # Allocate credit from credit manager
    with boa.env.prank(cm_mock):
        vault.allocate_credit(usdc.address, 40_000 * 10**6, recipient)

    assert vault.allocated_credit(usdc.address) == 40_000 * 10**6
    assert vault.available_liquidity(usdc.address) == 60_000 * 10**6
    assert usdc.balanceOf(recipient) == 40_000 * 10**6

def test_eip3156_flash_loan_success(vault, weth, flash_borrower):
    user = boa.env.eoa
    vault.set_asset_status(weth.address, True, 0)

    # Seed vault with 100 WETH
    weth.mint(user, 100 * WAD)
    weth.approve(vault.address, 100 * WAD)
    vault.deposit_collateral(weth.address, 100 * WAD, user)

    loan_amount = 10 * WAD
    expected_fee = vault.flashFee(weth.address, loan_amount)
    assert expected_fee == (10 * WAD * 10) // 10_000 # 0.01 WETH

    # Seed borrower with enough WETH to cover fee
    weth.mint(flash_borrower.address, expected_fee)

    # Execute flash loan
    success = vault.flashLoan(flash_borrower.address, weth.address, loan_amount, b"")
    assert success is True
    assert vault.protocol_fees(weth.address) == expected_fee

    # Sweep fees
    treasury = boa.env.generate_address()
    vault.sweep_protocol_fees(weth.address, treasury)
    assert weth.balanceOf(treasury) == expected_fee
    assert vault.protocol_fees(weth.address) == 0

def test_eip3156_flash_loan_rejection(vault, weth, flash_borrower):
    user = boa.env.eoa
    vault.set_asset_status(weth.address, True, 0)
    weth.mint(user, 50 * WAD)
    weth.approve(vault.address, 50 * WAD)
    vault.deposit_collateral(weth.address, 50 * WAD, user)

    # Trigger failure on callback
    flash_borrower.set_should_fail(True)
    with boa.reverts("AegisVault: flash loan callback rejected"):
        vault.flashLoan(flash_borrower.address, weth.address, 5 * WAD, b"")
