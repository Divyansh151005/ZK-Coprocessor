//! Guest SDK surface matching End_Goal DX (`env::read` / `commit` / `read_state`).

use header_commitment::verify_storage_proof_simplified;

/// Host-side mirror of guest env helpers for unit tests and codegen docs.
pub mod env {
    use super::*;

    pub fn read_u64_pair(a: u64, b: u64) -> (u64, u64) {
        (a, b)
    }

    pub fn commit_sum(a: u64, b: u64) -> u64 {
        a.wrapping_add(b)
    }

    /// Phase 2/3: verify storage slot against committed state root (simplified MPT).
    pub fn read_state(
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
}

/// Journal ABI codegen helper: document Solidity struct <-> Rust field order.
pub mod journal {
    pub const PHASE0_FIELDS: &[&str] = &["a", "b", "sum"];
    pub const PHASE1_FIELDS: &[&str] = &["requestId", "a", "b", "sum"];

    pub fn phase0_solidity() -> &'static str {
        "struct PublicValues { uint64 a; uint64 b; uint64 sum; }"
    }

    pub fn phase1_solidity() -> &'static str {
        "struct PublicValuesV1 { uint256 requestId; uint64 a; uint64 b; uint64 sum; }"
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn read_state_honest() {
        let leaf = [7u8; 32];
        assert_eq!(env::read_state(leaf, leaf, &[]).unwrap(), leaf);
    }

    #[test]
    fn read_state_tampered() {
        let leaf = [7u8; 32];
        assert!(env::read_state([8u8; 32], leaf, &[]).is_err());
    }

    #[test]
    fn journal_docs_nonempty() {
        assert!(journal::phase0_solidity().contains("sum"));
        assert!(journal::phase1_solidity().contains("requestId"));
    }
}
