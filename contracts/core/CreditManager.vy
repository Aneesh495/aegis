# @version ^0.4.0
"""
@title CreditManager
@notice Prime brokerage account factory, risk controller, and trade execution router.
@dev Enforces health factor invariants at every state boundary and manages adapter authorizations.
"""

from ethereum.ercs import IERC20

interface IAegisVault:
    def allocate_credit(asset: address, amount: uint256, recipient: address): nonpayable
    def repay_credit(asset: address, amount: uint256, from_account: address): nonpayable

interface IRiskEngine:
    def compute_account_health(account: address) -> uint256: view
    def is_account_liquidatable(account: address) -> bool: view

interface ICreditAccount:
    def execute(target: address, call_data: Bytes[2048], eth_value: uint256) -> Bytes[2048]: nonpayable
    def safe_approve(token: address, spender: address, amount: uint256): nonpayable
    def transfer_asset(token: address, recipient: address, amount: uint256): nonpayable
    def asset_balance(asset: address) -> uint256: view

interface IExchangeAdapter:
    def swap(
        asset_in: address,
        amount_in: uint256,
        asset_out: address,
        min_amount_out: uint256,
        recipient: address,
        trade_data: Bytes[1024]
    ) -> uint256: nonpayable

owner: public(address)
vault: public(address)
risk_engine: public(address)
debt_engine: public(address)
liquidation_auction: public(address)

# Account tracking
borrower_to_account: public(HashMap[address, address])
account_to_owner: public(HashMap[address, address])
all_accounts: public(DynArray[address, 1024])

# Per-account asset rosters
account_collateral_assets: public(HashMap[address, DynArray[address, 16]])
account_borrowed_assets: public(HashMap[address, DynArray[address, 16]])
account_debt: public(HashMap[address, HashMap[address, uint256]])

# Whitelisted execution adapters
is_whitelisted_adapter: public(HashMap[address, bool])

WAD: constant(uint256) = 1_000_000_000_000_000_000

event AccountOpened:
    borrower: indexed(address)
    account: indexed(address)

event CollateralDeposited:
    account: indexed(address)
    asset: indexed(address)
    amount: uint256

event CollateralWithdrawn:
    account: indexed(address)
    asset: indexed(address)
    amount: uint256
    recipient: address

event BorrowExecuted:
    account: indexed(address)
    asset: indexed(address)
    amount: uint256

event RepayExecuted:
    account: indexed(address)
    asset: indexed(address)
    amount: uint256

event TradeExecuted:
    account: indexed(address)
    adapter: indexed(address)
    asset_in: address
    amount_in: uint256
    asset_out: address
    amount_out: uint256

event AdapterStatusChanged:
    adapter: indexed(address)
    approved: bool

@deploy
def __init__(vault_address: address):
    self.owner = msg.sender
    self.vault = vault_address

@external
def set_protocol_contracts(risk_eng: address, debt_eng: address, liq_auction: address):
    assert msg.sender == self.owner, "CreditManager: unauthorized"
    self.risk_engine = risk_eng
    self.debt_engine = debt_eng
    self.liquidation_auction = liq_auction

@external
def set_adapter_status(adapter: address, approved: bool):
    assert msg.sender == self.owner, "CreditManager: unauthorized"
    self.is_whitelisted_adapter[adapter] = approved
    log AdapterStatusChanged(adapter=adapter, approved=approved)

@external
def register_credit_account(borrower: address, account: address):
    """
    @notice Registers an instantiated CreditAccount for a borrower.
    """
    assert msg.sender == self.owner or msg.sender == borrower, "CreditManager: unauthorized"
    assert self.borrower_to_account[borrower] == empty(address), "CreditManager: account exists"
    assert account != empty(address), "CreditManager: zero account"

    self.borrower_to_account[borrower] = account
    self.account_to_owner[account] = borrower
    self.all_accounts.append(account)
    log AccountOpened(borrower=borrower, account=account)

@view
@external
def get_credit_account(borrower: address) -> address:
    return self.borrower_to_account[borrower]

@view
@external
def get_account_owner(account: address) -> address:
    return self.account_to_owner[account]

@view
@external
def get_account_assets(account: address) -> DynArray[address, 16]:
    return self.account_collateral_assets[account]

@view
@external
def get_account_borrowed_assets(account: address) -> DynArray[address, 16]:
    return self.account_borrowed_assets[account]

@view
@external
def get_account_debt(account: address, asset: address) -> uint256:
    return self.account_debt[account][asset]

@internal
def _ensure_collateral_asset(account: address, asset: address):
    assets: DynArray[address, 16] = self.account_collateral_assets[account]
    for a: address in assets:
        if a == asset:
            return
    assert len(assets) < 16, "CreditManager: max collateral assets reached"
    self.account_collateral_assets[account].append(asset)

@internal
def _ensure_borrowed_asset(account: address, asset: address):
    assets: DynArray[address, 16] = self.account_borrowed_assets[account]
    for a: address in assets:
        if a == asset:
            return
    assert len(assets) < 16, "CreditManager: max borrowed assets reached"
    self.account_borrowed_assets[account].append(asset)

@external
def deposit_collateral(account: address, asset: address, amount: uint256):
    assert self.account_to_owner[account] != empty(address), "CreditManager: invalid account"
    assert amount > 0, "CreditManager: zero deposit"

    self._ensure_collateral_asset(account, asset)

    # Transfer tokens from caller directly into the CreditAccount proxy
    call_data: Bytes[100] = concat(
        method_id("transferFrom(address,address,uint256)"),
        convert(msg.sender, bytes32),
        convert(account, bytes32),
        convert(amount, bytes32)
    )
    res: Bytes[32] = raw_call(asset, call_data, max_outsize=32)
    if len(res) > 0:
        assert convert(res, bool), "CreditManager: deposit transfer failed"

    log CollateralDeposited(account=account, asset=asset, amount=amount)

@external
def withdraw_collateral(account: address, asset: address, amount: uint256, recipient: address):
    assert msg.sender == self.account_to_owner[account], "CreditManager: not account owner"
    assert amount > 0, "CreditManager: zero withdrawal"

    # Transfer asset from CreditAccount to recipient
    extcall ICreditAccount(account).transfer_asset(asset, recipient, amount)

    # Verify post-withdrawal solvency
    if len(self.account_borrowed_assets[account]) > 0:
        hf: uint256 = staticcall IRiskEngine(self.risk_engine).compute_account_health(account)
        assert hf >= WAD, "CreditManager: withdrawal leaves account underwater"

    log CollateralWithdrawn(account=account, asset=asset, amount=amount, recipient=recipient)

@external
def borrow_credit(account: address, asset: address, amount: uint256):
    assert msg.sender == self.account_to_owner[account], "CreditManager: not account owner"
    assert amount > 0, "CreditManager: zero borrow"

    self._ensure_borrowed_asset(account, asset)
    self._ensure_collateral_asset(account, asset)
    self.account_debt[account][asset] += amount

    # Draw liquidity from vault directly into credit account
    extcall IAegisVault(self.vault).allocate_credit(asset, amount, account)

    # Verify health factor remains >= 1.0 WAD
    hf: uint256 = staticcall IRiskEngine(self.risk_engine).compute_account_health(account)
    assert hf >= WAD, "CreditManager: borrow leaves account underwater"

    log BorrowExecuted(account=account, asset=asset, amount=amount)

@external
def repay_credit(account: address, asset: address, amount: uint256):
    assert amount > 0, "CreditManager: zero repayment"
    current_debt: uint256 = self.account_debt[account][asset]
    assert current_debt > 0, "CreditManager: no debt for asset"

    repay_amt: uint256 = amount
    if repay_amt > current_debt:
        repay_amt = current_debt

    self.account_debt[account][asset] = current_debt - repay_amt

    # Pull funds from payer to vault
    call_data: Bytes[100] = concat(
        method_id("transferFrom(address,address,uint256)"),
        convert(msg.sender, bytes32),
        convert(self.vault, bytes32),
        convert(repay_amt, bytes32)
    )
    res: Bytes[32] = raw_call(asset, call_data, max_outsize=32)
    if len(res) > 0:
        assert convert(res, bool), "CreditManager: repayment transfer failed"

    log RepayExecuted(account=account, asset=asset, amount=repay_amt)

@external
def execute_trade(
    account: address,
    adapter: address,
    asset_in: address,
    amount_in: uint256,
    asset_out: address,
    min_amount_out: uint256,
    trade_data: Bytes[1024]
) -> uint256:
    assert msg.sender == self.account_to_owner[account], "CreditManager: not account owner"
    assert self.is_whitelisted_adapter[adapter], "CreditManager: unapproved adapter"
    assert amount_in > 0, "CreditManager: zero amount in"

    # Ensure output asset is registered in account roster
    self._ensure_collateral_asset(account, asset_out)

    bal_before: uint256 = staticcall ICreditAccount(account).asset_balance(asset_out)

    # Approve adapter to spend asset_in from credit account
    extcall ICreditAccount(account).safe_approve(asset_in, adapter, amount_in)

    # Execute trade via adapter
    call_payload: Bytes[1200] = concat(
        method_id("swap(address,uint256,address,uint256,address,bytes)"),
        convert(asset_in, bytes32),
        convert(amount_in, bytes32),
        convert(asset_out, bytes32),
        convert(min_amount_out, bytes32),
        convert(account, bytes32),
        trade_data
    )
    extcall ICreditAccount(account).execute(adapter, call_payload, 0)

    bal_after: uint256 = staticcall ICreditAccount(account).asset_balance(asset_out)
    assert bal_after >= bal_before + min_amount_out, "CreditManager: slippage limit breached"
    amount_out: uint256 = bal_after - bal_before

    # Verify post-trade account health
    if len(self.account_borrowed_assets[account]) > 0:
        hf: uint256 = staticcall IRiskEngine(self.risk_engine).compute_account_health(account)
        assert hf >= WAD, "CreditManager: trade leaves account underwater"

    log TradeExecuted(
        account=account,
        adapter=adapter,
        asset_in=asset_in,
        amount_in=amount_in,
        asset_out=asset_out,
        amount_out=amount_out
    )
    return amount_out
