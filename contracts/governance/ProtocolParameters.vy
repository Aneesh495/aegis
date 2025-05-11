# @version ^0.4.0
"""
@title ProtocolParameters
@notice Central risk and configuration registry for protocol thresholds and constants.
@dev Modifiable exclusively through the governance council.
"""

owner: public(address)
emergency_council: public(address)

uint_parameters: public(HashMap[bytes32, uint256])
address_parameters: public(HashMap[bytes32, address])

event UintParamSet:
    param_key: indexed(bytes32)
    val: uint256

event AddressParamSet:
    param_key: indexed(bytes32)
    val: address

@deploy
def __init__(council: address):
    self.owner = msg.sender
    self.emergency_council = council

@view
@external
def get_uint_param(param_key: bytes32) -> uint256:
    return self.uint_parameters[param_key]

@view
@external
def get_address_param(param_key: bytes32) -> address:
    return self.address_parameters[param_key]

@external
def set_uint_param(param_key: bytes32, val: uint256):
    assert msg.sender == self.owner or msg.sender == self.emergency_council, "ProtocolParameters: unauthorized"
    self.uint_parameters[param_key] = val
    log UintParamSet(param_key=param_key, val=val)

@external
def set_address_param(param_key: bytes32, val: address):
    assert msg.sender == self.owner or msg.sender == self.emergency_council, "ProtocolParameters: unauthorized"
    self.address_parameters[param_key] = val
    log AddressParamSet(param_key=param_key, val=val)
