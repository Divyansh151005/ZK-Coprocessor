# Phase validation evidence (1–7)

Companion to `PHASE0_EVIDENCE.md`. All suites run 2026-08-02 on Anvil/local.

| Phase | Surface | Evidence |
|-------|---------|----------|
| 1 | ProgramRegistry, RequestRouter, Fulfillment, CallbackDispatcher + ERC-20 bounty | `forge test --match-contract Phase1GatewayTest` — 13/13 incl. ERC-20 fulfill/refund/negatives |
| 2 | HeaderCommitment + Rust PMMR/MPT helpers | `Phase2HeaderCommitmentTest` 4/4; `cargo test -p header-commitment`; `zk-coprocessor-sdk` `read_state` |
| 2b | Milestone C in-guest MPT (`alloy-trie`) | `NOTES/MILESTONE_C_MPT.md`; `./scripts/e2e-mpt.sh` |
| 2c | HeaderCommitment + Anvil MPT vertical | `./scripts/e2e-header-mpt-anvil.sh` (mock commit → ToyStorage getProof → mpt-guest) |
| 3 | Guest SDK + journal codegen docs | `cargo test -p zk-coprocessor-sdk` |
| 4 | Sepolia/Groth16 | **BLOCKED_UNFUNDED** — `NOTES/PHASE4_SEPOLIA.md`; gate: `./scripts/preflight-spn.sh` |
| 5 | Orchestrator FSM + runnable node soak | `cargo test -p zk-orchestrator`; `./scripts/e2e-orchestrator-soak.sh` (N=8) |
| 6 | `create-zk-coprocessor` scaffold + TS journal decode | `cargo test -p create-zk-coprocessor`; JS decode assertSum |
| 7 | ProverNetwork stake/slash/earn + L2 matrix note | `Phase7ProverNetworkTest` 2/2; `NOTES/PHASE7_L2_MATRIX.md` |

## Full forge

```text
Ran 4 test suites: 29 tests passed, 0 failed
```
