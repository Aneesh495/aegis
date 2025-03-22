# @version ^0.4.0
"""
@title MockFlashBorrower
@notice Test receiver contract for EIP-3156 flash loans.
"""

from ethereum.ercs import IERC20

FLASH_LOAN_CALLBACK_SUCCESS: constant(bytes32) = keccak256("ERC3156FlashBorrower.onFlashLoan")

owner: public(address)
last_token: public(address)
last_amount: public(uint256)
last_fee: public(uint256)
should_fail: public(bool)

@deploy
def __init__():
    self.owner = msg.sender

@external
def set_should_fail(fail: bool):
    self.should_fail = fail

@external
def onFlashLoan(
    initiator: address,
    token: address,
    amount: uint256,
    fee: uint256,
    data: Bytes[1024]
) -> bytes32:
    if self.should_fail:
        return empty(bytes32)

    self.last_token = token
    self.last_amount = amount
    self.last_fee = fee

    # Approve lender to take repayment (amount + fee)
    repayment: uint256 = amount + fee
    call_data: Bytes[68] = concat(
        method_id("approve(address,uint256)"),
        convert(msg.sender, bytes32),
        convert(repayment, bytes32)
    )
    res: Bytes[32] = raw_call(token, call_data, max_outsize=32)

    return FLASH_LOAN_CALLBACK_SUCCESS
