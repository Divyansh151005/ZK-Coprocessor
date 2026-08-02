# Phase 4 — prove path hardening (Sepolia)

## Pins (record at implement time)

| Component | Version / note |
|-----------|----------------|
| SP1 SDK | `6.0.1+` (align guest `sp1-zkvm` + host `sp1-sdk`) |
| sp1-contracts | forge-install `succinctlabs/sp1-contracts` matching SDK |
| Proof system | Groth16 (Plonk escape hatch if ceremony unacceptable) |
| Gateway | Canonical `SP1VerifierGateway` per [contract addresses](https://docs.succinct.xyz/docs/sp1/verification/contract-addresses) |

## Trusted setup assumption

SP1 Groth16 inherits Aztec Ignition + Succinct contributions. Document in app READMEs. Offer Plonk if ceremony trust is unacceptable to a consumer.

## Sepolia checklist

1. Deploy application gateway (Phase 1) pointing at Sepolia `SP1VerifierGateway` Groth16.
2. Register program vkey from `cargo run --bin vkey` (when SP1 feature enabled).
3. Prove via `SP1_PROVER=network` (Succinct Prover Network) or local Docker Groth16.
4. Fulfill N consecutive requests; log latency + gas.

## Cost / latency budget (bounty UX)

- Verifier gas class ~270k (Groth16) — End_Goal ~$0.01–$0.05 depending on L2/ETH fees.
- Prove latency: network-dependent; orchestrator floor bounty must cover prove + gas (Phase 5).

## Negatives

- Version skew (proof version not routed on gateway) → revert.
- Wrong vkey → revert (covered in Phase 0/1 tests with mock; re-run on Sepolia with fixture).

## Status

Local Anvil path uses `MockSP1Verifier` until SP1 toolchain + Docker Groth16 or NETWORK_PRIVATE_KEY available. Swap verifier address without changing fulfillment ABI.
