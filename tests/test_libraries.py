import pytest
import boa
from eth_utils import keccak

@pytest.fixture(scope="module")
def bitmaps():
    return boa.load("contracts/libraries/BitMaps.vy")

@pytest.fixture(scope="module")
def merkle():
    return boa.load("contracts/libraries/MerkleProof.vy")

def test_bitmaps_in_memory(bitmaps):
    # Test individual bit setting
    bm = 0
    bm = bitmaps.set_bit(bm, 0)
    bm = bitmaps.set_bit(bm, 15)
    bm = bitmaps.set_bit(bm, 255)

    assert bitmaps.get_bit(bm, 0) is True
    assert bitmaps.get_bit(bm, 15) is True
    assert bitmaps.get_bit(bm, 255) is True
    assert bitmaps.get_bit(bm, 1) is False
    assert bitmaps.get_bit(bm, 14) is False
    assert bitmaps.get_bit(bm, 254) is False

    # Test unsetting bit
    bm = bitmaps.unset_bit(bm, 15)
    assert bitmaps.get_bit(bm, 15) is False
    assert bitmaps.get_bit(bm, 0) is True

    # Test popcount
    assert bitmaps.popcount(bm) == 2
    assert bitmaps.popcount(0) == 0
    assert bitmaps.popcount((1 << 256) - 1) == 256

def test_bitmaps_storage(bitmaps):
    # Check across bucket boundaries
    idx1 = 42
    idx2 = 300 # bucket 1, offset 44
    idx3 = 1000 # bucket 3, offset 232

    assert bitmaps.is_storage_set(idx1) is False
    bitmaps.set_storage_bit(idx1)
    bitmaps.set_storage_bit(idx2)
    bitmaps.set_storage_bit(idx3)

    assert bitmaps.is_storage_set(idx1) is True
    assert bitmaps.is_storage_set(idx2) is True
    assert bitmaps.is_storage_set(idx3) is True
    assert bitmaps.is_storage_set(idx1 + 1) is False

    bitmaps.unset_storage_bit(idx2)
    assert bitmaps.is_storage_set(idx2) is False
    assert bitmaps.is_storage_set(idx1) is True
    assert bitmaps.is_storage_set(idx3) is True

def test_merkle_proof(merkle):
    def hash_pair(a: bytes, b: bytes) -> bytes:
        if int.from_bytes(a, "big") < int.from_bytes(b, "big"):
            return keccak(a + b)
        else:
            return keccak(b + a)

    # 4 leaves
    leaf0 = keccak(b"account0")
    leaf1 = keccak(b"account1")
    leaf2 = keccak(b"account2")
    leaf3 = keccak(b"account3")

    h01 = hash_pair(leaf0, leaf1)
    h23 = hash_pair(leaf2, leaf3)
    root = hash_pair(h01, h23)

    # Proof for leaf0: [leaf1, h23]
    proof0 = [leaf1, h23]
    assert merkle.verify(proof0, root, leaf0) is True

    # Proof for leaf2: [leaf3, h01]
    proof2 = [leaf3, h01]
    assert merkle.verify(proof2, root, leaf2) is True

    # Invalid leaf with proof0 fails
    assert merkle.verify(proof0, root, leaf2) is False
