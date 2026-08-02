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
| `cli/` | `create-zk-coprocessor` scaffold |

## Source of truth

- **[`End_Goal`](./End_Goal)** — final product (authoritative)
- [`NOTES/LOCKED_DECISIONS.md`](./NOTES/LOCKED_DECISIONS.md) — SP1, vendor gateway, Axiom-class PMMR, ETH-first
- [`SDD`](./SDD) / [`PHASES`](./PHASES) — architecture & build order
- [`NOTES/PHASE_EVIDENCE.md`](./NOTES/PHASE_EVIDENCE.md) — validation evidence

**Verifier:** production uses Succinct `ISP1Verifier` / `SP1VerifierGateway`. Local Anvil uses `MockSP1Verifier` with the same interface.
