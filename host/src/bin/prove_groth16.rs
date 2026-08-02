//! Generate a Groth16 proof for the add-guest program (Milestone A/B).
//!
//! Requires Docker (≥16GB RAM) for local wrap, or:
//!   SP1_PROVER=network NETWORK_PRIVATE_KEY=... (Succinct Prover Network)

use alloy_sol_types::SolType;
use clap::Parser;
use serde::Serialize;
use sp1_sdk::{
    blocking::{ProveRequest, Prover, ProverClient},
    include_elf, Elf, HashableKey, ProvingKey, SP1Stdin,
};
use zk_coprocessor_lib::PublicValuesStruct;

const ELF: Elf = include_elf!("add-guest");

#[derive(Parser, Debug)]
struct Args {
    #[arg(long)]
    a: u64,
    #[arg(long)]
    b: u64,
    /// Write fixture JSON to this path (optional).
    #[arg(long)]
    out: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Fixture {
    a: u64,
    b: u64,
    sum: u64,
    vkey: String,
    public_values: String,
    proof: String,
}

fn main() {
    sp1_sdk::utils::setup_logger();
    let _ = dotenvy::dotenv();
    let args = Args::parse();

    let client = ProverClient::from_env();
    let pk = client.setup(ELF).expect("setup ELF");
    let vkey = pk.verifying_key().bytes32();

    let mut stdin = SP1Stdin::new();
    stdin.write(&args.a);
    stdin.write(&args.b);

    eprintln!("proving groth16 a={} b={} vkey={vkey}", args.a, args.b);
    let proof = client
        .prove(&pk, stdin)
        .groth16()
        .run()
        .expect("groth16 prove failed");

    let bytes = proof.public_values.as_slice();
    let decoded = PublicValuesStruct::abi_decode(bytes, true).expect("decode public values");
    let fixture = Fixture {
        a: decoded.a,
        b: decoded.b,
        sum: decoded.sum,
        vkey: vkey.to_string(),
        public_values: format!("0x{}", hex::encode(bytes)),
        proof: format!("0x{}", hex::encode(proof.bytes())),
    };

    let json = serde_json::to_string_pretty(&fixture).unwrap();
    if let Some(path) = args.out {
        std::fs::write(&path, &json).expect("write fixture");
        eprintln!("wrote {path}");
    }
    println!("{json}");
}
