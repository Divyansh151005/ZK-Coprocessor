//! Phase 0 SP1 guest: read two u64s, commit abi-encoded (a, b, sum).

#![no_main]
sp1_zkvm::entrypoint!(main);

use alloy_sol_types::SolType;
use zk_coprocessor_lib::{add_wrapping, PublicValuesStruct};

pub fn main() {
    let a = sp1_zkvm::io::read::<u64>();
    let b = sp1_zkvm::io::read::<u64>();
    let sum = add_wrapping(a, b);
    let bytes = PublicValuesStruct::abi_encode(&PublicValuesStruct { a, b, sum });
    sp1_zkvm::io::commit_slice(&bytes);
}
