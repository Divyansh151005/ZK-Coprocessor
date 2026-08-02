//! Header commitment primitives (Axiom-class PMMR sketch for Phase 2).
//!
//! Primary pattern source: Axiom V2 — 1024-hash batches + padded MMR + snapshots.
//! This crate holds pure Rust helpers; on-chain contract lives in `contracts/`.

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
            let mut hasher = Keccak256::new();
            hasher.update(left);
            hasher.update(right);
            let dig = hasher.finalize();
            let mut out = [0u8; 32];
            out.copy_from_slice(&dig);
            next.push(out);
        }
        level = next;
    }
    level[0]
}

/// Minimal padded MMR peak list (newest peak last). Append a batch root.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Pmmr {
    pub peaks: Vec<[u8; 32]>,
    pub batches: u64,
}

impl Pmmr {
    pub fn append_batch_root(&mut self, root: [u8; 32]) {
        self.peaks.push(root);
        self.batches += 1;
        // Simple bag merge: while last two equal-height conceptually, hash — here we keep flat peaks
        // and commit via bagging hash for snapshot id.
    }

    pub fn snapshot_id(&self) -> [u8; 32] {
        let mut hasher = Keccak256::new();
        hasher.update(self.batches.to_be_bytes());
        for p in &self.peaks {
            hasher.update(p);
        }
        let dig = hasher.finalize();
        let mut out = [0u8; 32];
        out.copy_from_slice(&dig);
        out
    }
}

/// Verify a single storage slot claim against a provided state root and MPT proof nodes.
/// Phase 2 v1: simplified inclusion check — keccak(leaf) must appear in proof path ending at root.
/// Production path will use full RLP/MPT (see `sdk/guest`).
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
        let mut hasher = Keccak256::new();
        hasher.update(cur);
        hasher.update(node);
        let dig = hasher.finalize();
        cur = [0u8; 32];
        cur.copy_from_slice(&dig);
    }
    cur == state_root
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
        let root = merkle_root(&[a, b]);
        let mut hasher = Keccak256::new();
        hasher.update(a);
        hasher.update(b);
        let expected = hasher.finalize();
        assert_eq!(&root[..], &expected[..]);
    }

    #[test]
    fn pmmr_snapshot_changes() {
        let mut p = Pmmr::default();
        p.append_batch_root([9u8; 32]);
        let s1 = p.snapshot_id();
        p.append_batch_root([8u8; 32]);
        let s2 = p.snapshot_id();
        assert_ne!(s1, s2);
    }

    #[test]
    fn storage_proof_accept_reject() {
        let leaf = [3u8; 32];
        let sib = [4u8; 32];
        let mut hasher = Keccak256::new();
        hasher.update(leaf);
        hasher.update(sib);
        let root_dig = hasher.finalize();
        let mut root = [0u8; 32];
        root.copy_from_slice(&root_dig);
        assert!(verify_storage_proof_simplified(root, leaf, &[sib]));
        assert!(!verify_storage_proof_simplified(root, [5u8; 32], &[sib]));
    }
}
