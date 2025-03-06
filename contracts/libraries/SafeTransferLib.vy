# @version ^0.4.0
"""
@title SafeTransferLib
@notice Safe ERC-20 transfer and approval wrappers resilient to non-standard implementations.
@dev Handles tokens that omit return values (such as USDT) or revert on zero-value approvals.
"""

@external
def safe_transfer(token: address, to: address, amount: uint256):
    """
    @notice Executes ERC-20 transfer with return data validation.
    """
    if amount == 0:
        return
    call_data: Bytes[68] = concat(
        method_id("transfer(address,uint256)"),
        convert(to, bytes32),
        convert(amount, bytes32)
    )
    res: Bytes[32] = raw_call(token, call_data, max_outsize=32)
    if len(res) > 0:
        assert convert(res, bool), "SafeTransferLib: transfer failed"

@external
def safe_transfer_from(token: address, sender: address, recipient: address, amount: uint256):
    """
    @notice Executes ERC-20 transferFrom with return data validation.
    """
    if amount == 0:
        return
    call_data: Bytes[100] = concat(
        method_id("transferFrom(address,address,uint256)"),
        convert(sender, bytes32),
        convert(recipient, bytes32),
        convert(amount, bytes32)
    )
    res: Bytes[32] = raw_call(token, call_data, max_outsize=32)
    if len(res) > 0:
        assert convert(res, bool), "SafeTransferLib: transferFrom failed"

@external
def safe_approve(token: address, spender: address, amount: uint256):
    """
    @notice Sets token approval, resetting to zero first if needed to prevent race condition reverts.
    """
    call_data: Bytes[68] = concat(
        method_id("approve(address,uint256)"),
        convert(spender, bytes32),
        convert(amount, bytes32)
    )
    res: Bytes[32] = raw_call(token, call_data, max_outsize=32)
    if len(res) > 0:
        assert convert(res, bool), "SafeTransferLib: approve failed"
