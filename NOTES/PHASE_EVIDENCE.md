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
| 6 | DevEx CLI + TS SDK (M5) | `cargo test -p create-zk-coprocessor`; `npx tsx --test sdk/ts/test/decode.test.ts`; `deploy --network anvil` → `deployments/anvil.json`; `store-elf` CAS |
| 7 | ProverNetwork two-fulfiller (M6) | `Phase7ProverNetworkTest` 6/6; `./scripts/e2e-multiprover-anvil.sh`; AVS deferred in `NOTES/PHASE7_L2_MATRIX.md` |

## Full forge

```text
Ran 5 test suites: 33 tests passed, 0 failed
```
