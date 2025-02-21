import pytest
import boa

WAD = 10**18
RAY = 10**27

@pytest.fixture(scope="module")
def math_lib():
    return boa.load("contracts/libraries/MathLib.vy")

def test_wad_constants(math_lib):
    assert math_lib.get_wad() == WAD
    assert math_lib.get_ray() == RAY

def test_wad_mul_basic(math_lib):
    # 1.0 * 1.0 = 1.0
    assert math_lib.wad_mul(WAD, WAD) == WAD
    # 2.5 * 4.0 = 10.0
    assert math_lib.wad_mul(int(2.5 * WAD), 4 * WAD) == 10 * WAD
    # Zero multiplication
    assert math_lib.wad_mul(0, 100 * WAD) == 0
    assert math_lib.wad_mul(100 * WAD, 0) == 0

def test_wad_div_basic(math_lib):
    # 10.0 / 2.0 = 5.0
    assert math_lib.wad_div(10 * WAD, 2 * WAD) == 5 * WAD
    # 1.0 / 3.0 with half-up rounding
    one_third = math_lib.wad_div(WAD, 3 * WAD)
    assert one_third == 333333333333333333
    # Division by zero reverts
    with boa.reverts("MathLib: division by zero"):
        math_lib.wad_div(WAD, 0)

def test_ray_mul_and_div(math_lib):
    assert math_lib.ray_mul(RAY, RAY) == RAY
    assert math_lib.ray_mul(2 * RAY, 3 * RAY) == 6 * RAY
    assert math_lib.ray_div(6 * RAY, 2 * RAY) == 3 * RAY
    with boa.reverts("MathLib: division by zero"):
        math_lib.ray_div(RAY, 0)

def test_wad_to_ray_and_back(math_lib):
    val = 42 * WAD
    ray_val = math_lib.wad_to_ray(val)
    assert ray_val == 42 * RAY
    assert math_lib.ray_to_wad(ray_val) == val

def test_scale_decimals(math_lib):
    # USDC (6 decimals) 1,500 USDC = 1,500,000,000 units
    usdc_raw = 1_500_000_000
    usdc_wad = math_lib.scale_to_wad(usdc_raw, 6)
    assert usdc_wad == 1_500 * WAD
    assert math_lib.scale_from_wad(usdc_wad, 6) == usdc_raw

    # WBTC (8 decimals) 2.5 WBTC = 250,000,000 units
    wbtc_raw = 250_000_000
    wbtc_wad = math_lib.scale_to_wad(wbtc_raw, 8)
    assert wbtc_wad == int(2.5 * WAD)
    assert math_lib.scale_from_wad(wbtc_wad, 8) == wbtc_raw

    # 18 decimals (identity)
    assert math_lib.scale_to_wad(10 * WAD, 18) == 10 * WAD
    assert math_lib.scale_from_wad(10 * WAD, 18) == 10 * WAD

def test_sqrt_u256(math_lib):
    assert math_lib.sqrt_u256(0) == 0
    assert math_lib.sqrt_u256(1) == 1
    assert math_lib.sqrt_u256(4) == 2
    assert math_lib.sqrt_u256(9) == 3
    assert math_lib.sqrt_u256(10) == 3 # floor(sqrt(10))
    assert math_lib.sqrt_u256(100) == 10
    assert math_lib.sqrt_u256(1_000_000) == 1_000
    assert math_lib.sqrt_u256(10**36) == 10**18

def test_ray_pow(math_lib):
    # RAY^0 = RAY
    assert math_lib.ray_pow(RAY, 0) == RAY
    # RAY^10 = RAY
    assert math_lib.ray_pow(RAY, 10) == RAY
    # 2^3 = 8
    two_ray = 2 * RAY
    assert math_lib.ray_pow(two_ray, 3) == 8 * RAY

def test_min_max_abs(math_lib):
    assert math_lib.min_u256(10, 20) == 10
    assert math_lib.min_u256(50, 20) == 20
    assert math_lib.max_u256(10, 20) == 20
    assert math_lib.max_u256(50, 20) == 50
    assert math_lib.abs_diff(100, 30) == 70
    assert math_lib.abs_diff(30, 100) == 70
