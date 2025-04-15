# @version ^0.4.0
"""
@title LiquidationAuction
@notice Continuous two-phase Dutch auction engine for MEV-resistant liquidation settlement.
@dev Penalty starts at maximum ceiling and smoothly decays to floor over the auction duration.
"""

from ethereum.ercs import IERC20

struct Auction:
    account: address
    debt_asset: address
    collateral_asset: address
    debt_amount: uint256
    collateral_amount: uint256
    start_time: uint256
    duration: uint256
    start_penalty_wad: uint256
    min_penalty_wad: uint256
    settled: bool

interface IPriceFeedRouter:
    def get_asset_price(asset: address) -> uint256: view

interface ICreditAccount:
    def transfer_asset(token: address, recipient: address, amount: uint256): nonpayable

interface ICreditManager:
    def repay_credit(account: address, asset: address, amount: uint256): nonpayable

owner: public(address)
credit_manager: public(address)
price_router: public(address)

auction_count: public(uint256)
auctions: public(HashMap[uint256, Auction])

# Default auction parameters
DEFAULT_DURATION: constant(uint256) = 300 # 5 minutes
DEFAULT_MAX_PENALTY: constant(uint256) = 150_000_000_000_000_000 # 15%
DEFAULT_MIN_PENALTY: constant(uint256) = 30_000_000_000_000_000  # 3%
WAD: constant(uint256) = 1_000_000_000_000_000_000

event AuctionStarted:
    auction_id: indexed(uint256)
    account: indexed(address)
    debt_asset: address
    collateral_asset: address
    debt_amount: uint256
    collateral_amount: uint256
    start_time: uint256
    duration: uint256

event AuctionBid:
    auction_id: indexed(uint256)
    bidder: indexed(address)
    debt_covered: uint256
    collateral_received: uint256
    applied_penalty_wad: uint256

@deploy
def __init__(price_router_address: address):
    self.owner = msg.sender
    self.price_router = price_router_address

@external
def set_credit_manager(cm: address):
    assert msg.sender == self.owner, "LiquidationAuction: unauthorized"
    self.credit_manager = cm

@view
@external
def get_auction(auction_id: uint256) -> Auction:
    return self.auctions[auction_id]

@view
@external
def get_current_penalty(auction_id: uint256) -> uint256:
    """
    @notice Returns the current decaying liquidation penalty in WAD.
    """
    auc: Auction = self.auctions[auction_id]
    assert auc.start_time > 0, "LiquidationAuction: auction not found"
    if auc.settled:
        return 0

    if block.timestamp <= auc.start_time:
        return auc.start_penalty_wad

    elapsed: uint256 = block.timestamp - auc.start_time
    if elapsed >= auc.duration:
        return auc.min_penalty_wad

    # Linear decay: P(t) = P_max - (elapsed * (P_max - P_min)) / duration
    penalty_spread: uint256 = auc.start_penalty_wad - auc.min_penalty_wad
    decay: uint256 = (elapsed * penalty_spread) // auc.duration
    return auc.start_penalty_wad - decay

@view
@internal
def _get_token_decimals(asset: address) -> uint8:
    call_data: Bytes[4] = method_id("decimals()")
    res: Bytes[32] = raw_call(asset, call_data, max_outsize=32, is_static_call=True)
    if len(res) > 0:
        return convert(res, uint8)
    return 18

@view
@external
def get_collateral_payout(auction_id: uint256, debt_to_cover: uint256) -> uint256:
    """
    @notice Computes collateral quantity awarded to a liquidator for debt_to_cover.
    """
    auc: Auction = self.auctions[auction_id]
    assert auc.start_time > 0, "LiquidationAuction: not found"
    assert not auc.settled, "LiquidationAuction: settled"
    assert debt_to_cover <= auc.debt_amount, "LiquidationAuction: debt exceeds total"

    curr_penalty: uint256 = self._compute_penalty(auc)

    debt_price_wad: uint256 = staticcall IPriceFeedRouter(self.price_router).get_asset_price(auc.debt_asset)
    collat_price_wad: uint256 = staticcall IPriceFeedRouter(self.price_router).get_asset_price(auc.collateral_asset)

    debt_dec: uint8 = self._get_token_decimals(auc.debt_asset)
    collat_dec: uint8 = self._get_token_decimals(auc.collateral_asset)

    # Normalize debt covered to WAD
    debt_covered_wad: uint256 = self._scale_to_wad(debt_to_cover, debt_dec)

    # Debt USD value = (debt_covered_wad * debt_price_wad) / WAD
    debt_usd_wad: uint256 = (debt_covered_wad * debt_price_wad) // WAD

    # Collateral USD entitlement with penalty = debt_usd_wad * (WAD + penalty) / WAD
    collat_usd_wad: uint256 = (debt_usd_wad * (WAD + curr_penalty)) // WAD

    # Required collateral WAD = (collat_usd_wad * WAD) / collat_price_wad
    collat_wad: uint256 = (collat_usd_wad * WAD) // collat_price_wad

    collat_out: uint256 = self._scale_from_wad(collat_wad, collat_dec)
    if collat_out > auc.collateral_amount:
        collat_out = auc.collateral_amount
    return collat_out

@view
@internal
def _compute_penalty(auc: Auction) -> uint256:
    if block.timestamp <= auc.start_time:
        return auc.start_penalty_wad
    elapsed: uint256 = block.timestamp - auc.start_time
    if elapsed >= auc.duration:
        return auc.min_penalty_wad
    penalty_spread: uint256 = auc.start_penalty_wad - auc.min_penalty_wad
    decay: uint256 = (elapsed * penalty_spread) // auc.duration
    return auc.start_penalty_wad - decay

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
def start_auction(
    account: address,
    debt_asset: address,
    collateral_asset: address,
    debt_amount: uint256,
    collateral_amount: uint256
) -> uint256:
    assert msg.sender == self.credit_manager or msg.sender == self.owner, "LiquidationAuction: unauthorized"
    assert debt_amount > 0 and collateral_amount > 0, "LiquidationAuction: zero auction amounts"

    self.auction_count += 1
    new_id: uint256 = self.auction_count

    self.auctions[new_id] = Auction(
        account=account,
        debt_asset=debt_asset,
        collateral_asset=collateral_asset,
        debt_amount=debt_amount,
        collateral_amount=collateral_amount,
        start_time=block.timestamp,
        duration=DEFAULT_DURATION,
        start_penalty_wad=DEFAULT_MAX_PENALTY,
        min_penalty_wad=DEFAULT_MIN_PENALTY,
        settled=False
    )

    log AuctionStarted(
        auction_id=new_id,
        account=account,
        debt_asset=debt_asset,
        collateral_asset=collateral_asset,
        debt_amount=debt_amount,
        collateral_amount=collateral_amount,
        start_time=block.timestamp,
        duration=DEFAULT_DURATION
    )
    return new_id

@external
def bid(auction_id: uint256, debt_to_cover: uint256) -> uint256:
    """
    @notice Submits a liquidation bid covering debt in exchange for collateral.
    """
    auc: Auction = self.auctions[auction_id]
    assert auc.start_time > 0, "LiquidationAuction: auction not found"
    assert not auc.settled, "LiquidationAuction: already settled"
    assert debt_to_cover > 0, "LiquidationAuction: zero debt bid"
    assert debt_to_cover <= auc.debt_amount, "LiquidationAuction: bid exceeds debt"

    curr_penalty: uint256 = self._compute_penalty(auc)

    debt_price_wad: uint256 = staticcall IPriceFeedRouter(self.price_router).get_asset_price(auc.debt_asset)
    collat_price_wad: uint256 = staticcall IPriceFeedRouter(self.price_router).get_asset_price(auc.collateral_asset)

    debt_dec: uint8 = self._get_token_decimals(auc.debt_asset)
    collat_dec: uint8 = self._get_token_decimals(auc.collateral_asset)

    debt_covered_wad: uint256 = self._scale_to_wad(debt_to_cover, debt_dec)
    debt_usd_wad: uint256 = (debt_covered_wad * debt_price_wad) // WAD
    collat_usd_wad: uint256 = (debt_usd_wad * (WAD + curr_penalty)) // WAD
    collat_wad: uint256 = (collat_usd_wad * WAD) // collat_price_wad
    collat_out: uint256 = self._scale_from_wad(collat_wad, collat_dec)

    if collat_out > auc.collateral_amount:
        collat_out = auc.collateral_amount

    # Update auction state
    auc.debt_amount -= debt_to_cover
    auc.collateral_amount -= collat_out
    if auc.debt_amount == 0 or auc.collateral_amount == 0:
        auc.settled = True
    self.auctions[auction_id] = auc

    # Transfer collateral directly from CreditAccount to liquidator
    extcall ICreditAccount(auc.account).transfer_asset(auc.collateral_asset, msg.sender, collat_out)

    # Repay debt in CreditManager
    # Transfer debt tokens from bidder to CreditManager
    call_data: Bytes[100] = concat(
        method_id("transferFrom(address,address,uint256)"),
        convert(msg.sender, bytes32),
        convert(self.credit_manager, bytes32),
        convert(debt_to_cover, bytes32)
    )
    res: Bytes[32] = raw_call(auc.debt_asset, call_data, max_outsize=32)
    if len(res) > 0:
        assert convert(res, bool), "LiquidationAuction: transferFrom failed"

    log AuctionBid(
        auction_id=auction_id,
        bidder=msg.sender,
        debt_covered=debt_to_cover,
        collateral_received=collat_out,
        applied_penalty_wad=curr_penalty
    )
    return collat_out
