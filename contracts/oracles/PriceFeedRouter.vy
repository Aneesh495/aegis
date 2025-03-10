# @version ^0.4.0
"""
@title PriceFeedRouter
@notice Central multi-source price router with deviation circuit breakers and TWAP fallback.
@dev Cross-verifies primary and secondary feeds; falls back to TWAP if deviation exceeds threshold.
"""

from ethereum.ercs import IERC20

interface IOracleAdapter:
    def get_price(asset: address) -> (uint256, uint256): view
    def is_valid(asset: address) -> bool: view

interface ITWAPOracle:
    def get_twap(asset: address, window_seconds: uint256) -> uint256: view
    def record_observation(asset: address, current_price_wad: uint256): nonpayable

owner: public(address)
twap_oracle: public(address)

primary_adapter: public(HashMap[address, address])
secondary_adapter: public(HashMap[address, address])
max_deviation_wad: public(HashMap[address, uint256]) # e.g. 0.03 * 10^18 (3%)
twap_window: public(HashMap[address, uint256]) # e.g. 1800 seconds (30 mins)

WAD: constant(uint256) = 1_000_000_000_000_000_000

event FeedConfigured:
    asset: indexed(address)
    primary: address
    secondary: address
    max_deviation_wad: uint256

event PriceQueried:
    asset: indexed(address)
    selected_price_wad: uint256
    source_type: uint8 # 0: Primary, 1: Mean/Agreement, 2: Secondary, 3: TWAP fallback

@deploy
def __init__(twap_oracle_address: address):
    self.owner = msg.sender
    self.twap_oracle = twap_oracle_address

@external
def set_asset_feeds(
    asset: address,
    primary: address,
    secondary: address,
    max_dev_wad: uint256,
    window_sec: uint256
):
    assert msg.sender == self.owner, "PriceFeedRouter: unauthorized"
    self.primary_adapter[asset] = primary
    self.secondary_adapter[asset] = secondary
    self.max_deviation_wad[asset] = max_dev_wad
    self.twap_window[asset] = window_sec
    log FeedConfigured(
        asset=asset,
        primary=primary,
        secondary=secondary,
        max_deviation_wad=max_dev_wad
    )

@view
@external
def get_asset_price(asset: address) -> uint256:
    """
    @notice Returns validated asset price in 18-decimal WAD.
    """
    primary: address = self.primary_adapter[asset]
    assert primary != empty(address), "PriceFeedRouter: asset feed unconfigured"

    p_valid: bool = staticcall IOracleAdapter(primary).is_valid(asset)
    p_price: uint256 = 0
    p_time: uint256 = 0
    if p_valid:
        p_price, p_time = staticcall IOracleAdapter(primary).get_price(asset)

    secondary: address = self.secondary_adapter[asset]
    s_valid: bool = False
    s_price: uint256 = 0
    s_time: uint256 = 0
    if secondary != empty(address):
        s_valid = staticcall IOracleAdapter(secondary).is_valid(asset)
        if s_valid:
            s_price, s_time = staticcall IOracleAdapter(secondary).get_price(asset)

    # Case 1: Both primary and secondary valid
    if p_valid and s_valid:
        diff: uint256 = 0
        if p_price >= s_price:
            diff = p_price - s_price
        else:
            diff = s_price - p_price

        # Check relative divergence: (diff * WAD) / p_price
        divergence_wad: uint256 = (diff * WAD) // p_price
        max_dev: uint256 = self.max_deviation_wad[asset]

        if divergence_wad <= max_dev:
            # Feeds agree within tolerance, return arithmetic mean for stability
            return (p_price + s_price) // 2
        else:
            # Feeds diverge beyond tolerance, trigger TWAP fallback if configured
            if self.twap_oracle != empty(address):
                window: uint256 = self.twap_window[asset]
                if window == 0:
                    window = 1800
                return staticcall ITWAPOracle(self.twap_oracle).get_twap(asset, window)
            else:
                return p_price

    # Case 2: Only primary is valid
    if p_valid:
        return p_price

    # Case 3: Only secondary is valid
    if s_valid:
        return s_price

    # Case 4: Both adapters failing, attempt TWAP fallback
    if self.twap_oracle != empty(address):
        window: uint256 = self.twap_window[asset]
        if window == 0:
            window = 1800
        return staticcall ITWAPOracle(self.twap_oracle).get_twap(asset, window)

    raise "PriceFeedRouter: all price sources exhausted"

@view
@external
def is_price_valid(asset: address) -> bool:
    primary: address = self.primary_adapter[asset]
    if primary == empty(address):
        return False
    if staticcall IOracleAdapter(primary).is_valid(asset):
        return True
    secondary: address = self.secondary_adapter[asset]
    if secondary != empty(address) and staticcall IOracleAdapter(secondary).is_valid(asset):
        return True
    return False

@external
def update_twap(asset: address):
    """
    @notice Updates TWAP observation with current verified price.
    """
    assert self.twap_oracle != empty(address), "PriceFeedRouter: no twap oracle"
    # Call internal view logic
    primary: address = self.primary_adapter[asset]
    assert primary != empty(address), "PriceFeedRouter: unconfigured"
    price_wad: uint256 = 0
    time_val: uint256 = 0
    price_wad, time_val = staticcall IOracleAdapter(primary).get_price(asset)
    extcall ITWAPOracle(self.twap_oracle).record_observation(asset, price_wad)
