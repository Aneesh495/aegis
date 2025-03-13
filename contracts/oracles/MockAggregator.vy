# @version ^0.4.0
"""
@title MockAggregator
@notice Test mock implementing Chainlink AggregatorV3Interface.
"""

decimals: public(uint8)
latest_answer: public(int256)
latest_timestamp: public(uint256)
round_count: public(uint80)

@deploy
def __init__(dec: uint8, initial_answer: int256):
    self.decimals = dec
    self.latest_answer = initial_answer
    self.latest_timestamp = block.timestamp
    self.round_count = 1

@external
def set_answer(new_answer: int256):
    self.latest_answer = new_answer
    self.latest_timestamp = block.timestamp
    self.round_count += 1

@external
def set_timestamp(new_timestamp: uint256):
    self.latest_timestamp = new_timestamp

@view
@external
def latestRoundData() -> (uint80, int256, uint256, uint256, uint80):
    return (
        self.round_count,
        self.latest_answer,
        self.latest_timestamp,
        self.latest_timestamp,
        self.round_count
    )
