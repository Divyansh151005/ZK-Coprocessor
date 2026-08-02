# Project understanding (read before plan mode)

**Status:** Research locked; SDD/PHASES revised to production-pragmatic form. **No implementation until after plan mode.**  
**Date:** 2026-08-02  
**Source of truth:** [`End_Goal`](../End_Goal)  
**Locked engineering decisions:** [`LOCKED_DECISIONS.md`](./LOCKED_DECISIONS.md)  
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

## 5. Critical design decisions

### Locked (see `LOCKED_DECISIONS.md`)

Vendor VerifierGateway · Axiom-class PMMR · lifecycle/registry/economics · vendor SDK compression · API-first + Phase 0 vertical slice.

### Still open for plan mode

1. **zkVM vendor:** SP1 vs RISC Zero (or abstract both).  
2. **Header commitment:** build vs integrate existing (Axiom-class) system.  
3. **L2 rollout order:** Anvil → Sepolia → Base/Arb/OP → mainnet.  
4. **ERC-20 / gas abstraction:** oracle vs intent vs ETH-only v1.  
5. **Program identity encoding:** exact hash(ELF) / vk / CID scheme.

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

1. Confirm open decisions (zkVM, header commitment path, L2 order, bounty token).  
2. Detail **Phase 0 vertical slice** (`VERTICAL_SLICE.md`) into concrete file layout, deps, and test commands.  
3. Align Phase 1+ backlog with revised `PHASES` / `SDD`.  
4. Only after plan approval: implement Phase 0 (no breadth before green E2E).
