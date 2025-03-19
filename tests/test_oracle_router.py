import pytest
import boa

WAD = 10**18

@pytest.fixture
def mock_chainlink_eth():
    # ETH/USD at $3,000.00 with 8 decimals = 300,000,000,000
    return boa.load("contracts/oracles/MockAggregator.vy", 8, 300_000_000_000)

@pytest.fixture
def chainlink_adapter_eth(mock_chainlink_eth):
    # Heartbeat: 3600s, min: $100, max: $50,000
    return boa.load(
        "contracts/oracles/ChainlinkAdapter.vy",
        mock_chainlink_eth.address,
        3600,
        10_000_000_000,
        5_000_000_000_000
    )

@pytest.fixture
def mock_pyth():
    return boa.load("contracts/oracles/MockPyth.vy")

@pytest.fixture
def pyth_adapter_eth(mock_pyth):
    feed_id = b"\x01" * 32
    # Set Pyth price to $3,010.00 (price=301000000000, conf=3000000000 (~1%), expo=-8)
    mock_pyth.set_pyth_price(feed_id, 301_000_000_000, 3_000_000_000, -8, boa.env.timestamp)
    # Max age 3600s, max conf ratio 2% (0.02 * WAD)
    return boa.load(
        "contracts/oracles/PythAdapter.vy",
        mock_pyth.address,
        feed_id,
        3600,
        int(0.02 * WAD)
    )

@pytest.fixture
def twap_oracle():
    return boa.load("contracts/oracles/TWAPOracle.vy", 64)

@pytest.fixture
def price_router(twap_oracle):
    return boa.load("contracts/oracles/PriceFeedRouter.vy", twap_oracle.address)

def test_chainlink_adapter_normalization(chainlink_adapter_eth, mock_chainlink_eth):
    price_wad, updated_at = chainlink_adapter_eth.get_price(boa.env.eoa)
    assert price_wad == 3_000 * WAD
    assert chainlink_adapter_eth.is_valid(boa.env.eoa) is True

    # Test circuit breaker min answer
    mock_chainlink_eth.set_answer(5_000_000_000) # $50 (below min $100)
    assert chainlink_adapter_eth.is_valid(boa.env.eoa) is False
    with boa.reverts("ChainlinkAdapter: answer below min circuit breaker"):
        chainlink_adapter_eth.get_price(boa.env.eoa)

def test_pyth_adapter_confidence_bound(pyth_adapter_eth, mock_pyth):
    feed_id = b"\x01" * 32
    price_wad, pub_time = pyth_adapter_eth.get_price(boa.env.eoa)
    assert price_wad == 3_010 * WAD
    assert pyth_adapter_eth.is_valid(boa.env.eoa) is True

    # Set confidence interval too wide (10% confidence interval)
    mock_pyth.set_pyth_price(feed_id, 301_000_000_000, 35_000_000_000, -8, boa.env.timestamp)
    assert pyth_adapter_eth.is_valid(boa.env.eoa) is False
    with boa.reverts("PythAdapter: confidence interval too wide"):
        pyth_adapter_eth.get_price(boa.env.eoa)

def test_twap_oracle_accumulator(twap_oracle):
    token = boa.env.eoa
    # Observation 1 at current time, price $3,000
    twap_oracle.record_observation(token, 3000 * WAD)

    # Observation 2 at +600s, price $3,600
    boa.env.time_travel(seconds=600)
    twap_oracle.record_observation(token, 3600 * WAD)

    # TWAP over 600s
    twap_price = twap_oracle.get_twap(token, 600)
    assert twap_price == 3600 * WAD

def test_price_router_multi_source(price_router, chainlink_adapter_eth, pyth_adapter_eth, mock_chainlink_eth, mock_pyth):
    token = boa.env.eoa
    mock_chainlink_eth.set_answer(300_000_000_000) # $3,000
    feed_id = b"\x01" * 32
    mock_pyth.set_pyth_price(feed_id, 301_000_000_000, 1_000_000_000, -8, boa.env.timestamp) # $3,010

    # Max deviation: 3% (0.03 * WAD)
    price_router.set_asset_feeds(
        token,
        chainlink_adapter_eth.address,
        pyth_adapter_eth.address,
        int(0.03 * WAD),
        1800
    )

    # Within tolerance: returns average of 3,000 and 3,010 = 3,005
    agreed_price = price_router.get_asset_price(token)
    assert agreed_price == 3_005 * WAD
