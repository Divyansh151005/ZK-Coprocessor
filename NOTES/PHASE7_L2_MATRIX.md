# Phase 7 — multi-L2 deployment matrix

Order (locked plan): **Anvil → Sepolia → Base → Arbitrum → Optimism → Ethereum mainnet**.

| Chain | VerifierGateway | Our CREATE2 / address book | Notes |
|-------|-----------------|----------------------------|-------|
| Anvil 31337 | MockSP1Verifier / local deploy | `scripts/e2e-anvil.sh` | Phase 0 |
| Sepolia | Succinct deployments JSON | Phase 4 | First public prove |
| Base | Succinct deployments | Phase 7 | First L2 |
| Arbitrum | Succinct deployments | Phase 7 | |
| Optimism | Succinct deployments | Phase 7 | |
| Ethereum | Succinct deployments | Phase 7 | Last |

Open prover participation: `ProverNetwork.sol` stake/slash sketch + optional Succinct Prover Network integration (prefer SPN for prove marketplace; own registry for fulfiller economics).
