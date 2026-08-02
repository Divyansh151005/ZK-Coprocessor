# Phase 4 — prove path hardening (Sepolia)

## Status: **BLOCKED_UNFUNDED** (v1 A+Unfunded)

Live Sepolia fulfillment and Succinct Prover Network Groth16 are **gated** until the requester deposits PROVE (and has Sepolia ETH for gas). Local Anvil + `PROVE_MODE=mock` remains the green path.

| Gate | Command / check |
|------|-----------------|
| SPN escrow | `./scripts/preflight-spn.sh` → wraps `spn-balance --min ${SPN_MIN_PROVE:-1}` |
| Unlock prove | Deposit PROVE via [Explorer Account UI](https://explorer.succinct.xyz) ([docs](https://docs.succinct.xyz/docs/sp1/prover-network/quickstart)) |
| Anvil SP1 E2E | `PROVE_MODE=sp1 SP1_PROVER=network ./scripts/e2e-anvil.sh` (pre-flight runs automatically) |
| Sepolia | Follow checklist below **after** escrow ≥ 1 PROVE |

## Pins

| Component | Version / note |
|-----------|----------------|
| SP1 SDK / cargo-prove | **6.3.1** (guest `sp1-zkvm` + host `sp1-sdk`) |
| On-chain Groth16 verifier | **v6.1.0** (`VERIFIER_HASH` in `DeploySp1Local.s.sol`) |
| sp1-contracts | `contracts/lib/sp1-contracts` (forge install) |
| Proof system | Groth16 (Plonk escape hatch if ceremony unacceptable) |
| Gateway | Canonical `SP1VerifierGateway` / [contract addresses](https://docs.succinct.xyz/docs/sp1/verification/contract-addresses) |

## Trusted setup assumption

SP1 Groth16 inherits Aztec Ignition + Succinct contributions. Document in app READMEs. Offer Plonk if ceremony trust is unacceptable to a consumer.

## Unlock sequence (when funded)

```bash
export PATH="$HOME/.sp1/bin:$HOME/.cargo/bin:$HOME/.foundry/bin:$PATH"
# 1) Confirm escrow
./scripts/preflight-spn.sh
# 2) Anvil real Groth16 (optional fixture)
PROVE_MODE=sp1 SP1_PROVER=network ./scripts/e2e-anvil.sh
# 3) Sepolia — deploy gateway apps to Sepolia SP1VerifierGateway, then fulfill N requests
```

## Sepolia checklist

1. Deploy application gateway (Phase 1) pointing at Sepolia `SP1VerifierGateway` Groth16.
2. Register program vkey from `./target/release/vkey`.
3. Prove via `SP1_PROVER=network` (or local Docker Groth16 ≥16GB RAM).
4. Fulfill N consecutive requests; log latency + gas.

## Cost / latency budget (bounty UX)

- Verifier gas class ~270k (Groth16) — End_Goal ~$0.01–$0.05 depending on L2/ETH fees.
- Prove latency: network-dependent; orchestrator floor bounty must cover prove + gas (Phase 5).
- add-guest Groth16 quote observed ~0.45 PROVE (see `NOTES/MILESTONE_AB_SP1.md`).

## Negatives

- Version skew (proof version not routed on gateway) → revert.
- Wrong vkey → revert (Phase 0/1 Foundry; re-run on Sepolia with fixture when funded).
- `spn-balance --min 1` exit 1 / e2e exit 2 when escrow empty.
