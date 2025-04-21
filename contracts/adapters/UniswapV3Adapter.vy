# @version ^0.4.0
"""
@title UniswapV3Adapter
@notice Execution adapter interfacing with Uniswap V3 SwapRouter.
@dev Handles single-tick concentrated liquidity swaps with strict amountOutMinimum assertion.
"""

from ethereum.ercs import IERC20

struct ExactInputSingleParams:
    tokenIn: address
    tokenOut: address
    fee: uint24
    recipient: address
    deadline: uint256
    amountIn: uint256
    amountOutMinimum: uint256
    sqrtPriceLimitX96: uint160

interface ISwapRouter:
    def exactInputSingle(params: ExactInputSingleParams) -> uint256: nonpayable

owner: public(address)
swap_router: public(address)
default_fee_tier: public(uint24) # e.g. 500 = 0.05%, 3000 = 0.30%

event RouterUpdated:
    router: address
    fee_tier: uint24

@deploy
def __init__(router: address, fee: uint24):
    self.owner = msg.sender
    self.swap_router = router
    self.default_fee_tier = fee

@external
def swap(
    asset_in: address,
    amount_in: uint256,
    asset_out: address,
    min_amount_out: uint256,
    recipient: address,
    trade_data: Bytes[1024]
) -> uint256:
    assert amount_in > 0, "UniswapV3Adapter: zero amount in"
    assert recipient != empty(address), "UniswapV3Adapter: zero recipient"

    # Pull asset_in from caller to this adapter
    call_in: Bytes[100] = concat(
        method_id("transferFrom(address,address,uint256)"),
        convert(msg.sender, bytes32),
        convert(self, bytes32),
        convert(amount_in, bytes32)
    )
    res_in: Bytes[32] = raw_call(asset_in, call_in, max_outsize=32)
    if len(res_in) > 0:
        assert convert(res_in, bool), "UniswapV3Adapter: transferFrom failed"

    # Approve swap router
    call_app: Bytes[68] = concat(
        method_id("approve(address,uint256)"),
        convert(self.swap_router, bytes32),
        convert(amount_in, bytes32)
    )
    res_app: Bytes[32] = raw_call(asset_in, call_app, max_outsize=32)
    if len(res_app) > 0:
        assert convert(res_app, bool), "UniswapV3Adapter: approve failed"

    # Execute exactInputSingle on Uniswap V3 SwapRouter
    params: ExactInputSingleParams = ExactInputSingleParams(
        tokenIn=asset_in,
        tokenOut=asset_out,
        fee=self.default_fee_tier,
        recipient=recipient,
        deadline=block.timestamp + 300,
        amountIn=amount_in,
        amountOutMinimum=min_amount_out,
        sqrtPriceLimitX96=0
    )

    amount_out: uint256 = extcall ISwapRouter(self.swap_router).exactInputSingle(params)
    assert amount_out >= min_amount_out, "UniswapV3Adapter: return below minimum"
    return amount_out
