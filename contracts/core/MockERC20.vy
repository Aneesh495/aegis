# @version ^0.4.0
"""
@title MockERC20
@notice Standard ERC-20 implementation for testing and development.
@dev Supports arbitrary decimals (e.g. 6 for USDC, 8 for WBTC, 18 for WETH).
"""

event Transfer:
    sender: indexed(address)
    receiver: indexed(address)
    value: uint256

event Approval:
    owner: indexed(address)
    spender: indexed(address)
    value: uint256

name: public(String[64])
symbol: public(String[32])
decimals: public(uint8)
totalSupply: public(uint256)

balanceOf: public(HashMap[address, uint256])
allowance: public(HashMap[address, HashMap[address, uint256]])

@deploy
def __init__(name_: String[64], symbol_: String[32], decimals_: uint8):
    self.name = name_
    self.symbol = symbol_
    self.decimals = decimals_

@external
def transfer(recipient: address, amount: uint256) -> bool:
    assert recipient != empty(address), "ERC20: transfer to zero address"
    sender_balance: uint256 = self.balanceOf[msg.sender]
    assert sender_balance >= amount, "ERC20: transfer amount exceeds balance"
    self.balanceOf[msg.sender] = sender_balance - amount
    self.balanceOf[recipient] += amount
    log Transfer(sender=msg.sender, receiver=recipient, value=amount)
    return True

@external
def transferFrom(sender: address, recipient: address, amount: uint256) -> bool:
    assert recipient != empty(address), "ERC20: transfer to zero address"
    current_allowance: uint256 = self.allowance[sender][msg.sender]
    if current_allowance != max_value(uint256):
        assert current_allowance >= amount, "ERC20: insufficient allowance"
        self.allowance[sender][msg.sender] = current_allowance - amount
    sender_balance: uint256 = self.balanceOf[sender]
    assert sender_balance >= amount, "ERC20: transfer amount exceeds balance"
    self.balanceOf[sender] = sender_balance - amount
    self.balanceOf[recipient] += amount
    log Transfer(sender=sender, receiver=recipient, value=amount)
    return True

@external
def approve(spender: address, amount: uint256) -> bool:
    assert spender != empty(address), "ERC20: approve to zero address"
    self.allowance[msg.sender][spender] = amount
    log Approval(owner=msg.sender, spender=spender, value=amount)
    return True

@external
def mint(to: address, amount: uint256):
    assert to != empty(address), "ERC20: mint to zero address"
    self.totalSupply += amount
    self.balanceOf[to] += amount
    log Transfer(sender=empty(address), receiver=to, value=amount)

@external
def burn(from_account: address, amount: uint256):
    sender_balance: uint256 = self.balanceOf[from_account]
    assert sender_balance >= amount, "ERC20: burn amount exceeds balance"
    self.balanceOf[from_account] = sender_balance - amount
    self.totalSupply -= amount
    log Transfer(sender=from_account, receiver=empty(address), value=amount)
