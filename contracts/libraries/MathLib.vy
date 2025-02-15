# @version ^0.4.0
"""
@title MathLib
@notice Comprehensive Fixed-Point WAD (18 decimals) and RAY (27 decimals) arithmetic library.
@dev All operations implement half-up rounding to minimize cumulative rounding bias.
"""

WAD: constant(uint256) = 1_000_000_000_000_000_000 # 10^18
HALF_WAD: constant(uint256) = 500_000_000_000_000_000

RAY: constant(uint256) = 1_000_000_000_000_000_000_000_000_000 # 10^27
HALF_RAY: constant(uint256) = 500_000_000_000_000_000_000_000_000

RAY_WAD_RATIO: constant(uint256) = 1_000_000_000 # 10^9

@pure
@external
def get_wad() -> uint256:
    return WAD

@pure
@external
def get_ray() -> uint256:
    return RAY

@pure
@external
def wad_mul(a: uint256, b: uint256) -> uint256:
    if a == 0 or b == 0:
        return 0
    return (a * b + HALF_WAD) // WAD

@pure
@external
def wad_div(a: uint256, b: uint256) -> uint256:
    assert b > 0, "MathLib: division by zero"
    return (a * WAD + b // 2) // b

@pure
@external
def ray_mul(a: uint256, b: uint256) -> uint256:
    if a == 0 or b == 0:
        return 0
    return (a * b + HALF_RAY) // RAY

@pure
@external
def ray_div(a: uint256, b: uint256) -> uint256:
    assert b > 0, "MathLib: division by zero"
    return (a * RAY + b // 2) // b

@pure
@external
def wad_to_ray(a: uint256) -> uint256:
    return a * RAY_WAD_RATIO

@pure
@external
def ray_to_wad(a: uint256) -> uint256:
    return (a + RAY_WAD_RATIO // 2) // RAY_WAD_RATIO

@pure
@external
def min_u256(a: uint256, b: uint256) -> uint256:
    if a < b:
        return a
    return b

@pure
@external
def max_u256(a: uint256, b: uint256) -> uint256:
    if a > b:
        return a
    return b

@pure
@external
def abs_diff(a: uint256, b: uint256) -> uint256:
    if a >= b:
        return a - b
    return b - a

@pure
@external
def sqrt_u256(x: uint256) -> uint256:
    if x == 0:
        return 0
    z: uint256 = (x + 1) // 2
    y: uint256 = x
    for i: uint256 in range(256):
        if z >= y:
            break
        y = z
        z = (x // z + z) // 2
    return y

@pure
@external
def ray_pow(x: uint256, n: uint256) -> uint256:
    """
    @notice Exponentiation by squaring in RAY precision.
    @param x Base in RAY.
    @param n Exponent integer.
    @return Result in RAY.
    """
    if n == 0:
        return RAY
    z: uint256 = x
    if n % 2 != 0:
        z = x
    else:
        z = RAY
    
    half_ray: uint256 = HALF_RAY
    ray_val: uint256 = RAY
    exp: uint256 = n // 2
    base: uint256 = x

    for i: uint256 in range(64):
        if exp == 0:
            break
        base = (base * base + half_ray) // ray_val
        if exp % 2 != 0:
            z = (z * base + half_ray) // ray_val
        exp = exp // 2
    return z

@pure
@external
def scale_to_wad(amount: uint256, decimals: uint8) -> uint256:
    """
    @notice Scales token balance with arbitrary decimals to 18-decimal WAD.
    """
    if decimals == 18:
        return amount
    elif decimals < 18:
        diff: uint256 = convert(18 - decimals, uint256)
        return amount * (10 ** diff)
    else:
        diff: uint256 = convert(decimals - 18, uint256)
        return amount // (10 ** diff)

@pure
@external
def scale_from_wad(wad_amount: uint256, decimals: uint8) -> uint256:
    """
    @notice Scales 18-decimal WAD amount down to token native decimals.
    """
    if decimals == 18:
        return wad_amount
    elif decimals < 18:
        diff: uint256 = convert(18 - decimals, uint256)
        return wad_amount // (10 ** diff)
    else:
        diff: uint256 = convert(decimals - 18, uint256)
        return wad_amount * (10 ** diff)
