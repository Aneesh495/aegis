# @version ^0.4.0
"""
@title BatchClearinghouse
@notice Frequent Batch Auction (FBA) clearinghouse computing uniform market clearing prices.
@dev Eliminates sub-millisecond frontrunning and sandwich attacks via discrete epoch clearing.
"""

from ethereum.ercs import IERC20

struct Order:
    trader: address
    base_asset: address
    quote_asset: address
    is_buy: bool
    limit_price_wad: uint256
    amount: uint256       # Base amount requested or offered
    filled: uint256       # Base amount filled so far
    epoch_id: uint256
    cancelled: bool

owner: public(address)
epoch_duration: public(uint256) # in seconds (e.g. 60 seconds)
epoch_start_time: public(uint256)
current_epoch_id: public(uint256)

order_count: public(uint256)
orders: public(HashMap[uint256, Order])

# Escrowed balances: asset => account => balance
escrowed_balances: public(HashMap[address, HashMap[address, uint256]])

WAD: constant(uint256) = 1_000_000_000_000_000_000

event OrderSubmitted:
    order_id: indexed(uint256)
    trader: indexed(address)
    base_asset: address
    quote_asset: address
    is_buy: bool
    limit_price_wad: uint256
    amount: uint256
    epoch_id: uint256

event OrderCancelled:
    order_id: indexed(uint256)
    trader: indexed(address)

event EpochCleared:
    epoch_id: indexed(uint256)
    base_asset: indexed(address)
    quote_asset: indexed(address)
    clearing_price_wad: uint256
    matched_base_volume: uint256
    matched_quote_volume: uint256

@deploy
def __init__(epoch_duration_seconds: uint256):
    self.owner = msg.sender
    self.epoch_duration = epoch_duration_seconds
    self.epoch_start_time = block.timestamp
    self.current_epoch_id = 1

@view
@external
def current_epoch() -> uint256:
    if block.timestamp >= self.epoch_start_time + self.epoch_duration:
        elapsed_epochs: uint256 = (block.timestamp - self.epoch_start_time) // self.epoch_duration
        return self.current_epoch_id + elapsed_epochs
    return self.current_epoch_id

@view
@external
def get_order(order_id: uint256) -> Order:
    return self.orders[order_id]

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

@external
def submit_order(
    base_asset: address,
    quote_asset: address,
    is_buy: bool,
    limit_price_wad: uint256,
    amount: uint256
) -> uint256:
    assert amount > 0, "BatchClearing: zero amount"
    assert limit_price_wad > 0, "BatchClearing: zero limit price"

    # Compute current epoch
    curr_epoch: uint256 = self.current_epoch_id
    if block.timestamp >= self.epoch_start_time + self.epoch_duration:
        elapsed: uint256 = (block.timestamp - self.epoch_start_time) // self.epoch_duration
        curr_epoch = self.current_epoch_id + elapsed

    self.order_count += 1
    new_order_id: uint256 = self.order_count

    # Pull escrowed funds from trader
    if is_buy:
        # Buyer escrows quote asset: quote_amount = (amount_base_wad * limit_price_wad) / WAD
        base_dec: uint8 = self._get_token_decimals(base_asset)
        quote_dec: uint8 = self._get_token_decimals(quote_asset)
        amount_base_wad: uint256 = self._scale_to_wad(amount, base_dec)
        quote_wad: uint256 = (amount_base_wad * limit_price_wad) // WAD
        quote_amt: uint256 = self._scale_from_wad(quote_wad, quote_dec)

        call_in: Bytes[100] = concat(
            method_id("transferFrom(address,address,uint256)"),
            convert(msg.sender, bytes32),
            convert(self, bytes32),
            convert(quote_amt, bytes32)
        )
        res: Bytes[32] = raw_call(quote_asset, call_in, max_outsize=32)
        if len(res) > 0:
            assert convert(res, bool), "BatchClearing: quote escrow transfer failed"
        self.escrowed_balances[quote_asset][msg.sender] += quote_amt
    else:
        # Seller escrows base asset
        call_in: Bytes[100] = concat(
            method_id("transferFrom(address,address,uint256)"),
            convert(msg.sender, bytes32),
            convert(self, bytes32),
            convert(amount, bytes32)
        )
        res: Bytes[32] = raw_call(base_asset, call_in, max_outsize=32)
        if len(res) > 0:
            assert convert(res, bool), "BatchClearing: base escrow transfer failed"
        self.escrowed_balances[base_asset][msg.sender] += amount

    self.orders[new_order_id] = Order(
        trader=msg.sender,
        base_asset=base_asset,
        quote_asset=quote_asset,
        is_buy=is_buy,
        limit_price_wad=limit_price_wad,
        amount=amount,
        filled=0,
        epoch_id=curr_epoch,
        cancelled=False
    )

    log OrderSubmitted(
        order_id=new_order_id,
        trader=msg.sender,
        base_asset=base_asset,
        quote_asset=quote_asset,
        is_buy=is_buy,
        limit_price_wad=limit_price_wad,
        amount=amount,
        epoch_id=curr_epoch
    )
    return new_order_id

@external
def cancel_order(order_id: uint256):
    ord: Order = self.orders[order_id]
    assert ord.trader == msg.sender, "BatchClearing: not order owner"
    assert not ord.cancelled, "BatchClearing: already cancelled"
    assert ord.filled == 0, "BatchClearing: already filled"

    ord.cancelled = True
    self.orders[order_id] = ord

    # Refund escrowed tokens
    if ord.is_buy:
        base_dec: uint8 = self._get_token_decimals(ord.base_asset)
        quote_dec: uint8 = self._get_token_decimals(ord.quote_asset)
        amount_base_wad: uint256 = self._scale_to_wad(ord.amount, base_dec)
        quote_wad: uint256 = (amount_base_wad * ord.limit_price_wad) // WAD
        quote_amt: uint256 = self._scale_from_wad(quote_wad, quote_dec)

        self.escrowed_balances[ord.quote_asset][msg.sender] -= quote_amt
        call_out: Bytes[68] = concat(
            method_id("transfer(address,uint256)"),
            convert(msg.sender, bytes32),
            convert(quote_amt, bytes32)
        )
        res_q: Bytes[32] = raw_call(ord.quote_asset, call_out, max_outsize=32)
    else:
        self.escrowed_balances[ord.base_asset][msg.sender] -= ord.amount
        call_out: Bytes[68] = concat(
            method_id("transfer(address,uint256)"),
            convert(msg.sender, bytes32),
            convert(ord.amount, bytes32)
        )
        res_b: Bytes[32] = raw_call(ord.base_asset, call_out, max_outsize=32)

    log OrderCancelled(order_id=order_id, trader=msg.sender)

@external
def clear_pair(
    buy_order_id: uint256,
    sell_order_id: uint256,
    clearing_price_wad: uint256
) -> (uint256, uint256):
    """
    @notice Matches a crossed buy and sell order at uniform clearing price.
    """
    buy_ord: Order = self.orders[buy_order_id]
    sell_ord: Order = self.orders[sell_order_id]

    assert buy_ord.is_buy and not sell_ord.is_buy, "BatchClearing: invalid pair types"
    assert not buy_ord.cancelled and not sell_ord.cancelled, "BatchClearing: cancelled order"
    assert buy_ord.base_asset == sell_ord.base_asset, "BatchClearing: mismatched base"
    assert buy_ord.quote_asset == sell_ord.quote_asset, "BatchClearing: mismatched quote"

    # Enforce uniform clearing price sanity: sell_price <= clearing_price <= buy_price
    assert clearing_price_wad >= sell_ord.limit_price_wad, "BatchClearing: clearing below sell limit"
    assert clearing_price_wad <= buy_ord.limit_price_wad, "BatchClearing: clearing above buy limit"

    # Matched base amount = min(rem_buy, rem_sell)
    rem_buy: uint256 = buy_ord.amount - buy_ord.filled
    rem_sell: uint256 = sell_ord.amount - sell_ord.filled
    matched_base: uint256 = rem_buy
    if rem_sell < matched_base:
        matched_base = rem_sell
    assert matched_base > 0, "BatchClearing: zero matched volume"

    base_dec: uint8 = self._get_token_decimals(buy_ord.base_asset)
    quote_dec: uint8 = self._get_token_decimals(buy_ord.quote_asset)

    matched_base_wad: uint256 = self._scale_to_wad(matched_base, base_dec)
    matched_quote_wad: uint256 = (matched_base_wad * clearing_price_wad) // WAD
    matched_quote: uint256 = self._scale_from_wad(matched_quote_wad, quote_dec)

    # Update filled amounts
    buy_ord.filled += matched_base
    sell_ord.filled += matched_base
    self.orders[buy_order_id] = buy_ord
    self.orders[sell_order_id] = sell_ord

    # Settle asset movements:
    # 1. Base tokens from escrow to Buyer
    self.escrowed_balances[buy_ord.base_asset][sell_ord.trader] -= matched_base
    call_base: Bytes[68] = concat(
        method_id("transfer(address,uint256)"),
        convert(buy_ord.trader, bytes32),
        convert(matched_base, bytes32)
    )
    res_b: Bytes[32] = raw_call(buy_ord.base_asset, call_base, max_outsize=32)

    # 2. Quote tokens from escrow to Seller
    self.escrowed_balances[buy_ord.quote_asset][buy_ord.trader] -= matched_quote
    call_quote: Bytes[68] = concat(
        method_id("transfer(address,uint256)"),
        convert(sell_ord.trader, bytes32),
        convert(matched_quote, bytes32)
    )
    res_q: Bytes[32] = raw_call(buy_ord.quote_asset, call_quote, max_outsize=32)

    # 3. Unspent surplus quote refund if clearing_price < buy_ord.limit_price
    if buy_ord.filled == buy_ord.amount and clearing_price_wad < buy_ord.limit_price_wad:
        refund_wad: uint256 = (matched_base_wad * (buy_ord.limit_price_wad - clearing_price_wad)) // WAD
        refund_quote: uint256 = self._scale_from_wad(refund_wad, quote_dec)
        if refund_quote > 0 and self.escrowed_balances[buy_ord.quote_asset][buy_ord.trader] >= refund_quote:
            self.escrowed_balances[buy_ord.quote_asset][buy_ord.trader] -= refund_quote
            call_refund: Bytes[68] = concat(
                method_id("transfer(address,uint256)"),
                convert(buy_ord.trader, bytes32),
                convert(refund_quote, bytes32)
            )
            res_ref: Bytes[32] = raw_call(buy_ord.quote_asset, call_refund, max_outsize=32)

    log EpochCleared(
        epoch_id=buy_ord.epoch_id,
        base_asset=buy_ord.base_asset,
        quote_asset=buy_ord.quote_asset,
        clearing_price_wad=clearing_price_wad,
        matched_base_volume=matched_base,
        matched_quote_volume=matched_quote
    )
    return (matched_base, matched_quote)
