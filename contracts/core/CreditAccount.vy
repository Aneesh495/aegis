# @version ^0.4.0
"""
@title CreditAccount
@notice Isolated smart contract proxy holding leveraged positions and margin.
@dev All state-changing operations are restricted to the authorized CreditManager.
"""

interface IERC20:
    def balanceOf(account: address) -> uint256: view

credit_manager: public(address)
owner: public(address)

event Executed:
    target: indexed(address)
    value: uint256
    call_data: Bytes[2048]

event Approved:
    token: indexed(address)
    spender: indexed(address)
    amount: uint256

event AssetTransferred:
    token: indexed(address)
    recipient: indexed(address)
    amount: uint256

@deploy
def __init__(manager: address, account_owner: address):
    self.credit_manager = manager
    self.owner = account_owner

@view
@external
def asset_balance(asset: address) -> uint256:
    return staticcall IERC20(asset).balanceOf(self)

@external
def execute(target: address, call_data: Bytes[2048], value: uint256) -> Bytes[2048]:
    assert msg.sender == self.credit_manager, "CreditAccount: only credit manager"
    assert target != empty(address), "CreditAccount: zero target"

    res: Bytes[2048] = raw_call(target, call_data, max_outsize=2048, value=value)
    log Executed(target=target, value=value, call_data=call_data)
    return res

@external
def safe_approve(token: address, spender: address, amount: uint256):
    assert msg.sender == self.credit_manager, "CreditAccount: only credit manager"

    call_data: Bytes[68] = concat(
        method_id("approve(address,uint256)"),
        convert(spender, bytes32),
        convert(amount, bytes32)
    )
    res: Bytes[32] = raw_call(token, call_data, max_outsize=32)
    if len(res) > 0:
        assert convert(res, bool), "CreditAccount: approve failed"

    log Approved(token=token, spender=spender, amount=amount)

@external
def transfer_asset(token: address, recipient: address, amount: uint256):
    assert msg.sender == self.credit_manager, "CreditAccount: only credit manager"
    assert recipient != empty(address), "CreditAccount: zero recipient"

    call_data: Bytes[68] = concat(
        method_id("transfer(address,uint256)"),
        convert(recipient, bytes32),
        convert(amount, bytes32)
    )
    res: Bytes[32] = raw_call(token, call_data, max_outsize=32)
    if len(res) > 0:
        assert convert(res, bool), "CreditAccount: transfer failed"

    log AssetTransferred(token=token, recipient=recipient, amount=amount)
