# @version ^0.4.0
"""
@title TWAPOracle
@notice Cumulative on-chain Time-Weighted Average Price (TWAP) accumulator.
@dev Maintains a rolling buffer of observations to provide manipulation-resistant pricing.
"""

struct Observation:
    timestamp: uint256
    price_cumulative: uint256

owner: public(address)
buffer_size: public(uint256)
observation_index: public(HashMap[address, uint256])
observations: public(HashMap[address, HashMap[uint256, Observation]])
last_updated_price: public(HashMap[address, uint256])

event ObservationRecorded:
    asset: indexed(address)
    price_wad: uint256
    price_cumulative: uint256
    timestamp: uint256

@deploy
def __init__(max_buffer: uint256):
    self.owner = msg.sender
    self.buffer_size = max_buffer

@external
def record_observation(asset: address, current_price_wad: uint256):
    """
    @notice Appends a new price observation into the rolling ring buffer.
    """
    idx: uint256 = self.observation_index[asset]
    prev_obs: Observation = self.observations[asset][idx]

    new_cumulative: uint256 = 0
    if prev_obs.timestamp == 0:
        new_cumulative = current_price_wad
    else:
        dt: uint256 = block.timestamp - prev_obs.timestamp
        new_cumulative = prev_obs.price_cumulative + (current_price_wad * dt)

    next_idx: uint256 = (idx + 1) % self.buffer_size
    self.observation_index[asset] = next_idx
    self.observations[asset][next_idx] = Observation(
        timestamp=block.timestamp,
        price_cumulative=new_cumulative
    )
    self.last_updated_price[asset] = current_price_wad
    log ObservationRecorded(
        asset=asset,
        price_wad=current_price_wad,
        price_cumulative=new_cumulative,
        timestamp=block.timestamp
    )

@view
@external
def get_twap(asset: address, window_seconds: uint256) -> uint256:
    """
    @notice Calculates TWAP over window_seconds.
    """
    latest_idx: uint256 = self.observation_index[asset]
    latest: Observation = self.observations[asset][latest_idx]
    assert latest.timestamp > 0, "TWAPOracle: no observations"
    assert block.timestamp >= latest.timestamp, "TWAPOracle: timestamp in future"

    # Search backwards for the observation closest to block.timestamp - window_seconds
    target_time: uint256 = 0
    if block.timestamp > window_seconds:
        target_time = block.timestamp - window_seconds

    oldest_idx: uint256 = latest_idx
    for i: uint256 in range(64):
        prev: uint256 = (latest_idx + self.buffer_size - i) % self.buffer_size
        obs: Observation = self.observations[asset][prev]
        if obs.timestamp == 0 or obs.timestamp <= target_time:
            oldest_idx = prev
            break

    oldest: Observation = self.observations[asset][oldest_idx]
    if oldest.timestamp == latest.timestamp or oldest.timestamp == 0:
        return self.last_updated_price[asset]

    dt: uint256 = latest.timestamp - oldest.timestamp
    d_cumulative: uint256 = latest.price_cumulative - oldest.price_cumulative
    return d_cumulative // dt
