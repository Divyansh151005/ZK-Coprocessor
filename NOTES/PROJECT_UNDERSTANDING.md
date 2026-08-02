# Project understanding (read before plan mode)

**Status:** Research + gap analysis only. No implementation started.  
**Date:** 2026-08-02  
**Source of truth:** [`End_Goal`](../End_Goal)  
**Flexible plans:** [`SDD`](../SDD), [`PHASES`](../PHASES)  
**Optional tooling:** [`MCPs`](../MCPs)

---

## 1. Motive (why this exists)

Smart contracts cannot cheaply do heavy compute or deep historical reads. Centralized APIs reintroduce trust. This project turns the chain into a **trustless cloud orchestrator**: dApps outsource compute/history queries off-chain, get a **ZK-verified** result back on-chain for roughly verifier gas (~$0.01–$0.05 class), with **no cryptography required from app developers**.

One-line product metaphor (from `End_Goal`): **AWS Lambda of Web3**.

---

## 2. Final product = four deliverables (must all land)

Mapped from `End_Goal` §2:

| ID | Deliverable | What “done” means |
|----|-------------|-------------------|
| A | Developer CLI & SDK (`create-zk-coprocessor`) | Scaffold `/app` (Rust) + `/contracts` (Solidity); `env::read_state()`-class abstractions; one-click compile→RISC-V→storage→bindings |
| B | On-chain gateway | Shared universal verifier; bounty escrow; secure callback dispatcher; multi-chain (Ethereum + L2s) |
| C | Trustless state engine | Historical block-hash commitment (MMR/PMMR-style); MPT/RLP/Keccak verification **inside** zkVM; no trust in Infura for correctness |
| D | Decentralized proving network | Indexer → GPU zkVM prove → STARK→SNARK compress → MEV-aware relayer; later open as AVS / staking network |

`End_Goal` §3 use cases (DeFi history, VIP/loyalty with privacy, omnichain reads, verifiable games) and §4 (AVS / restaking / open provers) define **success metrics**, not optional extras.

---

## 3. How SDD / PHASES relate

### SDD (3 layers)

1. On-chain gateway (Solidity / Foundry)  
2. zkVM engine (Rust / SP1 or RISC Zero + compression)  
3. Off-chain orchestrator (indexer, proving pool, relayer)

SDD flow (request → index → execute → prove → compress → verify → callback) matches industry patterns (RISC Zero Bonsai relay, SP1 on-chain verify). SDD is a solid skeleton but **underspecifies** state engine depth, multi-L2, program registry, request lifecycle, and network economics vs `End_Goal`.

### PHASES (6 phases)

| Phase | Intent | Covers End_Goal pieces |
|-------|--------|-------------------------|
| 1 | Gateway + verifier | Part of B |
| 2 | Trustless data | Core of C |
| 3 | zkVM engine | Core of D (compute) + part of A (guest SDK) |
| 4 | Recursion / SNARK wrap | Part of D (compression) + B (VK link) |
| 5 | Orchestrator / relayer | Rest of D (ops) |
| 6 | CLI / SDK / deploy | A |

**Missing as explicit phases:** multi-L2 rollout, security/audit/ops, and §4 network/AVS end-state. Phase order also puts DevEx last; for a framework product, a **thin vertical slice** (toy CLI + one guest + gateway + mock/local prove) should appear early so architecture is validated E2E before scaling each layer.

---

## 4. Competitive / primary-source landscape (researched)

Do not reinvent blindly—compose and differentiate.

| System | Role vs our goal | Primary refs |
|--------|------------------|--------------|
| **Axiom** | Production ZK coprocessor for **historical Ethereum data** + compute; on-chain block-hash cache (1024-batches + padded MMR); query verified vs cache | [Axiom V2 contracts](https://github.com/axiom-crypto/axiom-v2-contracts), architecture docs |
| **SP1 (Succinct)** | RISC-V zkVM; STARK prove + recursion + Groth16/Plonk wrap; **SP1VerifierGateway** on EVM (~260B Groth16, ~270k gas class) | [Proof types](https://docs.succinct.xyz/docs/sp1/generating-proofs/proof-types), [sp1-contracts](https://github.com/succinctlabs/sp1-contracts) |
| **Risc Zero / Bonsai** | zkVM + Groth16 on-chain; **request → relay → verify → callback** template | [Verifier contracts](https://dev.risczero.com/api/blockchain-integration/contracts/verifier), Foundry template |
| **Succinct Prover Network** | Decentralized prover marketplace + stake/slash (PROVE)—closest live analogue to `End_Goal` §4 (not necessarily EigenLayer AVS) | [SPN architecture](https://docs.succinct.xyz/docs/protocol/spn/architecture) |

**Strategic implication:** Differentiate on **integrated product** (CLI + state engine + gateway + network), not on reinventing the Groth16 verifier or zkVM core on day one.

---

## 5. Critical design decisions to resolve in plan mode

1. **zkVM vendor:** SP1 vs RISC Zero (or abstract both). Affects guest SDK, precompiles, verifier contracts, Docker/prove hardware, trusted setup story.  
2. **Universal verifier strategy:** Reuse vendor **VerifierGateway/Router** + pin program VK / image ID, vs hand-rolling gnark Solidity (PHASES §1). Industry default: **reuse gateway**, own the **application gateway** (request/escrow/callback).  
3. **State engine scope v1:** Headers-only vs account/storage/tx/receipt (Axiom-class). MPT+RLP in-guest is a multi-month workstream—scope a minimal honest v1.  
4. **Block-hash cache:** Naive “store hashes” vs Axiom-style ZK-updated batches + PMMR snapshots for async proving.  
5. **Centralized prover v1 vs network:** Ship single-operator orchestrator first; design interfaces so AVS/SPN-like network plugs in later (`End_Goal` §4).  
6. **Program identity:** `programId` = hash(ELF) vs VK hash vs content-addressed IPFS CID + on-chain registry.  
7. **Economics:** ETH-only bounty vs ERC-20; fee split (prover gas vs protocol fee); timeout + refund; unpaid griefing.  
8. **L2 strategy:** Which chains first (Sepolia → Base/Arb/OP → mainnet).  
9. **Privacy use case:** VIP history without revealing exact activity needs selective disclosure / committed inputs—not free from “ZK of Rust.”

---

## 6. Agent operating rules for phase briefs

When the user supplies a phase implementation plan:

1. Treat it as a **draft**, not complete production scope.  
2. Diff against `End_Goal` + this NOTES pack.  
3. Research voids with primary sources.  
4. Propose a **hardened phase plan** (must-have / should-have / defer).  
5. Implement only after validation gates and then commit/push.

---

## 7. Suggested plan-mode agenda (next chat)

1. Lock v1 product slice that proves A+B+C+D **minimally** (e.g. “prove Fibonacci + one eth_getProof storage read → callback on Anvil/Sepolia”).  
2. Choose zkVM + verifier strategy with written rationale.  
3. Rewrite PHASES into production-aware phases including: request lifecycle, registry, observability, test matrix, multi-L2, and deferred AVS.  
4. Update SDD sequence diagrams + trust boundaries.  
5. Decide MCP enablement (Foundry / EVM RPC) when Phase 1–2 coding starts—not a blocker for planning.
