# @version ^0.4.0
"""
@title MockDEXAdapter
@notice Deterministic DEX swap adapter for integration testing and simulated executions.
@dev Allows credit accounts to execute swaps with configurable exchange rates and slippage.
"""

from ethereum.ercs import IERC20

owner: public(address)
exchange_rate_wad: public(HashMap[address, HashMap[address, uint256]]) # asset_in => asset_out => rate

WAD: constant(uint256) = 1_000_000_000_000_000_000

event Swapped:
    sender: indexed(address)
    asset_in: indexed(address)
    amount_in: uint256
    asset_out: indexed(address)
    amount_out: uint256
    recipient: address

@deploy
def __init__():
    self.owner = msg.sender

@external
def set_rate(asset_in: address, asset_out: address, rate_wad: uint256):
    assert msg.sender == self.owner, "MockDEX: unauthorized"
    self.exchange_rate_wad[asset_in][asset_out] = rate_wad

@view
@internal
def _get_token_decimals(asset: address) -> uint8:
    call_data: Bytes[4] = method_id("decimals()")
    res: Bytes[32] = raw_call(asset, call_data, max_outsize=32, is_static_call=True)
    if len(res) > 0:
        return convert(res, uint8)
    return 18

@view
@internal
def _scale_to_wad(amount: uint256, dec: uint8) -> uint256:
    if dec == 18:
        return amount
    elif dec < 18:
        mult: uint256 = 10 ** convert(18 - dec, uint256)
        return amount * mult
    else:
        div_val: uint256 = 10 ** convert(dec - 18, uint256)
        return amount // div_val

@view
@internal
def _scale_from_wad(wad_amount: uint256, dec: uint8) -> uint256:
    if dec == 18:
        return wad_amount
    elif dec < 18:
        div_val: uint256 = 10 ** convert(18 - dec, uint256)
        return wad_amount // div_val
    else:
        mult: uint256 = 10 ** convert(dec - 18, uint256)
        return wad_amount * mult

@view
@external
def preview_swap(
    asset_in: address,
    amount_in: uint256,
    asset_out: address,
    trade_data: Bytes[1024]
) -> uint256:
    rate_wad: uint256 = self.exchange_rate_wad[asset_in][asset_out]
    assert rate_wad > 0, "MockDEX: rate not configured"

    in_dec: uint8 = self._get_token_decimals(asset_in)
    out_dec: uint8 = self._get_token_decimals(asset_out)

    in_wad: uint256 = self._scale_to_wad(amount_in, in_dec)
    out_wad: uint256 = (in_wad * rate_wad) // WAD
    return self._scale_from_wad(out_wad, out_dec)

@external
def swap(
    asset_in: address,
    amount_in: uint256,
    asset_out: address,
    min_amount_out: uint256,
    recipient: address,
    trade_data: Bytes[1024]
) -> uint256:
    assert amount_in > 0, "MockDEX: zero amount in"
    assert recipient != empty(address), "MockDEX: zero recipient"

    rate_wad: uint256 = self.exchange_rate_wad[asset_in][asset_out]
    assert rate_wad > 0, "MockDEX: rate not configured"

    in_dec: uint8 = self._get_token_decimals(asset_in)
    out_dec: uint8 = self._get_token_decimals(asset_out)

    in_wad: uint256 = self._scale_to_wad(amount_in, in_dec)
    out_wad: uint256 = (in_wad * rate_wad) // WAD
    amount_out: uint256 = self._scale_from_wad(out_wad, out_dec)

    assert amount_out >= min_amount_out, "MockDEX: slippage limit breached"

    # Transfer asset_in from caller to this adapter
    call_in: Bytes[100] = concat(
        method_id("transferFrom(address,address,uint256)"),
        convert(msg.sender, bytes32),
        convert(self, bytes32),
        convert(amount_in, bytes32)
    )
    res_in: Bytes[32] = raw_call(asset_in, call_in, max_outsize=32)
    if len(res_in) > 0:
        assert convert(res_in, bool), "MockDEX: transferFrom failed"

    # Transfer asset_out from this adapter to recipient
    call_out: Bytes[68] = concat(
        method_id("transfer(address,uint256)"),
        convert(recipient, bytes32),
        convert(amount_out, bytes32)
    )
    res_out: Bytes[32] = raw_call(asset_out, call_out, max_outsize=32)
    if len(res_out) > 0:
        assert convert(res_out, bool), "MockDEX: transfer failed"

    log Swapped(
        sender=msg.sender,
        asset_in=asset_in,
        amount_in=amount_in,
        asset_out=asset_out,
        amount_out=amount_out,
        recipient=recipient
    )
    return amount_out
