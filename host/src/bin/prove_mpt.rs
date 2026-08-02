//! Fetch `eth_getProof` + run MPT guest (Milestone C).
//!
//! Fast path: `--execute-only` (local execute).
//! Real Groth16: `SP1_PROVER=network` + `NETWORK_PRIVATE_KEY` (SPN).
//!
//! Uses blocking JSON-RPC (not `alloy` / nested Tokio) to avoid runtime
//! conflicts with `sp1_sdk` blocking prover + `c-kzg` link conflicts.

use alloy_primitives::{hex, Address, B256, U256};
use alloy_rlp::Encodable;
use alloy_sol_types::SolType;
use clap::Parser;
use serde::Serialize;
use serde_json::{json, Value};
use sp1_sdk::{
    blocking::{ProveRequest, Prover, ProverClient},
    include_elf, Elf, HashableKey, ProvingKey, SP1Stdin,
};
use zk_coprocessor_lib::StorageProofPublicValues;

const ELF: Elf = include_elf!("mpt-guest");

#[derive(Parser, Debug)]
struct Args {
    /// Contract / account address
    #[arg(long)]
    address: String,
    /// Storage slot (decimal or 0x-hex)
    #[arg(long, default_value = "0")]
    slot: String,
    /// Block tag/number (`latest` or decimal)
    #[arg(long, default_value = "latest")]
    block: String,
    #[arg(long, env = "ETH_RPC_URL", default_value = "https://ethereum-rpc.publicnode.com")]
    rpc: String,
    #[arg(long)]
    out: Option<String>,
    /// Execute guest only (no Groth16)
    #[arg(long, default_value_t = false)]
    execute_only: bool,
    /// Negative test: flip one byte in the account proof before execute (must fail)
    #[arg(long, default_value_t = false)]
    tamper: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Fixture {
    vkey: String,
    public_values: String,
    proof: String,
    state_root: String,
    address: String,
    slot: String,
    value: String,
}

fn main() -> eyre::Result<()> {
    sp1_sdk::utils::setup_logger();
    let _ = dotenvy::dotenv();
    let args = Args::parse();

    let address: Address = args.address.parse()?;
    let slot = parse_b256(&args.slot)?;
    let block_tag = normalize_block_tag(&args.block);

    let (state_root, account_rlp, mut account_proof, storage_proof, storage_value) =
        fetch_mpt_witness(&args.rpc, address, slot, &block_tag)?;

    if args.tamper {
        let node = account_proof
            .last_mut()
            .ok_or_else(|| eyre::eyre!("cannot tamper: empty account proof"))?;
        let b = node.last_mut().ok_or_else(|| eyre::eyre!("cannot tamper: empty node"))?;
        *b ^= 0x01;
        eprintln!("tampered last byte of last accountProof node");
    }

    eprintln!(
        "witness ready stateRoot={} slot={} value={}",
        hex::encode(state_root),
        hex::encode(slot),
        hex::encode(storage_value)
    );

    let mut stdin = SP1Stdin::new();
    stdin.write(&state_root.0);
    stdin.write(&address.into_array());
    stdin.write(&slot.0);
    stdin.write(&account_rlp);
    stdin.write(&account_proof);
    stdin.write(&storage_proof);
    stdin.write(&storage_value.0);

    let client = ProverClient::from_env();
    let pk = client.setup(ELF).expect("setup");
    let vkey = pk.verifying_key().bytes32();

    if args.execute_only {
        let (public_values, report) = client.execute(ELF, stdin).run().expect("execute");
        let decoded =
            StorageProofPublicValues::abi_decode(public_values.as_slice(), true).expect("decode");
        eprintln!(
            "execute OK cycles={} value=0x{}",
            report.total_instruction_count(),
            hex::encode(decoded.value)
        );
        let fixture = Fixture {
            vkey: vkey.to_string(),
            public_values: format!("0x{}", hex::encode(public_values.as_slice())),
            proof: "0x".into(),
            state_root: format!("0x{}", hex::encode(state_root)),
            address: address.to_string(),
            slot: format!("0x{}", hex::encode(slot)),
            value: format!("0x{}", hex::encode(storage_value)),
        };
        emit(&fixture, args.out.as_deref())?;
        return Ok(());
    }

    eprintln!("proving groth16 mpt-guest vkey={vkey}");
    let proof = client
        .prove(&pk, stdin)
        .groth16()
        .run()
        .expect("groth16 prove failed");
    let bytes = proof.public_values.as_slice();
    let fixture = Fixture {
        vkey: vkey.to_string(),
        public_values: format!("0x{}", hex::encode(bytes)),
        proof: format!("0x{}", hex::encode(proof.bytes())),
        state_root: format!("0x{}", hex::encode(state_root)),
        address: address.to_string(),
        slot: format!("0x{}", hex::encode(slot)),
        value: format!("0x{}", hex::encode(storage_value)),
    };
    emit(&fixture, args.out.as_deref())?;
    Ok(())
}

fn emit(fixture: &Fixture, out: Option<&str>) -> eyre::Result<()> {
    let json = serde_json::to_string_pretty(fixture)?;
    if let Some(path) = out {
        std::fs::write(path, &json)?;
        eprintln!("wrote {path}");
    }
    println!("{json}");
    Ok(())
}

fn rpc_call(rpc: &str, method: &str, params: Value) -> eyre::Result<Value> {
    let client = reqwest::blocking::Client::new();
    let body = json!({
        "jsonrpc": "2.0",
        "id": 1,
        "method": method,
        "params": params,
    });
    let resp: Value = client.post(rpc).json(&body).send()?.json()?;
    if let Some(err) = resp.get("error") {
        eyre::bail!("{method} error: {err}");
    }
    resp.get("result")
        .cloned()
        .ok_or_else(|| eyre::eyre!("{method}: missing result"))
}

fn fetch_mpt_witness(
    rpc: &str,
    address: Address,
    slot: B256,
    block_tag: &str,
) -> eyre::Result<(B256, Vec<u8>, Vec<Vec<u8>>, Vec<Vec<u8>>, B256)> {
    let block = rpc_call(rpc, "eth_getBlockByNumber", json!([block_tag, false]))?;
    let state_root = parse_b256(
        block
            .get("stateRoot")
            .and_then(|v| v.as_str())
            .ok_or_else(|| eyre::eyre!("block missing stateRoot"))?,
    )?;

    let proof = rpc_call(
        rpc,
        "eth_getProof",
        json!([
            format!("{address}"),
            [format!("0x{}", hex::encode(slot))],
            block_tag
        ]),
    )?;

    let nonce = u64::from_str_radix(
        proof
            .get("nonce")
            .and_then(|v| v.as_str())
            .unwrap_or("0x0")
            .trim_start_matches("0x"),
        16,
    )?;
    let balance = U256::from_str_radix(
        proof
            .get("balance")
            .and_then(|v| v.as_str())
            .unwrap_or("0x0")
            .trim_start_matches("0x"),
        16,
    )?;
    let storage_hash = parse_b256(
        proof
            .get("storageHash")
            .and_then(|v| v.as_str())
            .ok_or_else(|| eyre::eyre!("missing storageHash"))?,
    )?;
    let code_hash = parse_b256(
        proof
            .get("codeHash")
            .and_then(|v| v.as_str())
            .ok_or_else(|| eyre::eyre!("missing codeHash"))?,
    )?;

    let account_rlp = encode_account_rlp(nonce, balance, storage_hash, code_hash);
    let account_proof = decode_hex_array(
        proof
            .get("accountProof")
            .ok_or_else(|| eyre::eyre!("missing accountProof"))?,
    )?;

    let storage_arr = proof
        .get("storageProof")
        .and_then(|v| v.as_array())
        .ok_or_else(|| eyre::eyre!("missing storageProof"))?;
    let sp = storage_arr
        .first()
        .ok_or_else(|| eyre::eyre!("empty storageProof"))?;
    let storage_proof = decode_hex_array(
        sp.get("proof")
            .ok_or_else(|| eyre::eyre!("missing storage proof nodes"))?,
    )?;
    let storage_value = {
        let raw = sp
            .get("value")
            .and_then(|v| v.as_str())
            .unwrap_or("0x0");
        let u = U256::from_str_radix(raw.trim_start_matches("0x"), 16)?;
        B256::from(u.to_be_bytes::<32>())
    };

    Ok((
        state_root,
        account_rlp,
        account_proof,
        storage_proof,
        storage_value,
    ))
}

fn encode_account_rlp(nonce: u64, balance: U256, storage_root: B256, code_hash: B256) -> Vec<u8> {
    let mut out = Vec::new();
    let encodable: [&dyn Encodable; 4] = [&nonce, &balance, &storage_root, &code_hash];
    alloy_rlp::encode_list::<_, dyn Encodable>(&encodable, &mut out);
    out
}

fn decode_hex_array(v: &Value) -> eyre::Result<Vec<Vec<u8>>> {
    let arr = v
        .as_array()
        .ok_or_else(|| eyre::eyre!("expected hex array"))?;
    arr.iter()
        .map(|item| {
            let s = item
                .as_str()
                .ok_or_else(|| eyre::eyre!("expected hex string"))?;
            Ok(hex::decode(s.trim_start_matches("0x"))?)
        })
        .collect()
}

fn parse_b256(s: &str) -> eyre::Result<B256> {
    if let Ok(n) = s.parse::<u64>() {
        return Ok(B256::from(U256::from(n).to_be_bytes::<32>()));
    }
    let h = s.trim_start_matches("0x");
    let bytes = hex::decode(h)?;
    eyre::ensure!(bytes.len() <= 32, "slot/hash too long");
    let mut out = [0u8; 32];
    out[32 - bytes.len()..].copy_from_slice(&bytes);
    Ok(B256::from(out))
}

fn normalize_block_tag(s: &str) -> String {
    if s == "latest" || s.starts_with("0x") {
        s.to_string()
    } else if let Ok(n) = s.parse::<u64>() {
        format!("0x{n:x}")
    } else {
        s.to_string()
    }
}
