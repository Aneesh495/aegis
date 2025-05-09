# @version ^0.4.0
"""
@title EmergencyCouncil
@notice Multi-signature timelock and circuit breaker controller.
@dev Supports fast-path emergency pause by authorized guardians and timelocked recovery.
"""

owner: public(address)
timelock_delay: public(uint256)
is_guardian: public(HashMap[address, bool])
is_paused: public(HashMap[bytes32, bool])
emergency_shutdown_active: public(bool)

# Timelocked action queue: action_hash => execution_timestamp
queued_actions: public(HashMap[bytes32, uint256])

FEATURE_BORROW: constant(bytes32) = keccak256("FEATURE_BORROW")
FEATURE_WITHDRAW: constant(bytes32) = keccak256("FEATURE_WITHDRAW")
FEATURE_LIQUIDATION: constant(bytes32) = keccak256("FEATURE_LIQUIDATION")
FEATURE_TRADE: constant(bytes32) = keccak256("FEATURE_TRADE")

event FeaturePaused:
    feature_id: indexed(bytes32)
    caller: indexed(address)

event FeatureUnpaused:
    feature_id: indexed(bytes32)
    caller: indexed(address)

event EmergencyShutdownTriggered:
    caller: indexed(address)
    timestamp: uint256

event GuardianSet:
    guardian: indexed(address)
    status: bool

event ActionQueued:
    action_hash: indexed(bytes32)
    eta: uint256

event ActionExecuted:
    action_hash: indexed(bytes32)

@deploy
def __init__(delay_seconds: uint256):
    self.owner = msg.sender
    self.timelock_delay = delay_seconds
    self.is_guardian[msg.sender] = True

@external
def set_guardian(guardian: address, status: bool):
    assert msg.sender == self.owner, "EmergencyCouncil: unauthorized"
    self.is_guardian[guardian] = status
    log GuardianSet(guardian=guardian, status=status)

@external
def pause_feature(feature_id: bytes32):
    """
    @notice Guardians can immediately pause a feature to contain protocol risk.
    """
    assert self.is_guardian[msg.sender] or msg.sender == self.owner, "EmergencyCouncil: unauthorized"
    self.is_paused[feature_id] = True
    log FeaturePaused(feature_id=feature_id, caller=msg.sender)

@external
def unpause_feature(feature_id: bytes32):
    """
    @notice Only owner can unpause features.
    """
    assert msg.sender == self.owner, "EmergencyCouncil: unauthorized"
    self.is_paused[feature_id] = False
    log FeatureUnpaused(feature_id=feature_id, caller=msg.sender)

@external
def trigger_emergency_shutdown():
    """
    @notice Immediate global halt in event of critical vulnerability.
    """
    assert self.is_guardian[msg.sender] or msg.sender == self.owner, "EmergencyCouncil: unauthorized"
    self.emergency_shutdown_active = True
    log EmergencyShutdownTriggered(caller=msg.sender, timestamp=block.timestamp)

@external
def queue_action(action_hash: bytes32) -> uint256:
    assert msg.sender == self.owner, "EmergencyCouncil: unauthorized"
    eta: uint256 = block.timestamp + self.timelock_delay
    self.queued_actions[action_hash] = eta
    log ActionQueued(action_hash=action_hash, eta=eta)
    return eta

@external
def execute_action(action_hash: bytes32):
    assert msg.sender == self.owner, "EmergencyCouncil: unauthorized"
    eta: uint256 = self.queued_actions[action_hash]
    assert eta > 0, "EmergencyCouncil: action not queued"
    assert block.timestamp >= eta, "EmergencyCouncil: timelock not expired"

    self.queued_actions[action_hash] = 0
    log ActionExecuted(action_hash=action_hash)
