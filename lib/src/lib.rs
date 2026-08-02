//! Shared journal ABIs for ZK-Coprocessor guests.

use alloy_sol_types::sol;

sol! {
    /// Phase 0 public values / journal ABI (v0).
    struct PublicValuesStruct {
        uint64 a;
        uint64 b;
        uint64 sum;
    }

    /// Milestone C / Phase 2 storage proof journal.
    struct StorageProofPublicValues {
        bytes32 stateRoot;
        address account;
        bytes32 slot;
        bytes32 value;
    }
}

/// Compute sum with wrapping overflow (explicit Phase 0 policy).
pub fn add_wrapping(a: u64, b: u64) -> u64 {
    a.wrapping_add(b)
}

#[cfg(test)]
mod tests {
    use super::*;
    use alloy_sol_types::SolType;

    #[test]
    fn add_basic() {
        assert_eq!(add_wrapping(2, 3), 5);
    }

    #[test]
    fn add_wrapping_overflow() {
        assert_eq!(add_wrapping(u64::MAX, 1), 0);
    }

    #[test]
    fn abi_roundtrip() {
        let pv = PublicValuesStruct {
            a: 7,
            b: 11,
            sum: 18,
        };
        let encoded = PublicValuesStruct::abi_encode(&pv);
        let decoded = PublicValuesStruct::abi_decode(&encoded, true).unwrap();
        assert_eq!(decoded.a, 7);
        assert_eq!(decoded.b, 11);
        assert_eq!(decoded.sum, 18);
    }

    #[test]
    fn storage_proof_abi_roundtrip() {
        let pv = StorageProofPublicValues {
            stateRoot: [1u8; 32].into(),
            account: [2u8; 20].into(),
            slot: [3u8; 32].into(),
            value: [4u8; 32].into(),
        };
        let encoded = StorageProofPublicValues::abi_encode(&pv);
        let decoded = StorageProofPublicValues::abi_decode(&encoded, true).unwrap();
        assert_eq!(decoded.stateRoot, pv.stateRoot);
        assert_eq!(decoded.account, pv.account);
        assert_eq!(decoded.slot, pv.slot);
        assert_eq!(decoded.value, pv.value);
    }
}
