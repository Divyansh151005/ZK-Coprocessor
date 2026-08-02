# Phase 7 — multi-L2 deployment matrix + open prover (v1)

Order (checklist only while unfunded — **no live L2 txs**): **Anvil → Sepolia → Base → Arbitrum → Optimism → Ethereum mainnet**.

| Chain | VerifierGateway | Our CREATE2 / address book | Notes |
|-------|-----------------|----------------------------|-------|
| Anvil 31337 | MockSP1Verifier / local deploy | `scripts/e2e-anvil.sh` | Phase 0 |
| Sepolia | Succinct deployments JSON | Phase 4 **BLOCKED_UNFUNDED** | First public prove when funded |
| Base | Succinct deployments | checklist | First L2 |
| Arbitrum | Succinct deployments | checklist | |
| Optimism | Succinct deployments | checklist | |
| Ethereum | Succinct deployments | checklist | Last |

## Open prover (v1 Anvil)

`ProverNetwork.sol` is a **centralized** stake / assign / earn / slash registry for multi-fulfiller demos:

- Two Anvil keys stake ETH (`join`)
- Orchestrator/owner `assignJob` → `completeJob` (bounty accounting)
- `slashMissedJob` for timeouts
- Demo: `./scripts/e2e-multiprover-anvil.sh`

Prefer Succinct Prover Network for the prove marketplace when funded; this registry covers fulfiller economics on our gateway.

## EigenLayer AVS — deferred

**Out of scope for End_Goal v1 (A + Unfunded).** No EigenLayer operator sets, `AllocationManager` slash wiring, or restaked security. Revisit only after funded Sepolia/SPN path and a dedicated AVS design against primary EigenLayer docs ([ELIP-002](https://github.com/eigenfoundation/ELIPs/blob/main/ELIPs/ELIP-002.md)).
