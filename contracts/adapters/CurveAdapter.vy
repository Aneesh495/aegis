# @version ^0.4.0
"""
@title CurveAdapter
@notice Execution adapter interfacing with Curve StableSwap pools.
@dev Ideal for low-slippage collateral rebalancing between pegged assets.
"""

from ethereum.ercs import IERC20

interface ICurvePool:
    def exchange(i: int128, j: int128, dx: uint256, min_dy: uint256) -> uint256: nonpayable

owner: public(address)
pool: public(address)
token_to_index: public(HashMap[address, int128])

@deploy
def __init__(curve_pool: address):
    self.owner = msg.sender
    self.pool = curve_pool

@external
def set_token_index(token: address, index: int128):
    assert msg.sender == self.owner, "CurveAdapter: unauthorized"
    self.token_to_index[token] = index

@external
def swap(
    asset_in: address,
    amount_in: uint256,
    asset_out: address,
    min_amount_out: uint256,
    recipient: address,
    trade_data: Bytes[1024]
) -> uint256:
    assert amount_in > 0, "CurveAdapter: zero amount in"
    assert recipient != empty(address), "CurveAdapter: zero recipient"

    i: int128 = self.token_to_index[asset_in]
    j: int128 = self.token_to_index[asset_out]

    # Pull asset_in from caller to this adapter
    call_in: Bytes[100] = concat(
        method_id("transferFrom(address,address,uint256)"),
        convert(msg.sender, bytes32),
        convert(self, bytes32),
        convert(amount_in, bytes32)
    )
    res_in: Bytes[32] = raw_call(asset_in, call_in, max_outsize=32)
    if len(res_in) > 0:
        assert convert(res_in, bool), "CurveAdapter: transferFrom failed"

    # Approve Curve pool
    call_app: Bytes[68] = concat(
        method_id("approve(address,uint256)"),
        convert(self.pool, bytes32),
        convert(amount_in, bytes32)
    )
    res_app: Bytes[32] = raw_call(asset_in, call_app, max_outsize=32)
    if len(res_app) > 0:
        assert convert(res_app, bool), "CurveAdapter: approve failed"

    # Execute exchange on Curve
    dy: uint256 = extcall ICurvePool(self.pool).exchange(i, j, amount_in, min_amount_out)
    assert dy >= min_amount_out, "CurveAdapter: dy below min"

    # Transfer output token to recipient
    call_out: Bytes[68] = concat(
        method_id("transfer(address,uint256)"),
        convert(recipient, bytes32),
        convert(dy, bytes32)
    )
    res_out: Bytes[32] = raw_call(asset_out, call_out, max_outsize=32)
    if len(res_out) > 0:
        assert convert(res_out, bool), "CurveAdapter: transfer failed"

    return dy
