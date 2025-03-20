# @version ^0.4.0
"""
@title AegisVault
@notice Multi-asset institutional treasury, credit allocator, and EIP-3156 flash lender.
@dev Maintains segmented accounting for reserves, allocated credit lines, and protocol fees.
"""

from ethereum.ercs import IERC20

interface IERC3156FlashBorrower:
    def onFlashLoan(
        initiator: address,
        token: address,
        amount: uint256,
        fee: uint256,
        data: Bytes[1024]
    ) -> bytes32: nonpayable

event Deposit:
    asset: indexed(address)
    sender: indexed(address)
    amount: uint256

event Withdrawal:
    asset: indexed(address)
    recipient: indexed(address)
    amount: uint256

event CreditAllocated:
    asset: indexed(address)
    recipient: indexed(address)
    amount: uint256

event CreditRepaid:
    asset: indexed(address)
    payer: indexed(address)
    amount: uint256

event FlashLoanExecuted:
    receiver: indexed(address)
    token: indexed(address)
    amount: uint256
    fee: uint256

event FeesCollected:
    asset: indexed(address)
    recipient: indexed(address)
    amount: uint256

owner: public(address)
credit_manager: public(address)
debt_engine: public(address)

# Asset configuration
is_supported_asset: public(HashMap[address, bool])
asset_capacity: public(HashMap[address, uint256])

# Accounting ledgers
total_reserve: public(HashMap[address, uint256])
allocated_credit: public(HashMap[address, uint256])
protocol_fees: public(HashMap[address, uint256])

# Flash loan configuration
flash_fee_bps: public(uint256) # e.g. 5 bps = 0.05%
BPS_DENOMINATOR: constant(uint256) = 10_000
FLASH_LOAN_CALLBACK_SUCCESS: constant(bytes32) = keccak256("ERC3156FlashBorrower.onFlashLoan")

@deploy
def __init__(flash_fee_basis_points: uint256):
    self.owner = msg.sender
    self.flash_fee_bps = flash_fee_basis_points

@external
def set_credit_manager(cm: address):
    assert msg.sender == self.owner, "AegisVault: unauthorized"
    self.credit_manager = cm

@external
def set_debt_engine(de: address):
    assert msg.sender == self.owner, "AegisVault: unauthorized"
    self.debt_engine = de

@external
def set_asset_status(asset: address, supported: bool, max_capacity: uint256):
    assert msg.sender == self.owner, "AegisVault: unauthorized"
    self.is_supported_asset[asset] = supported
    self.asset_capacity[asset] = max_capacity

@view
@external
def available_liquidity(asset: address) -> uint256:
    reserve: uint256 = self.total_reserve[asset]
    allocated: uint256 = self.allocated_credit[asset]
    fees: uint256 = self.protocol_fees[asset]
    if reserve > (allocated + fees):
        return reserve - allocated - fees
    return 0

@external
@nonreentrant
def deposit_collateral(asset: address, amount: uint256, on_behalf_of: address) -> uint256:
    assert self.is_supported_asset[asset], "AegisVault: unsupported asset"
    assert amount > 0, "AegisVault: deposit zero amount"

    capacity: uint256 = self.asset_capacity[asset]
    new_reserve: uint256 = self.total_reserve[asset] + amount
    assert capacity == 0 or new_reserve <= capacity, "AegisVault: capacity exceeded"

    self.total_reserve[asset] = new_reserve

    # Transfer tokens from caller to vault
    call_data: Bytes[100] = concat(
        method_id("transferFrom(address,address,uint256)"),
        convert(msg.sender, bytes32),
        convert(self, bytes32),
        convert(amount, bytes32)
    )
    res: Bytes[32] = raw_call(asset, call_data, max_outsize=32)
    if len(res) > 0:
        assert convert(res, bool), "AegisVault: transferFrom failed"

    log Deposit(asset=asset, sender=on_behalf_of, amount=amount)
    return amount

@external
@nonreentrant
def withdraw_collateral(asset: address, amount: uint256, recipient: address) -> uint256:
    assert msg.sender == self.credit_manager or msg.sender == self.debt_engine or msg.sender == self.owner, "AegisVault: unauthorized withdrawal"
    assert amount > 0, "AegisVault: withdraw zero amount"
    assert self.total_reserve[asset] >= amount, "AegisVault: insufficient reserve"

    self.total_reserve[asset] -= amount

    call_data: Bytes[68] = concat(
        method_id("transfer(address,uint256)"),
        convert(recipient, bytes32),
        convert(amount, bytes32)
    )
    res: Bytes[32] = raw_call(asset, call_data, max_outsize=32)
    if len(res) > 0:
        assert convert(res, bool), "AegisVault: transfer failed"

    log Withdrawal(asset=asset, recipient=recipient, amount=amount)
    return amount

@external
@nonreentrant
def allocate_credit(asset: address, amount: uint256, recipient: address):
    assert msg.sender == self.credit_manager, "AegisVault: only credit manager"
    assert self.is_supported_asset[asset], "AegisVault: unsupported asset"

    avail: uint256 = self.total_reserve[asset] - self.allocated_credit[asset] - self.protocol_fees[asset]
    assert avail >= amount, "AegisVault: insufficient free liquidity"

    self.allocated_credit[asset] += amount

    call_data: Bytes[68] = concat(
        method_id("transfer(address,uint256)"),
        convert(recipient, bytes32),
        convert(amount, bytes32)
    )
    res: Bytes[32] = raw_call(asset, call_data, max_outsize=32)
    if len(res) > 0:
        assert convert(res, bool), "AegisVault: transfer failed"

    log CreditAllocated(asset=asset, recipient=recipient, amount=amount)

@external
@nonreentrant
def repay_credit(asset: address, amount: uint256, from_account: address):
    assert msg.sender == self.credit_manager, "AegisVault: only credit manager"
    assert self.allocated_credit[asset] >= amount, "AegisVault: repayment exceeds allocated"

    self.allocated_credit[asset] -= amount

    call_data: Bytes[100] = concat(
        method_id("transferFrom(address,address,uint256)"),
        convert(from_account, bytes32),
        convert(self, bytes32),
        convert(amount, bytes32)
    )
    res: Bytes[32] = raw_call(asset, call_data, max_outsize=32)
    if len(res) > 0:
        assert convert(res, bool), "AegisVault: transferFrom failed"

    log CreditRepaid(asset=asset, payer=from_account, amount=amount)

# --- EIP-3156 Flash Lending ---

@view
@external
def maxFlashLoan(token: address) -> uint256:
    if not self.is_supported_asset[token]:
        return 0
    reserve: uint256 = self.total_reserve[token]
    allocated: uint256 = self.allocated_credit[token]
    fees: uint256 = self.protocol_fees[token]
    if reserve > (allocated + fees):
        return reserve - allocated - fees
    return 0

@view
@external
def flashFee(token: address, amount: uint256) -> uint256:
    assert self.is_supported_asset[token], "AegisVault: unsupported asset"
    return (amount * self.flash_fee_bps) // BPS_DENOMINATOR

@external
@nonreentrant
def flashLoan(
    receiver: address,
    token: address,
    amount: uint256,
    data: Bytes[1024]
) -> bool:
    assert self.is_supported_asset[token], "AegisVault: unsupported asset"
    avail: uint256 = self.total_reserve[token] - self.allocated_credit[token] - self.protocol_fees[token]
    assert avail >= amount, "AegisVault: amount exceeds free liquidity"

    fee: uint256 = (amount * self.flash_fee_bps) // BPS_DENOMINATOR
    repayment_target: uint256 = amount + fee

    # Transfer loan amount to receiver
    transfer_data: Bytes[68] = concat(
        method_id("transfer(address,uint256)"),
        convert(receiver, bytes32),
        convert(amount, bytes32)
    )
    res_transfer: Bytes[32] = raw_call(token, transfer_data, max_outsize=32)
    if len(res_transfer) > 0:
        assert convert(res_transfer, bool), "AegisVault: transfer failed"

    # Invoke receiver callback
    callback_res: bytes32 = extcall IERC3156FlashBorrower(receiver).onFlashLoan(
        msg.sender,
        token,
        amount,
        fee,
        data
    )
    assert callback_res == FLASH_LOAN_CALLBACK_SUCCESS, "AegisVault: flash loan callback rejected"

    # Recover amount + fee from receiver
    recover_data: Bytes[100] = concat(
        method_id("transferFrom(address,address,uint256)"),
        convert(receiver, bytes32),
        convert(self, bytes32),
        convert(repayment_target, bytes32)
    )
    res_recover: Bytes[32] = raw_call(token, recover_data, max_outsize=32)
    if len(res_recover) > 0:
        assert convert(res_recover, bool), "AegisVault: recovery failed"

    self.protocol_fees[token] += fee
    log FlashLoanExecuted(receiver=receiver, token=token, amount=amount, fee=fee)
    return True

@external
def sweep_protocol_fees(asset: address, recipient: address) -> uint256:
    assert msg.sender == self.owner, "AegisVault: unauthorized"
    fee_amount: uint256 = self.protocol_fees[asset]
    assert fee_amount > 0, "AegisVault: no fees to sweep"

    self.protocol_fees[asset] = 0
    self.total_reserve[asset] -= fee_amount

    call_data: Bytes[68] = concat(
        method_id("transfer(address,uint256)"),
        convert(recipient, bytes32),
        convert(fee_amount, bytes32)
    )
    res: Bytes[32] = raw_call(asset, call_data, max_outsize=32)
    if len(res) > 0:
        assert convert(res, bool), "AegisVault: transfer failed"

    log FeesCollected(asset=asset, recipient=recipient, amount=fee_amount)
    return fee_amount
