# ZK-Coprocessor

Automated ZK-Coprocessor framework: trustless off-chain compute and historical chain data for smart contracts, with ZK-verified callbacks on-chain (“AWS Lambda of Web3”).

## Quick start (Phase 0)

```bash
# Foundry
curl -L https://foundry.paradigm.xyz | bash && foundryup

# Contracts
cd contracts && git clone --depth 1 https://github.com/foundry-rs/forge-std lib/forge-std
forge test -vv

# Rust workspace
cargo test --workspace

# Anvil E2E (request → mock prove → callback)
./scripts/e2e-anvil.sh
```

See [`scripts/README-e2e.md`](./scripts/README-e2e.md) and [`NOTES/PHASE0_EVIDENCE.md`](./NOTES/PHASE0_EVIDENCE.md).

## Layout

| Path | Role |
|------|------|
| `contracts/` | Foundry: gateway, registry, header commitment, prover network |
| `guest/` | SP1 RISC-V add-two-numbers program (`cargo prove` / sp1 toolchain) |
| `host/` | `prove-mock` + E2E helpers |
| `lib/` | Shared journal ABI |
| `crates/header-commitment` | Axiom-class PMMR / simplified MPT helpers |
| `crates/orchestrator` | Job FSM + ETH floor economics |
| `sdk/guest` | `env::read_state` / journal codegen docs |
| `sdk/ts` | TypeScript journal decode |
| `cli/` | `create-zk-coprocessor` scaffold + Anvil deploy + ELF CAS |
| `crates/orchestrator` | Job FSM + `orchestrator` node binary |
| `guest-mpt/` | In-guest alloy-trie MPT verification |

## DevEx (v1)

```bash
cargo run -p create-zk-coprocessor -- new my-app --template compute
cargo run -p create-zk-coprocessor -- new my-state --template state
# with Anvil running:
cargo run -p create-zk-coprocessor -- deploy --network anvil
# writes deployments/anvil.json
HASH=$(cargo run -q -p create-zk-coprocessor -- store-elf --elf path/to/elf)
# optional: register on ProgramRegistry
# cargo run -p create-zk-coprocessor -- register --elf-hash $HASH --vkey 0x.. --registry $REGISTRY
./scripts/e2e-orchestrator-soak.sh
```

Install CLI: `cargo install --path cli` (or `npx` via root `package.json` bin when `cargo` is on PATH).
TS journal helpers: [`sdk/ts`](./sdk/ts).

- **[`End_Goal`](./End_Goal)** — final product (authoritative)
- [`NOTES/LOCKED_DECISIONS.md`](./NOTES/LOCKED_DECISIONS.md) — SP1, vendor gateway, Axiom-class PMMR, ETH-first
- [`SDD`](./SDD) / [`PHASES`](./PHASES) — architecture & build order
- [`NOTES/PHASE_EVIDENCE.md`](./NOTES/PHASE_EVIDENCE.md) — validation evidence

**Verifier:** production / `PROVE_MODE=sp1` uses Succinct `SP1VerifierGateway` + Groth16 v6.1.0. Default local harness uses `MockSP1Verifier` (`PROVE_MODE=mock`). See [`NOTES/MILESTONE_AB_SP1.md`](./NOTES/MILESTONE_AB_SP1.md).

