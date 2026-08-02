//! Single-operator orchestrator node (Anvil / mock prove).
//!
//! Polls `ComputationRequested`, runs `prove-mock`, submits `fulfill`.
//! Groth16/network path is gated by `SP1_PROVER=network` + `spn-balance --min`.

use clap::Parser;
use serde_json::{json, Value};
use std::collections::HashSet;
use std::path::PathBuf;
use std::process::Command;
use std::thread;
use std::time::Duration;
use tracing::{info, warn};
use zk_orchestrator::{Job, JobStatus, Orchestrator};

/// keccak256("ComputationRequested(uint256,bytes32,uint64,uint64,address,address,uint256)")
const TOPIC0: &str = "0x5f1ef9c061edb490bde3d94e180f688eadfa43756f8b26a7d4f7bb51f4f52804";

#[derive(Parser, Debug)]
#[command(name = "orchestrator")]
struct Args {
    #[arg(long, env = "RPC_URL", default_value = "http://127.0.0.1:8545")]
    rpc: String,
    #[arg(long, env = "ROUTER")]
    router: String,
    #[arg(long, env = "FULFILLMENT")]
    fulfillment: String,
    #[arg(
        long,
        env = "PRIVATE_KEY",
        default_value = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
    )]
    private_key: String,
    #[arg(long, env = "ORCH_FLOOR_WEI", default_value_t = 0)]
    floor_wei: u128,
    #[arg(long, env = "ORCH_POLL_MS", default_value_t = 1000)]
    poll_ms: u64,
    /// Process at most N new jobs then exit (0 = forever).
    #[arg(long, default_value_t = 0)]
    max_jobs: u64,
    #[arg(long, env = "PROVE_BIN", default_value = "")]
    prove_bin: String,
    #[arg(long, default_value_t = false)]
    once: bool,
}

fn main() -> eyre::Result<()> {
    let _ = dotenvy::dotenv();
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();
    let args = Args::parse();

    if std::env::var("SP1_PROVER").unwrap_or_default() == "network" {
        // Only gate when explicitly requesting network prove path.
        let status = Command::new("bash")
            .arg("-lc")
            .arg("test -x ./scripts/preflight-spn.sh && ./scripts/preflight-spn.sh")
            .current_dir(repo_root())
            .status();
        match status {
            Ok(s) if s.success() => {}
            _ => {
                eyre::bail!("SP1_PROVER=network but SPN preflight failed (BLOCKED_UNFUNDED)");
            }
        }
    }
    // Default prove path is prove-mock (ignore SP1_PROVER=cpu/cuda for this binary).

    let prove_bin = if args.prove_bin.is_empty() {
        repo_root().join("target/release/prove-mock")
    } else {
        PathBuf::from(&args.prove_bin)
    };
    eyre::ensure!(prove_bin.exists(), "missing prove binary at {}", prove_bin.display());

    let mut orch = Orchestrator::new(args.floor_wei);
    let mut seen: HashSet<u64> = HashSet::new();
    let mut done: u64 = 0;
    let mut from_block = "0x0".to_string();

    info!(router = %args.router, fulfillment = %args.fulfillment, "orchestrator starting");

    loop {
        let logs = get_logs(&args.rpc, &args.router, &from_block)?;
        for log in logs {
            let Some(req) = parse_request_log(&log) else {
                continue;
            };
            if !seen.insert(req.id) {
                continue;
            }
            if let Some(bn) = log.get("blockNumber").and_then(|v| v.as_str()) {
                from_block = bn.to_string();
            }
            info!(request_id = req.id, a = req.a, b = req.b, bounty = req.bounty, "job");

            let job = Job {
                request_id: req.id,
                program_id: req.vkey,
                elf_hash: req.vkey,
                expected_elf_hash: req.vkey,
                status: JobStatus::Queued,
                fail_reason: None,
                bounty_wei: req.bounty,
                floor_wei: args.floor_wei,
            };
            if let Err(e) = orch.enqueue(job) {
                warn!(error = %e, "enqueue skipped");
                continue;
            }
            orch.transition(req.id, JobStatus::Proving)?;

            match prove_and_fulfill(&args, &prove_bin, &req) {
                Ok(()) => {
                    orch.transition(req.id, JobStatus::Submitting)?;
                    orch.transition(req.id, JobStatus::Confirmed)?;
                    info!(request_id = req.id, "confirmed");
                    done += 1;
                }
                Err(e) => {
                    warn!(request_id = req.id, error = %e, "fulfill failed");
                    let _ = orch.fail(req.id, e.to_string());
                }
            }

            if args.max_jobs > 0 && done >= args.max_jobs {
                info!(done, "max_jobs reached");
                return Ok(());
            }
        }

        if args.once {
            return Ok(());
        }
        thread::sleep(Duration::from_millis(args.poll_ms));
    }
}

struct ParsedReq {
    id: u64,
    vkey: [u8; 32],
    a: u64,
    b: u64,
    bounty: u128,
}

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn rpc(rpc_url: &str, method: &str, params: Value) -> eyre::Result<Value> {
    let client = reqwest::blocking::Client::new();
    let body = json!({"jsonrpc":"2.0","id":1,"method":method,"params":params});
    let resp: Value = client.post(rpc_url).json(&body).send()?.json()?;
    if let Some(err) = resp.get("error") {
        eyre::bail!("{method}: {err}");
    }
    Ok(resp["result"].clone())
}

fn get_logs(rpc_url: &str, router: &str, from_block: &str) -> eyre::Result<Vec<Value>> {
    // Recompute topic0 dynamically via cast if hardcoded mismatches deployments.
    let topic0 = event_topic0()?;
    let result = rpc(
        rpc_url,
        "eth_getLogs",
        json!([{
            "fromBlock": from_block,
            "toBlock": "latest",
            "address": router,
            "topics": [topic0]
        }]),
    )?;
    Ok(result.as_array().cloned().unwrap_or_default())
}

fn event_topic0() -> eyre::Result<String> {
    // Prefer cast for correctness across toolchain versions.
    let out = Command::new("cast")
        .args([
            "sig-event",
            "ComputationRequested(uint256,bytes32,uint64,uint64,address,address,uint256)",
        ])
        .output()?;
    if out.status.success() {
        let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
        if s.starts_with("0x") {
            return Ok(s);
        }
    }
    Ok(TOPIC0.to_string())
}

fn parse_request_log(log: &Value) -> Option<ParsedReq> {
    let topics = log.get("topics")?.as_array()?;
    let id = u64::from_str_radix(topics.get(1)?.as_str()?.trim_start_matches("0x"), 16).ok()?;
    let vkey_hex = topics.get(2)?.as_str()?.trim_start_matches("0x");
    let mut vkey = [0u8; 32];
    let vb = hex::decode(vkey_hex).ok()?;
    if vb.len() != 32 {
        return None;
    }
    vkey.copy_from_slice(&vb);
    let data = log.get("data")?.as_str()?.trim_start_matches("0x");
    let raw = hex::decode(data).ok()?;
    // abi: a, b, callback, requester, bounty — each 32 bytes
    if raw.len() < 160 {
        return None;
    }
    let a = u64::from_be_bytes(raw[24..32].try_into().ok()?);
    let b = u64::from_be_bytes(raw[56..64].try_into().ok()?);
    let bounty = {
        let mut buf = [0u8; 16];
        buf.copy_from_slice(&raw[144..160]);
        u128::from_be_bytes(buf)
    };
    Some(ParsedReq {
        id,
        vkey,
        a,
        b,
        bounty,
    })
}

fn prove_and_fulfill(args: &Args, prove_bin: &PathBuf, req: &ParsedReq) -> eyre::Result<()> {
    let vkey = format!("0x{}", hex::encode(req.vkey));
    let out = Command::new(prove_bin)
        .args([
            "--a",
            &req.a.to_string(),
            "--b",
            &req.b.to_string(),
            "--vkey",
            &vkey,
        ])
        .output()?;
    eyre::ensure!(out.status.success(), "prove-mock failed: {}", String::from_utf8_lossy(&out.stderr));
    let proof_json: Value = serde_json::from_slice(&out.stdout)?;
    let public_values = proof_json["publicValues"].as_str().ok_or_else(|| eyre::eyre!("pv"))?;
    let proof = proof_json["proof"].as_str().ok_or_else(|| eyre::eyre!("proof"))?;

    let send = Command::new("cast")
        .args([
            "send",
            &args.fulfillment,
            "fulfill(uint256,bytes,bytes)",
            &req.id.to_string(),
            public_values,
            proof,
            "--rpc-url",
            &args.rpc,
            "--private-key",
            &args.private_key,
        ])
        .output()?;
    if !send.status.success() {
        eyre::bail!(
            "cast send fulfill failed: {}",
            String::from_utf8_lossy(&send.stderr)
        );
    }
    Ok(())
}
