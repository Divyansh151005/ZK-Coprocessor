# Phase 0 — E2E vertical slice (execute after plan mode)

**Do not implement until plan mode produces the detailed plan.** This note freezes the agreed de-risk prototype.

## Goal

Prove the **full lifecycle** locally with minimal business logic:

`request event → orchestrator → zkVM prove → vendor VerifierGateway → callback`

## Components

1. **Guest (RISC-V):** Hardcoded program: read two integers, commit `a + b` to journal.  
2. **Consumer + router (Solidity on Anvil):** Emit computation request with the two numbers (+ programId); expose `receiveCoprocessorResult(bytes journal)`.  
3. **Orchestrator (Rust or Node):** Subscribe to event → prove via vendor SDK → submit tx calling our fulfillment → vendor gateway verify → callback.  
4. **Verifier:** Canonical vendor gateway deployed/configured on Anvil — **not** a custom gnark verifier.

## Explicit non-goals for the slice

- MPT / historical state  
- PMMR header commitment  
- IPFS registry (can hardcode ELF path)  
- ERC-20 bounties, Flashbots, multi-worker queue  
- Custom compression / GPU cluster  

## Exit criteria

- [ ] Anvil E2E: request → proof → callback journal equals `a + b`  
- [ ] Bad proof / wrong public values revert  
- [ ] Commands documented; tests automated where practical  
- [ ] Commit + push

## Next swap-ins (after green)

1. Replace addition guest with MPT storage read (Phase 2 start).  
2. Replace local prove with vendor prover network / stronger ops (Phase 4–5).  
3. Expand scaffold into `create-zk-coprocessor` (Phase 6).
