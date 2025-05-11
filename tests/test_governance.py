import pytest
import boa
from eth_utils import keccak

@pytest.fixture
def council():
    # 2 days timelock delay = 172,800 seconds
    return boa.load("contracts/governance/EmergencyCouncil.vy", 172_800)

@pytest.fixture
def params(council):
    return boa.load("contracts/governance/ProtocolParameters.vy", council.address)

def test_emergency_pause_by_guardian(council):
    guardian = boa.env.generate_address()
    council.set_guardian(guardian, True)
    assert council.is_guardian(guardian) is True

    feature_borrow = keccak(b"FEATURE_BORROW")
    assert council.is_paused(feature_borrow) is False

    # Guardian pauses borrows immediately
    with boa.env.prank(guardian):
        council.pause_feature(feature_borrow)
    assert council.is_paused(feature_borrow) is True

    # Unauthorized address cannot unpause
    unauth = boa.env.generate_address()
    with boa.env.prank(unauth):
        with boa.reverts("EmergencyCouncil: unauthorized"):
            council.unpause_feature(feature_borrow)

    # Owner unpauses
    council.unpause_feature(feature_borrow)
    assert council.is_paused(feature_borrow) is False

def test_timelock_queue_and_execute(council):
    action_hash = keccak(b"UPDATE_RISK_MODEL_USDC")
    eta = council.queue_action(action_hash)

    # Attempt to execute immediately reverts
    with boa.reverts("EmergencyCouncil: timelock not expired"):
        council.execute_action(action_hash)

    # Advance time by 2 days (172,800s)
    boa.env.time_travel(seconds=172_800)

    # Now execution succeeds
    council.execute_action(action_hash)
    assert council.queued_actions(action_hash) == 0

def test_protocol_parameters_registry(params):
    key = keccak(b"MIN_HEALTH_FACTOR")
    params.set_uint_param(key, 10**18)
    assert params.get_uint_param(key) == 10**18
