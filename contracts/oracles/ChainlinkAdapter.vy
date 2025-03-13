# @version ^0.4.0
"""
@title ChainlinkAdapter
@notice Standard Chainlink price feed adapter with heartbeat and sanity bounds.
@dev Converts any Chainlink feed decimals (typically 8) into standard 18-decimal WAD.
"""

interface AggregatorV3Interface:
    def decimals() -> uint8: view
    def latestRoundData() -> (uint80, int256, uint256, uint256, uint80): view

owner: public(address)
feed_decimals: public(uint8)
feed_address: public(address)
heartbeat: public(uint256)
min_answer: public(int256)
max_answer: public(int256)

WAD: constant(uint256) = 1_000_000_000_000_000_000

event RiskParamsUpdated:
    heartbeat: uint256
    min_answer: int256
    max_answer: int256

@deploy
def __init__(
    feed: address,
    heartbeat_seconds: uint256,
    min_ans: int256,
    max_ans: int256
):
    self.owner = msg.sender
    self.feed_address = feed
    self.feed_decimals = staticcall AggregatorV3Interface(feed).decimals()
    self.heartbeat = heartbeat_seconds
    self.min_answer = min_ans
    self.max_answer = max_ans

@view
@external
def get_price(asset: address) -> (uint256, uint256):
    """
    @notice Fetches the latest price normalized to 18-decimal WAD.
    @return price_wad Normalized price in 18 decimals.
    @return timestamp Timestamp when the oracle round was reported.
    """
    round_id: uint80 = 0
    answer: int256 = 0
    started_at: uint256 = 0
    updated_at: uint256 = 0
    answered_in_round: uint80 = 0

    round_id, answer, started_at, updated_at, answered_in_round = staticcall AggregatorV3Interface(self.feed_address).latestRoundData()

    assert answer > 0, "ChainlinkAdapter: non-positive price"
    assert answer >= self.min_answer, "ChainlinkAdapter: answer below min circuit breaker"
    assert answer <= self.max_answer, "ChainlinkAdapter: answer above max circuit breaker"
    assert updated_at > 0, "ChainlinkAdapter: round incomplete"
    assert block.timestamp >= updated_at, "ChainlinkAdapter: timestamp in future"
    assert block.timestamp - updated_at <= self.heartbeat, "ChainlinkAdapter: stale feed"

    ans_u256: uint256 = convert(answer, uint256)
    price_wad: uint256 = 0

    if self.feed_decimals == 18:
        price_wad = ans_u256
    elif self.feed_decimals < 18:
        scale_factor: uint256 = 10 ** convert(18 - self.feed_decimals, uint256)
        price_wad = ans_u256 * scale_factor
    else:
        scale_factor: uint256 = 10 ** convert(self.feed_decimals - 18, uint256)
        price_wad = ans_u256 // scale_factor

    return (price_wad, updated_at)

@view
@external
def is_valid(asset: address) -> bool:
    round_id: uint80 = 0
    answer: int256 = 0
    started_at: uint256 = 0
    updated_at: uint256 = 0
    answered_in_round: uint80 = 0

    round_id, answer, started_at, updated_at, answered_in_round = staticcall AggregatorV3Interface(self.feed_address).latestRoundData()
    if answer <= 0 or answer < self.min_answer or answer > self.max_answer:
        return False
    if updated_at == 0 or block.timestamp < updated_at or block.timestamp - updated_at > self.heartbeat:
        return False
    return True

@external
def update_parameters(heartbeat_seconds: uint256, min_ans: int256, max_ans: int256):
    assert msg.sender == self.owner, "ChainlinkAdapter: unauthorized"
    self.heartbeat = heartbeat_seconds
    self.min_answer = min_ans
    self.max_answer = max_ans
    log RiskParamsUpdated(heartbeat=heartbeat_seconds, min_answer=min_ans, max_answer=max_ans)
