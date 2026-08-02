# Locked architecture decisions (stakeholder-confirmed)

**Date:** 2026-08-02  
**Confirmed by:** User acceptance of production-pragmatic critique  
**Still open:** L2 mainnet timing; ERC-20 pricing implementation (design in Phase 5).  
**Resolved in plan/implementation:** zkVM = **SP1**; header commitment = **build** Axiom-class; L2 order Anvil→Sepolia→Base→Arb→OP→mainnet; ETH bounty first.  

These decisions are binding for planning and implementation unless `End_Goal` requires a change.

---

## D1 — Vendor VerifierGateway (no hand-rolled gnark)

- **Decision:** Do not compile a custom UniversalVerifier via gnark for the zkVM.  
- **Do:** `RequestRouter` / fulfillment formats proof + public values and calls Succinct `ISP1Verifier` gateway or RISC Zero verifier router.  
- **Why:** Audited, version-routed, multi-chain; removes verifier upgradeability from our threat model.  
- **Refs:** sp1-contracts, RISC Zero verifier docs.

## D2 — Axiom-class PMMR / ZK batch header commitments

- **Decision:** No naive per-block hash list / gas-bleeding cache.  
- **Do:** Periodic ZK proof linking ~1,024 headers → update on-chain PMMR (or integrate existing header commitment system). Guests treat that root as historical trust anchor.  
- **Why:** Gas + trust assumptions fail otherwise.

## D3 — Operational lifecycle is protocol

- **ProgramRegistry:** `programId` ↔ ELF CID hash (+ vk/image id).  
- **Request lifecycle:** ids, status, timeout, refund, replay bind.  
- **Economics:** ETH bounty first; ERC-20 / oracle / intent pricing so relayers don’t prove at a loss.  
- **Threats:** callback reentrancy, relayer censorship, fulfillment front-run / bounty theft.

## D4 — Vendor SDK for prove + compress

- **Decision:** Use `sp1-sdk` / `risc0-zkvm` (and vendor prover networks for Day-1).  
- **Defer:** Custom STARK recursion, trace sharding, owned GPU cluster until Phase 7.

## D5 — API-first DevEx / scaffold early

- **Decision:** Define Rust guest API + Solidity callback **before** deep router complexity.  
- **Phase 0** vertical slice is mandatory before heavy Phase 2–4 work.

## D6 — Vertical slice before breadth

Hardcoded add-two-numbers guest → event → orchestrator → local prove → vendor gateway on Anvil → callback.  
Only then swap in MPT state verification and scale proving.
