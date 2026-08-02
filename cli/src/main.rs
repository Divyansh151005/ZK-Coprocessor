//! `create-zk-coprocessor` CLI (Phase 6 / End_Goal A DevEx).

use clap::{Parser, Subcommand};
use sha2::{Digest, Sha256};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Parser, Debug)]
#[command(name = "create-zk-coprocessor", about = "Scaffold and deploy a ZK coprocessor app")]
struct Cli {
    #[command(subcommand)]
    cmd: Commands,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// Create a new project scaffold
    New {
        name: String,
        #[arg(long, default_value = "compute")]
        template: String,
        #[arg(long)]
        path: Option<PathBuf>,
    },
    /// Deploy gateway stack on Anvil and write deployments/<network>.json
    Deploy {
        #[arg(long, default_value = "anvil")]
        network: String,
        #[arg(long, env = "RPC_URL", default_value = "http://127.0.0.1:8545")]
        rpc: String,
        #[arg(
            long,
            env = "PRIVATE_KEY",
            default_value = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
        )]
        private_key: String,
        /// Framework contracts root (default: ../contracts from CWD or ZK_COPROCESSOR_ROOT)
        #[arg(long)]
        contracts: Option<PathBuf>,
    },
    /// Store an ELF under content-addressed artifacts/elf/<sha256>
    StoreElf {
        #[arg(long)]
        elf: PathBuf,
        #[arg(long, default_value = "artifacts/elf")]
        out_dir: PathBuf,
    },
    /// Register an ELF hash + vkey on ProgramRegistry (Anvil / local)
    Register {
        #[arg(long)]
        elf_hash: String,
        #[arg(long)]
        vkey: String,
        #[arg(long)]
        registry: String,
        #[arg(long)]
        content_uri: Option<String>,
        #[arg(long, env = "RPC_URL", default_value = "http://127.0.0.1:8545")]
        rpc: String,
        #[arg(
            long,
            env = "PRIVATE_KEY",
            default_value = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
        )]
        private_key: String,
    },
}

fn main() {
    let cli = Cli::parse();
    match cli.cmd {
        Commands::New {
            name,
            template,
            path,
        } => {
            let root = path.unwrap_or_else(|| PathBuf::from(&name));
            scaffold(&root, &name, &template).expect("scaffold failed");
            println!("created {} (template={template})", root.display());
            println!("folders: app/ (Rust guest) contracts/ (Solidity consumer)");
        }
        Commands::Deploy {
            network,
            rpc,
            private_key,
            contracts,
        } => {
            deploy_anvil(&network, &rpc, &private_key, contracts.as_deref())
                .expect("deploy failed");
        }
        Commands::StoreElf { elf, out_dir } => {
            let hash = store_elf(&elf, &out_dir).expect("store-elf failed");
            println!("0x{hash}");
            println!("path={}/{hash}", out_dir.display());
        }
        Commands::Register {
            elf_hash,
            vkey,
            registry,
            content_uri,
            rpc,
            private_key,
        } => {
            register_program(&elf_hash, &vkey, &registry, content_uri.as_deref(), &rpc, &private_key)
                .expect("register failed");
        }
    }
}

fn framework_contracts(explicit: Option<&Path>) -> PathBuf {
    if let Some(p) = explicit {
        return p.to_path_buf();
    }
    if let Ok(root) = std::env::var("ZK_COPROCESSOR_ROOT") {
        return PathBuf::from(root).join("contracts");
    }
    // Prefer sibling contracts/ when run from monorepo root.
    let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    if cwd.join("contracts").join("foundry.toml").exists() {
        return cwd.join("contracts");
    }
    if cwd.join("foundry.toml").exists() {
        return cwd;
    }
    cwd.join("../contracts")
}

fn deploy_anvil(
    network: &str,
    rpc: &str,
    pk: &str,
    contracts: Option<&Path>,
) -> Result<(), Box<dyn std::error::Error>> {
    let contracts = framework_contracts(contracts);
    let out = Command::new("forge")
        .current_dir(&contracts)
        .args([
            "script",
            "script/DeployLocal.s.sol:DeployLocal",
            "--rpc-url",
            rpc,
            "--private-key",
            pk,
            "--broadcast",
            "-vv",
        ])
        .output()?;
    let stdout = String::from_utf8_lossy(&out.stdout);
    let stderr = String::from_utf8_lossy(&out.stderr);
    let combined = format!("{stdout}\n{stderr}");
    if !out.status.success() {
        return Err(format!("forge script failed:\n{combined}").into());
    }
    let book = serde_json::json!({
        "network": network,
        "MockSP1Verifier": grab(&combined, "MockSP1Verifier"),
        "MinimalRequestRouter": grab(&combined, "MinimalRequestRouter"),
        "MinimalFulfillment": grab(&combined, "MinimalFulfillment"),
        "MockConsumer": grab(&combined, "MockConsumer"),
        "programRegistry": null,
        "requestRouter": grab(&combined, "MinimalRequestRouter"),
        "fulfillment": grab(&combined, "MinimalFulfillment"),
        "sp1VerifierGateway": "USE_VENDOR_OR_MOCK",
        "note": "Anvil mock stack from DeployLocal.s.sol"
    });
    let out_dir = PathBuf::from("deployments");
    fs::create_dir_all(&out_dir)?;
    let path = out_dir.join(format!("{network}.json"));
    fs::write(&path, serde_json::to_string_pretty(&book)?)?;
    println!("wrote {}", path.display());
    println!("{book}");
    Ok(())
}

fn grab(hay: &str, label: &str) -> String {
    for line in hay.lines() {
        if let Some(idx) = line.find(label) {
            let rest = &line[idx + label.len()..];
            if let Some(addr) = rest.split_whitespace().find(|t| t.starts_with("0x")) {
                return addr.to_string();
            }
        }
    }
    "0x".into()
}

fn store_elf(elf: &Path, out_dir: &Path) -> Result<String, Box<dyn std::error::Error>> {
    let bytes = fs::read(elf)?;
    let mut hasher = Sha256::new();
    hasher.update(&bytes);
    let hash = hex::encode(hasher.finalize());
    fs::create_dir_all(out_dir)?;
    let dest = out_dir.join(&hash);
    fs::write(&dest, bytes)?;
    Ok(hash)
}

fn normalize_bytes32(s: &str) -> Result<String, Box<dyn std::error::Error>> {
    let h = s.trim().trim_start_matches("0x");
    if h.len() > 64 || !h.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err(format!("invalid bytes32: {s}").into());
    }
    Ok(format!("0x{:0>64}", h))
}

fn register_program(
    elf_hash: &str,
    vkey: &str,
    registry: &str,
    content_uri: Option<&str>,
    rpc: &str,
    pk: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    let elf = normalize_bytes32(elf_hash)?;
    let vk = normalize_bytes32(vkey)?;
    let uri = content_uri
        .map(str::to_string)
        .unwrap_or_else(|| format!("cas://elf/{}", elf.trim_start_matches("0x")));
    let out = Command::new("cast")
        .args([
            "send",
            registry,
            "register(bytes32,bytes32,string)",
            &elf,
            &vk,
            &uri,
            "--rpc-url",
            rpc,
            "--private-key",
            pk,
        ])
        .output()?;
    let combined = format!(
        "{}\n{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    );
    if !out.status.success() {
        return Err(format!("cast register failed:\n{combined}").into());
    }
    println!("registered elf={elf} vkey={vk} uri={uri}");
    println!("{combined}");
    Ok(())
}

fn scaffold(root: &PathBuf, name: &str, template: &str) -> std::io::Result<()> {
    fs::create_dir_all(root.join("app/src"))?;
    fs::create_dir_all(root.join("contracts/src"))?;
    let guest = match template {
        "state" | "state-reading" => STATE_GUEST,
        _ => COMPUTE_GUEST,
    };
    fs::write(root.join("app/src/main.rs"), guest)?;
    fs::write(
        root.join("app/Cargo.toml"),
        r#"[package]
name = "app-guest"
version = "0.1.0"
edition = "2021"

[dependencies]
# Pin to framework versions when linking the monorepo.
# sp1-zkvm = "6.3.1"
# zk-coprocessor-lib = { path = "../../lib" }
"#,
    )?;
    fs::write(root.join("contracts/src/Consumer.sol"), CONSUMER_SOL)?;
    fs::write(
        root.join("contracts/foundry.toml"),
        r#"[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc_version = "0.8.20"
"#,
    )?;
    fs::write(
        root.join("README.md"),
        format!(
            r#"# {name}

Generated by `create-zk-coprocessor` (template={template}).

## Workflow

1. Implement guest logic in `app/` (see comments for SP1 entrypoint).
2. Keep callback consumer in `contracts/src/Consumer.sol` (`forge build` in `contracts/`).
3. From the ZK-Coprocessor monorepo root:
   - `cargo run -p create-zk-coprocessor -- deploy --network anvil`
   - `cargo run -p create-zk-coprocessor -- store-elf --elf <path-to-elf>`
   - `cargo run -p create-zk-coprocessor -- register --elf-hash <sha256> --vkey <bytes32> --registry <addr>`
   - Start `orchestrator` against printed addresses

Unfunded prove path uses `prove-mock`. SPN Groth16 requires `./scripts/preflight-spn.sh`.
"#
        ),
    )?;
    Ok(())
}

const COMPUTE_GUEST: &str = r#"//! Compute-only guest (add two numbers).
//! Wire with: sp1_zkvm + zk_coprocessor_lib::PublicValuesStruct
#![allow(dead_code)]

pub fn add_wrapping(a: u64, b: u64) -> u64 {
    a.wrapping_add(b)
}

fn main() {
    // SP1 guest entry (enable when building with cargo prove):
    // sp1_zkvm::entrypoint!(main);
    // let a = sp1_zkvm::io::read::<u64>();
    // let b = sp1_zkvm::io::read::<u64>();
    // let sum = add_wrapping(a, b);
    // commit PublicValuesStruct { a, b, sum }
}
"#;

const STATE_GUEST: &str = r#"//! State-reading guest template.
//! Production path: guest-mpt (alloy-trie) + HeaderCommitment binding.
#![allow(dead_code)]

/// Documented End_Goal API — host/sdk verify commitment then MPT.
pub fn read_state_doc() -> &'static str {
    "zk_coprocessor_sdk::env::read_state(committed_batch_root, state_root, leaf, proof_nodes)"
}

fn main() {
    // Prefer framework guest-mpt ELF for real eth_getProof verification.
    let _ = read_state_doc();
}
"#;

const CONSUMER_SOL: &str = r#"// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ICoprocessorConsumer {
    function receiveCoprocessorResult(bytes calldata journal) external;
}

contract Consumer is ICoprocessorConsumer {
    bytes public lastJournal;
    function receiveCoprocessorResult(bytes calldata journal) external override {
        lastJournal = journal;
    }
}
"#;

#[cfg(test)]
mod tests {
    use super::*;
    use std::env::temp_dir;

    #[test]
    fn scaffolds_compute_and_state() {
        for tpl in ["compute", "state"] {
            let dir = temp_dir().join(format!("zkc-scaffold-{}-{}", tpl, std::process::id()));
            let _ = fs::remove_dir_all(&dir);
            scaffold(&dir, "demo", tpl).unwrap();
            assert!(dir.join("app/src/main.rs").exists());
            assert!(dir.join("contracts/src/Consumer.sol").exists());
            assert!(dir.join("app/Cargo.toml").exists());
            assert!(dir.join("contracts/foundry.toml").exists());
            let _ = fs::remove_dir_all(&dir);
        }
    }

    #[test]
    fn normalize_bytes32_pads() {
        assert_eq!(
            normalize_bytes32("0x0a01").unwrap(),
            "0x0000000000000000000000000000000000000000000000000000000000000a01"
        );
    }

    #[test]
    fn store_elf_hashes() {
        let dir = temp_dir().join(format!("zkc-elf-{}", std::process::id()));
        let elf = dir.join("in.bin");
        fs::create_dir_all(&dir).unwrap();
        fs::write(&elf, b"hello-elf").unwrap();
        let out = dir.join("cas");
        let h = store_elf(&elf, &out).unwrap();
        assert_eq!(h.len(), 64);
        assert!(out.join(&h).exists());
        let _ = fs::remove_dir_all(&dir);
    }
}
