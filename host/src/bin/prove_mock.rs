//! Phase 0 helper: emit mock proof + public values JSON for cast/forge E2E.

use alloy_sol_types::SolType;
use clap::Parser;
use sha3::{Digest, Keccak256};
use zk_coprocessor_lib::{add_wrapping, PublicValuesStruct};

#[derive(Parser, Debug)]
struct Args {
    #[arg(long)]
    a: u64,
    #[arg(long)]
    b: u64,
    /// 32-byte program vkey hex (0x-prefixed)
    #[arg(long)]
    vkey: String,
}

fn main() {
    let args = Args::parse();
    let sum = add_wrapping(args.a, args.b);
    let pv = PublicValuesStruct {
        a: args.a,
        b: args.b,
        sum,
    };
    let public_values = PublicValuesStruct::abi_encode(&pv);

    let vkey_hex = args.vkey.trim_start_matches("0x");
    let vkey = hex::decode(vkey_hex).expect("vkey hex");
    assert_eq!(vkey.len(), 32, "vkey must be 32 bytes");

    let mut hasher = Keccak256::new();
    hasher.update(&public_values);
    hasher.update(&vkey);
    let digest = hasher.finalize();

    let mut proof = vec![0x4du8, 0x4f, 0x43, 0x4b]; // MOCK
    proof.extend_from_slice(&digest);

    let out = serde_json::json!({
        "a": args.a,
        "b": args.b,
        "sum": sum,
        "publicValues": format!("0x{}", hex::encode(&public_values)),
        "proof": format!("0x{}", hex::encode(&proof)),
        "vkey": format!("0x{}", hex::encode(&vkey)),
    });
    println!("{out}");
}
