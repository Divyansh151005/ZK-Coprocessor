//! Encode HeaderCommitment update public values (mock / Anvil path).

use alloy_sol_types::SolType;
use clap::Parser;
use header_commitment::{Pmmr, UpdatePublicValues};
use zk_coprocessor_lib::HeaderUpdatePublicValues;

#[derive(Parser, Debug)]
struct Args {
    /// Trusted state root (0x-hex) to embed as padded 1024-leaf batch.
    #[arg(long)]
    state_root: String,
    #[arg(long, default_value_t = 0)]
    start_block: u64,
}

fn main() -> eyre::Result<()> {
    let args = Args::parse();
    let sr = parse_b256(&args.state_root)?;
    let mut pmmr = Pmmr::default();
    let uv = UpdatePublicValues::from_state_root(&mut pmmr, args.start_block, sr);
    eyre::ensure!(
        header_commitment::state_root_matches_commitment(uv.batch_root, sr),
        "internal: batch root mismatch"
    );
    let sol = HeaderUpdatePublicValues {
        startBlock: uv.start_block,
        batchRoot: uv.batch_root.into(),
        prevSnapshotId: uv.prev_snapshot_id.into(),
        newSnapshotId: uv.new_snapshot_id.into(),
    };
    let encoded = HeaderUpdatePublicValues::abi_encode(&sol);
    println!("0x{}", hex::encode(encoded));
    eprintln!(
        "batchRoot=0x{} newSnapshot=0x{}",
        hex::encode(uv.batch_root),
        hex::encode(uv.new_snapshot_id)
    );
    Ok(())
}

fn parse_b256(s: &str) -> eyre::Result<[u8; 32]> {
    let h = s.trim_start_matches("0x");
    let bytes = hex::decode(h)?;
    eyre::ensure!(bytes.len() == 32, "state root must be 32 bytes");
    let mut out = [0u8; 32];
    out.copy_from_slice(&bytes);
    Ok(out)
}
