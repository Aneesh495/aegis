# @version ^0.4.0
"""
@title BitMaps
@notice Optimized 256-bit bitfield and multi-word bitmap manipulation library.
@dev Provides gas-efficient tracking of order fills, auction states, and security flags.
"""

# Dynamic storage bitmap mapping: bucket_index => 256-bit word
storage_bitmap: HashMap[uint256, uint256]

@pure
@external
def get_bit(bitmap: uint256, index: uint256) -> bool:
    """
    @notice Returns true if the bit at `index` is 1.
    """
    assert index < 256, "BitMaps: index out of bounds"
    mask: uint256 = 1 << index
    return (bitmap & mask) != 0

@pure
@external
def set_bit(bitmap: uint256, index: uint256) -> uint256:
    """
    @notice Sets the bit at `index` to 1.
    """
    assert index < 256, "BitMaps: index out of bounds"
    mask: uint256 = 1 << index
    return bitmap | mask

@pure
@external
def unset_bit(bitmap: uint256, index: uint256) -> uint256:
    """
    @notice Clears the bit at `index` to 0.
    """
    assert index < 256, "BitMaps: index out of bounds"
    mask: uint256 = ~(1 << index)
    return bitmap & mask

@view
@external
def is_storage_set(index: uint256) -> bool:
    """
    @notice Checks if a global index is set in storage bitmap.
    """
    bucket: uint256 = index // 256
    bit_offset: uint256 = index % 256
    word: uint256 = self.storage_bitmap[bucket]
    mask: uint256 = 1 << bit_offset
    return (word & mask) != 0

@external
def set_storage_bit(index: uint256):
    """
    @notice Sets a global index in storage bitmap.
    """
    bucket: uint256 = index // 256
    bit_offset: uint256 = index % 256
    word: uint256 = self.storage_bitmap[bucket]
    mask: uint256 = 1 << bit_offset
    self.storage_bitmap[bucket] = word | mask

@external
def unset_storage_bit(index: uint256):
    """
    @notice Unsets a global index in storage bitmap.
    """
    bucket: uint256 = index // 256
    bit_offset: uint256 = index % 256
    word: uint256 = self.storage_bitmap[bucket]
    mask: uint256 = ~(1 << bit_offset)
    self.storage_bitmap[bucket] = word & mask

@pure
@external
def popcount(x: uint256) -> uint256:
    """
    @notice Computes Hamming weight (number of set bits) in a 256-bit word.
    """
    count: uint256 = 0
    temp: uint256 = x
    for i: uint256 in range(256):
        if temp == 0:
            break
        count += (temp & 1)
        temp = temp >> 1
    return count
