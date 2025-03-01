# @version ^0.4.0
"""
@title MerkleProof
@notice Standard cryptographic verification for Merkle trees.
@dev Supports ordered pair hashing with keccak256 to prevent second-preimage attacks.
"""

@pure
@internal
def _hash_pair(a: bytes32, b: bytes32) -> bytes32:
    if convert(a, uint256) < convert(b, uint256):
        return keccak256(concat(a, b))
    else:
        return keccak256(concat(b, a))

@pure
@external
def verify(proof: DynArray[bytes32, 32], root: bytes32, leaf: bytes32) -> bool:
    """
    @notice Verifies a Merkle proof proving leaf membership in root.
    @param proof Array of sibling hashes along the branch.
    @param root The anticipated Merkle root.
    @param leaf The leaf element hash to prove.
    @return True if the computed hash equals root.
    """
    computed: bytes32 = leaf
    for elem: bytes32 in proof:
        computed = self._hash_pair(computed, elem)
    return computed == root
