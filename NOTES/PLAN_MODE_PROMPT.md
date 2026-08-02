# Plan-mode kickoff prompt (copy into a new Plan Mode chat)

Paste everything below the line into a **new chat in Plan mode**. Do not ask the agent to implement in that chat until the plan is approved.

---

You are planning the **ZK-Coprocessor** project in this workspace. **Do not write implementation code yet** — produce a concrete phased plan only.

## Source of truth (mandatory read order)

1. `End_Goal` (or `END_GOAL`) — **ultimate product truth**. Every plan item must serve this. If anything conflicts, prefer End_Goal.
2. `NOTES/LOCKED_DECISIONS.md` — stakeholder-confirmed engineering (vendor VerifierGateway, Axiom-class PMMR, lifecycle/registry, vendor SDK prove/compress, API-first, Phase 0 vertical slice).
3. `NOTES/PROJECT_UNDERSTANDING.md`, `NOTES/VERTICAL_SLICE.md`, `NOTES/RESEARCH_SOURCES.md`, `NOTES/PHASE_GAPS.md`
4. `SDD` — production-pragmatic architecture (flexible)
5. `PHASES` — build order (flexible; Phase 0 first)
6. `MCPs` — optional tooling only
7. `.cursor/rules/` — especially project doctrine, research-first, phase-delivery-gate, test-and-validate-e2e, commit-push-after-success

Also skim prior chat context if available: we already researched SP1/RISC Zero/Axiom/Succinct Network analogues and rejected hand-rolled gnark verifiers and naive block-hash lists.

## What we are building

An **Automated ZK-Coprocessor Framework**: trustless off-chain compute + historical chain data for smart contracts, ZK-verified callbacks on-chain (“AWS Lambda of Web3”). Final deliverables from End_Goal:

- **A** Developer CLI/SDK (`create-zk-coprocessor`)
- **B** On-chain application gateway (registry, escrow, callback) using **vendor** VerifierGateway — not custom gnark
- **C** Trustless state engine (Axiom-class PMMR + in-guest MPT)
- **D** Proving/orchestrator path; later Phase 7 decentralized network/AVS-style

## How we build (non-negotiable process)

- Build **strictly in phases** (`PHASES`). Start with **Phase 0 vertical slice** after the plan is approved.
- Before implementing any phase: research that phase against End_Goal + locked decisions; gap-fill voids; do not assume or guess deep-tech details.
- After **each phase** implementation: run **robust, complete, industry-standard validation** (unit + integration + E2E + negative/failure paths for everything that phase owns). Nothing left untested in that phase’s surface.
- A phase is **not done** until exit criteria are green with cited evidence.
- Only then **git add / commit / push** to `https://github.com/Divyansh151005/ZK-Coprocessor.git` to save progress. Do not push red or half-broken phases.
- Do not start the next phase until the current phase is validated and pushed.

## Plan mode output I need from you

1. Restate End_Goal success criteria in your own words (short).
2. Resolve or explicitly flag open decisions: SP1 vs RISC Zero; build vs integrate header commitments; L2 order; ERC-20/gas pricing for v1.
3. A **detailed Phase 0 plan** (file layout, deps, Anvil + vendor gateway, orchestrator, test matrix, exact exit criteria) matching `NOTES/VERTICAL_SLICE.md`.
4. Phased roadmap for Phase 1→7 aligned to revised `PHASES`/`SDD`, with per-phase: scope, threats, test plan, exit criteria, deferrals.
5. Risks, voids still open, and what is explicitly out of scope for v1.
6. Recommended first implementation prompt for Agent mode after I approve this plan (Phase 0 only).

Remember: **End_Goal is sacred. Research before design. Phase gates + full testing + push after green. No coding in this plan chat.**
