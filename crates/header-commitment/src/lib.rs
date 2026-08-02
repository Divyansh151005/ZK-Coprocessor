//! Header commitment primitives (Axiom-class PMMR for Phase 2).
//!
//! Pattern: 1024-hash batches + bagged peaks → snapshot id (Axiom-style).
//! On-chain: `contracts/src/HeaderCommitment.sol`.

use sha3::{Digest, Keccak256};

pub const BATCH_SIZE: usize = 1024;

/// Keccak Merkle root over a list of 32-byte leaves (pairwise; odd last duplicated).
pub fn merkle_root(leaves: &[[u8; 32]]) -> [u8; 32] {
    assert!(!leaves.is_empty(), "empty leaves");
    let mut level: Vec<[u8; 32]> = leaves.to_vec();
    while level.len() > 1 {
        let mut next = Vec::with_capacity(level.len().div_ceil(2));
        for chunk in level.chunks(2) {
            let left = chunk[0];
            let right = if chunk.len() == 2 { chunk[1] } else { chunk[0] };
            next.push(keccak2(&left, &right));
        }
        level = next;
    }
    level[0]
}

fn keccak2(a: &[u8; 32], b: &[u8; 32]) -> [u8; 32] {
    let mut hasher = Keccak256::new();
    hasher.update(a);
    hasher.update(b);
    let dig = hasher.finalize();
    let mut out = [0u8; 32];
    out.copy_from_slice(&dig);
    out
}

fn keccak_bag(peaks: &[[u8; 32]], batches: u64) -> [u8; 32] {
    let mut hasher = Keccak256::new();
    hasher.update(batches.to_be_bytes());
    for p in peaks {
        hasher.update(p);
    }
    let dig = hasher.finalize();
    let mut out = [0u8; 32];
    out.copy_from_slice(&dig);
    out
}

/// Padded MMR peak list. Append batch roots; snapshot id bags all peaks.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Pmmr {
    pub peaks: Vec<[u8; 32]>,
    pub batches: u64,
}

impl Pmmr {
    pub fn snapshot_id(&self) -> [u8; 32] {
        if self.peaks.is_empty() && self.batches == 0 {
            return [0u8; 32]; // matches HeaderCommitment constructor
        }
        keccak_bag(&self.peaks, self.batches)
    }

    /// Append a batch merkle root; returns (prev_snapshot, new_snapshot).
    pub fn append_batch_root(&mut self, root: [u8; 32]) -> ([u8; 32], [u8; 32]) {
        let prev = self.snapshot_id();
        self.peaks.push(root);
        self.batches += 1;
        // Bag-merge: while ≥2 peaks, fold last two (keeps peak list bounded for tests/demos).
        while self.peaks.len() >= 2 {
            let b = self.peaks.pop().unwrap();
            let a = self.peaks.pop().unwrap();
            self.peaks.push(keccak2(&a, &b));
        }
        let next = self.snapshot_id();
        (prev, next)
    }
}

/// Public values matching `HeaderCommitment.UpdatePublicValues`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct UpdatePublicValues {
    pub start_block: u64,
    pub batch_root: [u8; 32],
    pub prev_snapshot_id: [u8; 32],
    pub new_snapshot_id: [u8; 32],
}

impl UpdatePublicValues {
    /// Build update for `start_block` (must be multiple of 1024) from headers (len ≤ BATCH_SIZE).
    pub fn from_headers(pmmr: &mut Pmmr, start_block: u64, headers: &[[u8; 32]]) -> Self {
        assert_eq!(start_block % BATCH_SIZE as u64, 0, "start_block must be multiple of 1024");
        assert!(!headers.is_empty());
        assert!(headers.len() <= BATCH_SIZE);
        let mut leaves = headers.to_vec();
        while leaves.len() < BATCH_SIZE {
            leaves.push(*leaves.last().unwrap());
        }
        let batch_root = merkle_root(&leaves);
        let (prev, next) = pmmr.append_batch_root(batch_root);
        Self {
            start_block,
            batch_root,
            prev_snapshot_id: prev,
            new_snapshot_id: next,
        }
    }

    /// Anvil/demo: treat a single trusted `state_root` as a 1-leaf batch padded to 1024.
    pub fn from_state_root(pmmr: &mut Pmmr, start_block: u64, state_root: [u8; 32]) -> Self {
        Self::from_headers(pmmr, start_block, &[state_root])
    }
}

/// Verify a single storage slot claim against a provided state root and MPT proof nodes.
/// Legacy simplified path (hash chain). Prefer alloy-trie in guest / `verify_against_commitment`.
pub fn verify_storage_proof_simplified(
    state_root: [u8; 32],
    leaf_value: [u8; 32],
    proof_nodes: &[[u8; 32]],
) -> bool {
    if proof_nodes.is_empty() {
        return leaf_value == state_root;
    }
    let mut cur = leaf_value;
    for node in proof_nodes {
        cur = keccak2(&cur, node);
    }
    cur == state_root
}

/// True if `state_root` equals the committed batch root (v1 Anvil: batch encodes state root).
pub fn state_root_matches_commitment(committed_batch_root: [u8; 32], state_root: [u8; 32]) -> bool {
        let leaves = vec![state_root; BATCH_SIZE];
        let expected = merkle_root(&leaves);    committed_batch_root == expected
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn merkle_single() {
        let leaf = [1u8; 32];
        assert_eq!(merkle_root(&[leaf]), leaf);
    }

    #[test]
    fn merkle_two() {
        let a = [1u8; 32];
        let b = [2u8; 32];
        assert_eq!(merkle_root(&[a, b]), keccak2(&a, &b));
    }

    #[test]
    fn pmmr_snapshot_changes() {
        let mut p = Pmmr::default();
        let (prev0, s1) = p.append_batch_root([9u8; 32]);
        assert_eq!(prev0, [0u8; 32]);
        let (prev1, s2) = p.append_batch_root([8u8; 32]);
        assert_eq!(prev1, s1);
        assert_ne!(s1, s2);
    }

    #[test]
    fn update_from_state_root_roundtrip() {
        let mut p = Pmmr::default();
        let sr = [7u8; 32];
        let uv = UpdatePublicValues::from_state_root(&mut p, 0, sr);
        assert!(state_root_matches_commitment(uv.batch_root, sr));
        assert_eq!(uv.prev_snapshot_id, [0u8; 32]); // empty bag: batches=0 peaks=[]
        assert_ne!(uv.new_snapshot_id, uv.prev_snapshot_id);
    }

    #[test]
    fn storage_proof_accept_reject() {
        let leaf = [3u8; 32];
        let sib = [4u8; 32];
        let root = keccak2(&leaf, &sib);
        assert!(verify_storage_proof_simplified(root, leaf, &[sib]));
        assert!(!verify_storage_proof_simplified(root, [5u8; 32], &[sib]));
    }

    #[test]
    fn tamper_batch_root_fails_match() {
        let mut p = Pmmr::default();
        let uv = UpdatePublicValues::from_state_root(&mut p, 0, [1u8; 32]);
        assert!(!state_root_matches_commitment(uv.batch_root, [2u8; 32]));
    }
}
