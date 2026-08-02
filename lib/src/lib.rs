//! Shared journal ABI for Phase 0 add-two-numbers guest.
//!
//! Layout (Solidity `abi.encode`):
//!   `struct PublicValues { uint64 a; uint64 b; uint64 sum; }`
//!
//! Overflow policy: wrapping add (`wrapping_add`). Documented for Phase 0.

use alloy_sol_types::sol;

sol! {
    /// Phase 0 public values / journal ABI (v0).
    /// Phase 1 will extend with `requestId` binding.
    struct PublicValuesStruct {
        uint64 a;
        uint64 b;
        uint64 sum;
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
}
