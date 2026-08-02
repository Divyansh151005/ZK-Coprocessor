//! Guest SDK surface matching End_Goal DX (`env::read` / `commit` / `read_state`).

use header_commitment::{
    state_root_matches_commitment, verify_storage_proof_simplified, UpdatePublicValues, Pmmr,
};

/// Host-side mirror of guest env helpers for unit tests and codegen docs.
pub mod env {
    use super::*;

    pub fn read_u64_pair(a: u64, b: u64) -> (u64, u64) {
        (a, b)
    }

    pub fn commit_sum(a: u64, b: u64) -> u64 {
        a.wrapping_add(b)
    }

    /// Legacy simplified hash-chain check (unit tests / demos).
    pub fn read_state_simplified(
        state_root: [u8; 32],
        leaf_value: [u8; 32],
        proof_nodes: &[[u8; 32]],
    ) -> Result<[u8; 32], &'static str> {
        if verify_storage_proof_simplified(state_root, leaf_value, proof_nodes) {
            Ok(leaf_value)
        } else {
            Err("tampered or invalid storage proof")
        }
    }

    /// End_Goal-shaped API: require `state_root` to match a HeaderCommitment batch root
    /// (v1: batch is merkle of padded state-root leaves), then run simplified leaf check.
    ///
    /// Production guests use `alloy-trie` inside the zkVM (`guest-mpt`); this helper documents
    /// the commitment binding for app authors and host-side tests.
    pub fn read_state(
        committed_batch_root: [u8; 32],
        state_root: [u8; 32],
        leaf_value: [u8; 32],
        proof_nodes: &[[u8; 32]],
    ) -> Result<[u8; 32], &'static str> {
        if !state_root_matches_commitment(committed_batch_root, state_root) {
            return Err("state root not under header commitment batch");
        }
        read_state_simplified(state_root, leaf_value, proof_nodes)
    }

    /// Build header-update public values for mock `HeaderCommitment.commitBatch`.
    pub fn header_update_from_state_root(state_root: [u8; 32]) -> UpdatePublicValues {
        let mut pmmr = Pmmr::default();
        UpdatePublicValues::from_state_root(&mut pmmr, 0, state_root)
    }
}

/// Journal ABI codegen helper: document Solidity struct <-> Rust field order.
pub mod journal {
    pub const PHASE0_FIELDS: &[&str] = &["a", "b", "sum"];
    pub const PHASE1_FIELDS: &[&str] = &["requestId", "a", "b", "sum"];
    pub const STORAGE_FIELDS: &[&str] = &["stateRoot", "account", "slot", "value"];

    pub fn phase0_solidity() -> &'static str {
        "struct PublicValues { uint64 a; uint64 b; uint64 sum; }"
    }

    pub fn phase1_solidity() -> &'static str {
        "struct PublicValuesV1 { uint256 requestId; uint64 a; uint64 b; uint64 sum; }"
    }

    pub fn storage_solidity() -> &'static str {
        "struct StorageProofPublicValues { bytes32 stateRoot; address account; bytes32 slot; bytes32 value; }"
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn read_state_honest() {
        let leaf = [7u8; 32];
        let mut p = Pmmr::default();
        let uv = UpdatePublicValues::from_state_root(&mut p, 0, leaf);
        // leaf as both state root and simplified leaf (empty proof)
        assert_eq!(
            env::read_state(uv.batch_root, leaf, leaf, &[]).unwrap(),
            leaf
        );
    }

    #[test]
    fn read_state_wrong_commitment() {
        let leaf = [7u8; 32];
        assert!(env::read_state([8u8; 32], leaf, leaf, &[]).is_err());
    }

    #[test]
    fn read_state_tampered_leaf() {
        let sr = [7u8; 32];
        let mut p = Pmmr::default();
        let uv = UpdatePublicValues::from_state_root(&mut p, 0, sr);
        assert!(env::read_state(uv.batch_root, sr, [9u8; 32], &[]).is_err());
    }

    #[test]
    fn journal_docs_nonempty() {
        assert!(!journal::storage_solidity().is_empty());
    }
}
