# @version ^0.4.0
"""
@title PythAdapter
@notice Pyth network oracle adapter with confidence interval thresholding.
@dev Rejects price updates if confidence interval is too wide relative to spot price.
"""

struct PythPrice:
    price: int64
    conf: uint64
    expo: int32
    publishTime: uint256

interface IPyth:
    def getPriceNoOlderThan(id: bytes32, age: uint256) -> PythPrice: view

owner: public(address)
pyth_contract: public(address)
price_feed_id: public(bytes32)
max_age: public(uint256)
max_conf_ratio_wad: public(uint256) # e.g. 0.02 * 10^18 for 2% max confidence band

WAD: constant(uint256) = 1_000_000_000_000_000_000

event PythConfigUpdated:
    max_age: uint256
    max_conf_ratio_wad: uint256

@deploy
def __init__(
    pyth: address,
    feed_id: bytes32,
    max_age_seconds: uint256,
    max_conf_ratio: uint256
):
    self.owner = msg.sender
    self.pyth_contract = pyth
    self.price_feed_id = feed_id
    self.max_age = max_age_seconds
    self.max_conf_ratio_wad = max_conf_ratio

@view
@external
def get_price(asset: address) -> (uint256, uint256):
    pyth_data: PythPrice = staticcall IPyth(self.pyth_contract).getPriceNoOlderThan(self.price_feed_id, self.max_age)
    assert pyth_data.price > 0, "PythAdapter: non-positive price"

    price_u256: uint256 = convert(pyth_data.price, uint256)
    conf_u256: uint256 = convert(pyth_data.conf, uint256)

    # Validate confidence band: (conf * WAD) / price <= max_conf_ratio_wad
    conf_ratio_wad: uint256 = (conf_u256 * WAD) // price_u256
    assert conf_ratio_wad <= self.max_conf_ratio_wad, "PythAdapter: confidence interval too wide"

    # Normalize to 18-decimal WAD using expo
    price_wad: uint256 = 0
    if pyth_data.expo < 0:
        neg_expo: uint256 = convert(-pyth_data.expo, uint256)
        if neg_expo <= 18:
            mult: uint256 = 10 ** (18 - neg_expo)
            price_wad = price_u256 * mult
        else:
            div_val: uint256 = 10 ** (neg_expo - 18)
            price_wad = price_u256 // div_val
    else:
        pos_expo: uint256 = convert(pyth_data.expo, uint256)
        mult: uint256 = 10 ** (18 + pos_expo)
        price_wad = price_u256 * mult

    return (price_wad, pyth_data.publishTime)

@view
@external
def is_valid(asset: address) -> bool:
    pyth_data: PythPrice = staticcall IPyth(self.pyth_contract).getPriceNoOlderThan(self.price_feed_id, self.max_age)
    if pyth_data.price <= 0:
        return False
    price_u256: uint256 = convert(pyth_data.price, uint256)
    conf_u256: uint256 = convert(pyth_data.conf, uint256)
    conf_ratio_wad: uint256 = (conf_u256 * WAD) // price_u256
    if conf_ratio_wad > self.max_conf_ratio_wad:
        return False
    return True

@external
def set_config(max_age_seconds: uint256, max_conf_ratio: uint256):
    assert msg.sender == self.owner, "PythAdapter: unauthorized"
    self.max_age = max_age_seconds
    self.max_conf_ratio_wad = max_conf_ratio
    log PythConfigUpdated(max_age=max_age_seconds, max_conf_ratio_wad=max_conf_ratio)
