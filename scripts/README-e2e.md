# Phase 0 / Anvil E2E

## Prerequisites

- Foundry (`forge`, `anvil`, `cast`) — install via https://book.getfoundry.sh/getting-started/installation
- Rust (`cargo`)
- `jq`
- Optional for **real Groth16**: SP1 toolchain (`sp1up`), Docker, ≥16GB RAM — see [Succinct hardware docs](https://docs.succinct.xyz/docs/sp1/getting-started/hardware-requirements)

## Journal ABI (Phase 0 v0)

Solidity / guest public values:

```solidity
struct PublicValues { uint64 a; uint64 b; uint64 sum; } // abi.encode
```

Overflow: wrapping add (matches Rust `wrapping_add`).

## Mock vs real verifier

Phase 0 local E2E uses `MockSP1Verifier` (magic `MOCK` + keccak binding). It implements the same `ISP1Verifier.verifyProof` surface as Succinct’s gateway so fulfillment code is production-shaped. Swap the verifier address for `SP1VerifierGateway` + Groth16 proofs in Phase 4.

## Commands

```bash
# Unit / negative tests
cd contracts && forge install foundry-rs/forge-std --no-commit && forge test -vv

# Lib unit tests
cargo test -p zk-coprocessor-lib

# Full Anvil lifecycle
chmod +x scripts/e2e-anvil.sh
./scripts/e2e-anvil.sh
```

## Environment

| Var | Default |
|-----|---------|
| `RPC_URL` | `http://127.0.0.1:8545` |
| `PRIVATE_KEY` | Anvil account #0 |
| `A` / `B` | `2` / `3` |
| `PROGRAM_VKEY` | `0x...a11ce` |
