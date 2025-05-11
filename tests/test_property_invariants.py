import pytest
import boa
from hypothesis import given, settings, strategies as st

WAD = 10**18
RAY = 10**27

@pytest.fixture(scope="module")
def math_lib():
    return boa.load("contracts/libraries/MathLib.vy")

@settings(max_examples=50, deadline=None)
@given(
    a=st.integers(min_value=0, max_value=10**24),
    b=st.integers(min_value=0, max_value=10**24)
)
def test_wad_mul_commutativity(math_lib, a, b):
    res1 = math_lib.wad_mul(a, b)
    res2 = math_lib.wad_mul(b, a)
    assert res1 == res2

@settings(max_examples=50, deadline=None)
@given(
    x=st.integers(min_value=WAD, max_value=10**28),
    y=st.integers(min_value=10**17, max_value=10**21)
)
def test_wad_mul_div_inversion(math_lib, x, y):
    # Fixed-point integer rounding bound: error <= (WAD // y) + 2
    prod = math_lib.wad_mul(x, y)
    recovered = math_lib.wad_div(prod, y)
    max_rounding_error = (WAD // y) + 2
    assert abs(recovered - x) <= max_rounding_error

@settings(max_examples=50, deadline=None)
@given(x=st.integers(min_value=0, max_value=10**36))
def test_sqrt_invariant(math_lib, x):
    # sqrt(x)^2 <= x < (sqrt(x) + 1)^2
    r = math_lib.sqrt_u256(x)
    assert r * r <= x
    assert (r + 1) * (r + 1) > x

def test_waterfall_loss_ordering_properties():
    vault = boa.load("contracts/core/AegisVault.vy", 10)
    usdc = boa.load("contracts/core/MockERC20.vy", "USDC", "USDC", 6)
    de = boa.load("contracts/core/DebtEngine.vy", vault.address)

    # Seed tranches: Senior 100k, Mezz 50k, Junior 25k
    user = boa.env.eoa
    usdc.mint(user, 175_000 * 10**6)
    usdc.approve(de.address, 175_000 * 10**6)
    de.deposit_tranche(usdc.address, 0, 100_000 * 10**6, user)
    de.deposit_tranche(usdc.address, 1, 50_000 * 10**6, user)
    de.deposit_tranche(usdc.address, 2, 25_000 * 10**6, user)

    # Test bad debt of 20k (less than Junior 25k)
    j1, m1, s1 = de.absorb_bad_debt(usdc.address, 20_000 * 10**6)
    assert j1 == 20_000 * 10**6
    assert m1 == 0
    assert s1 == 0
    assert de.get_tranche_supply(usdc.address, 2) == 5_000 * 10**6
    assert de.get_tranche_supply(usdc.address, 1) == 50_000 * 10**6
    assert de.get_tranche_supply(usdc.address, 0) == 100_000 * 10**6

    # Test additional bad debt of 40k (wipes out remaining 5k Junior and 35k of Mezz)
    j2, m2, s2 = de.absorb_bad_debt(usdc.address, 40_000 * 10**6)
    assert j2 == 5_000 * 10**6
    assert m2 == 35_000 * 10**6
    assert s2 == 0
    assert de.get_tranche_supply(usdc.address, 2) == 0
    assert de.get_tranche_supply(usdc.address, 1) == 15_000 * 10**6
    assert de.get_tranche_supply(usdc.address, 0) == 100_000 * 10**6
