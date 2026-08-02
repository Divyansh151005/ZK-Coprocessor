# Phase & architecture voids (vs End_Goal + industry)

**Purpose:** Gaps to fix when planning. Flexible docs (`PHASES`, `SDD`) should absorb these; `End_Goal` stays fixed.

---

## A. Cross-cutting voids (missing from PHASES entirely)

| Gap | Why it matters | Suggested treatment |
|-----|----------------|---------------------|
| **Thin E2E vertical slice early** | Framework risk is integration, not isolated contracts | Add Phase 0 / parallel track: local Anvil + mock or real Groth16 + one guest + callback |
| **Request lifecycle** | Production needs `requestId`, status, timeout, cancel, refund, replay protection | Spec in Phase 1 contracts |
| **Program registry** | `programId` alone is weak; need VK/image pinning, versioning, deprecate | On-chain registry + storage metadata |
| **ERC-20 bounties** | `End_Goal` allows ETH or ERC-20; PHASES only ETH | Fee token abstraction |
| **Multi-L2 deployment** | Explicit in End_Goal B | Deployment matrix + CREATE2 / gateway addresses per chain |
| **Observability** | Proving SLAs, failed jobs, gas accounting | Metrics, structured logs, request tracing (Phase 5+) |
| **Security / audit / threat model** | Immutable money + crypto | Threat model doc; reentrancy, callback gas stipend, malicious journal decoding, relayer censorship |
| **AVS / open prover network** | End_Goal §4 end-state | Phase 7 (defer): staking, assignment, slashing, or integrate existing prover network |
| **Privacy path** | VIP use case claims privacy | Separate design note; not automatic from zkVM |
| **Omnichain** | End_Goal use case 3 | Deferred; needs light-client or message-passing story |
| **Testing pyramid** | Project rules demand E2E | Per-phase: unit + forge/anvil + zkVM guest tests + one golden E2E |

---

## B. Phase-by-phase voids

### Phase 1 — Gateway & verifier

**Present:** RequestRouter, UniversalVerifier, CallbackDispatcher.  

**Voids / upgrades:**

- PHASES says “compile UniversalVerifier with gnark.” For SP1/RISC Zero stacks, **prefer official VerifierGateway/Router** and build **our** application contracts around `verifyProof(vkey, publicValues, proof)`. Custom gnark is usually the wrong first move ([sp1-contracts](https://github.com/succinctlabs/sp1-contracts), [RISC Zero verifier](https://dev.risczero.com/api/blockchain-integration/contracts/verifier)).
- Bind **public values** to `{requestId, programId/vkey, callback, journal}` so proofs cannot be replayed across requests.
- Callback: gas stipend limits, target whitelist or user-supplied callback with reentrancy guard, failure accounting (don’t brick escrow).
- Access control: who may fulfill? (relayer allowlist v1 → open later).
- Events + indexed fields for indexer reliability.
- Foundry tests: happy path, bad proof, wrong vkey, reentrancy, insufficient bounty, timeout/refund.

### Phase 2 — Trustless data

**Present:** MMR accumulator, `eth_getProof`, RLP + Keccak MPT in guest.  

**Voids / upgrades:**

- Axiom-class systems use **ZK-proven updates** of 1024-hash batches + **padded MMR snapshots** so async proving remains consistent while the cache moves ([Axiom V2 contracts](https://github.com/axiom-crypto/axiom-v2-contracts)). A contract that “continually caches hashes” without a proven update path is incomplete.
- Trust root must be **blockhash** (header) → `stateRoot` → MPT path; document exact claim proven in-circuit.
- Scope: storage slot proof v1 first; accounts, receipts, txs later.
- Archive RPC dependency is for **witness generation only**—correctness is in-circuit.
- Guest library API should match End_Goal DX: `env::read_state(...)` not raw trie nodes for app authors.
- Benchmark cycles for MPT verify; precompile keccak aggressively.

### Phase 3 — zkVM engine

**Present:** Guest SDK, crypto precompile patches, trace sharding.  

**Voids / upgrades:**

- Pick **one** zkVM for v1; document hardware (Docker, RAM, GPU) from vendor docs.
- Precompiles: use vendor-supported patches (don’t hand-roll crypto circuits unless necessary).
- Sharding/GPU cluster is scale work—**defer** until single-machine Groth16 path works.
- Standardize journal ABI (abi.encode layout) shared with Solidity callbacks.
- Dev mode / mock proofs for fast Foundry iteration (RISC Zero / SP1 patterns).

### Phase 4 — Recursion & compression

**Present:** STARK aggregation, Groth16 wrap, trusted setup.  

**Voids / upgrades:**

- Prefer **vendor SDK proof modes** (`groth16()` / Plonk) over building a custom wrapper circuit ([SP1 proof types](https://docs.succinct.xyz/docs/sp1/generating-proofs/proof-types)).
- Trusted setup: inherit vendor ceremony (e.g. SP1 Aztec Ignition + contributions; RISC Zero ceremony)—document assumption; offer Plonk path if ceremony is unacceptable.
- Version pinning: gateway must route by proof version; plan upgrades without breaking apps.

### Phase 5 — Orchestrator & relayer

**Present:** Indexer, Redis/RabbitMQ pool, IPFS pull, Flashbots.  

**Voids / upgrades:**

- Job state machine: queued → proving → wrapping → submitting → confirmed / failed / expired.
- Idempotent fulfillment; stuck-nonce and replacement txs.
- Bounty accounting: refund path if SLA miss; who pays wrapper compute.
- Content addressing: IPFS **and** fallback; verify ELF hash matches `programId` before prove.
- MEV: Flashbots/MEV-Blocker is good; also protect against **callback argument manipulation** via proof binding (crypto), not only private relay.
- HA indexer: reorg handling, finality depth.
- Single-operator first; interface for multi-worker later.

### Phase 6 — Developer SDK

**Present:** `create-zk-coprocessor`, TS bindings, deploy pipeline.  

**Voids / upgrades:**

- Move a **minimal scaffold** earlier so DX informs contract/guest APIs.
- Templates for: pure compute guest; state-reading guest; example dApp callback consumer.
- `framework deploy`: network selection, explorer verify, address book output.
- Document cycle/cost estimation (even rough) for bounty UX.
- CI template for guest build + forge test.

---

## C. SDD-specific fixes

- Add **trust boundary diagram**: what RPC can lie about vs what the proof checks.  
- Add **programId / vkey / journal** data model.  
- Clarify compression is **sdk-managed** if using SP1/R0, not a bespoke Phase-4 science project for v1.  
- Explicitly include **state engine** as layer 2.5 (between gateway and zkVM), matching End_Goal C.  
- Name open questions (vendor, L2, bounty token) instead of implying settled.

---

## D. MCPs file — stance

Useful later, not required for planning:

- **Foundry MCP** — Phase 1 Solidity loop.  
- **EVM MCP** — Phase 2 `eth_getProof` witness gathering.  
- Etherscan MCP — optional for testnet verify.

Enable when coding those phases; avoid loading all at once (context cost). Prefer official CLIs if MCP quality is unclear—validate tools before depending on them.

---

## E. Definition of “industry-level” for this repo

A phase is not “done” when the brief’s bullet list exists. It is done when:

1. Threat model for that surface is written.  
2. Automated tests + one E2E path are green.  
3. Public interfaces (Solidity + guest journal ABI + events) are versioned.  
4. Failure modes (timeout, bad proof, reorg, underpriced gas) are handled or explicitly deferred with issue IDs.  
5. Progress is committed and pushed.
