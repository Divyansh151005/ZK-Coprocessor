# Phase 0 evidence

**Date:** 2026-08-02  
**zkVM pin:** SP1 path prepared (`guest/` + optional `sp1-sdk`); local E2E uses `MockSP1Verifier` implementing `ISP1Verifier` (swap for `SP1VerifierGateway` + Groth16 in Phase 4).

## Commands + results

```text
forge test -vv
→ 22 passed (Phase0 + Phase1 + Phase2 + Phase7 suites)

cargo test --workspace
→ all packages ok (lib, header-commitment, sdk, orchestrator, cli)

./scripts/e2e-anvil.sh
→ PASS: Phase 0 Anvil E2E (request → mock prove → callback journal == a+b)
  requestId=1 a=2 b=3 sum=5 journal matched publicValues
```

## Exit criteria

- [x] Anvil E2E: request → prove → callback journal == a+b
- [x] Negatives: bad proof, wrong public values, double fulfill, wrong vkey (Foundry)
- [x] Commands in `scripts/README-e2e.md`
- [x] Build/type-check clean
- [x] Commit + push after green

## Journal ABI v0

`abi.encode(uint64 a, uint64 b, uint64 sum)` — wrapping add.
