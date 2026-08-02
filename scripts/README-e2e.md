# Phase 0 / Anvil E2E

## Prerequisites

- Foundry (`forge`, `anvil`, `cast`)
- Rust (`cargo`)
- `jq`
- For **real Groth16**: `cargo-prove` / succinct toolchain, Docker ≥16GB RAM **or** Succinct Prover Network credentials

## Journal ABI (Phase 0 v0)

```solidity
struct PublicValues { uint64 a; uint64 b; uint64 sum; } // abi.encode
```

Overflow: wrapping add (matches Rust `wrapping_add`).

## Mock vs real verifier

| Mode | `PROVE_MODE` | Verifier | Prove binary |
|------|--------------|----------|--------------|
| Simulation (default) | `mock` | `MockSP1Verifier` | `prove-mock` |
| Real SP1 (Milestone B) | `sp1` | `SP1VerifierGateway` + Groth16 v6.1.0 | `prove-groth16` |

```bash
# Simulation
./scripts/e2e-anvil.sh

# Real gateway + Groth16
PROVE_MODE=sp1 ./scripts/e2e-anvil.sh
```

SPN: `SP1_PROVER=network` and `NETWORK_PRIVATE_KEY`.  
Program vkey: `./target/release/vkey` after guest ELF build.

## Commands

```bash
cd contracts && forge test -vv
cargo test --workspace
chmod +x scripts/e2e-anvil.sh && ./scripts/e2e-anvil.sh
```

## Environment

| Var | Default |
|-----|---------|
| `RPC_URL` | `http://127.0.0.1:8545` |
| `PRIVATE_KEY` | Anvil account #0 |
| `A` / `B` | `2` / `3` |
| `PROVE_MODE` | `mock` |
| `PROGRAM_VKEY` | mock mode only |
| `FIXTURE` | `contracts/src/fixtures/groth16-add.json` |
