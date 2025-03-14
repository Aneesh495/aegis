# @version ^0.4.0
"""
@title MockPyth
@notice Test mock implementing IPyth getPriceNoOlderThan.
"""

struct PythPrice:
    price: int64
    conf: uint64
    expo: int32
    publishTime: uint256

current_price: public(HashMap[bytes32, PythPrice])

@external
def set_pyth_price(
    id: bytes32,
    price: int64,
    conf: uint64,
    expo: int32,
    publish_time: uint256
):
    self.current_price[id] = PythPrice(
        price=price,
        conf=conf,
        expo=expo,
        publishTime=publish_time
    )

@view
@external
def getPriceNoOlderThan(id: bytes32, age: uint256) -> PythPrice:
    data: PythPrice = self.current_price[id]
    assert data.publishTime > 0, "MockPyth: price not set"
    assert block.timestamp >= data.publishTime, "MockPyth: publish time in future"
    assert block.timestamp - data.publishTime <= age, "MockPyth: price too old"
    return data
