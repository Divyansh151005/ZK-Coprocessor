# Research sources (primary)

Collected 2026-08-02 while reviewing `End_Goal` / `SDD` / `PHASES`. Prefer these over secondary blogs when implementing.

## End_Goal alignment targets

- Product docs in-repo: `End_Goal`, `SDD`, `PHASES`, `MCPs`

## zkVM + on-chain verification

- SP1 proof types (Groth16 ~260B, ~270k gas; Plonk alternative): https://docs.succinct.xyz/docs/sp1/generating-proofs/proof-types  
- SP1 on-chain verification setup: https://docs.succinct.xyz/docs/sp1/verification/getting-started  
- SP1 contracts / VerifierGateway: https://github.com/succinctlabs/sp1-contracts  
- RISC Zero verifier contracts / router: https://dev.risczero.com/api/blockchain-integration/contracts/verifier  
- RISC Zero Foundry / Bonsai callback pattern: https://github.com/risc0/risc0-foundry-template  

## Historical state / coprocessor analogues

- Axiom V2 contracts (block hash cache, query verification): https://github.com/axiom-crypto/axiom-v2-contracts  
- Axiom architecture overview (if URL moves, use repo README + `IAxiomV2State`): search `docs.axiom.xyz` / GitHub  

## Prover network / End_Goal §4 analogues

- Succinct Prover Network architecture: https://docs.succinct.xyz/docs/protocol/spn/architecture  
- Succinct staking / slashing for liveness: https://docs.succinct.xyz/docs/protocol/spn/staking  
- EigenLayer AVS vs purpose-built prover networks (comparison context only): evaluate only if AVS is chosen later  

## Ethereum primitives

- `BLOCKHASH` 256-window limit (why accumulators exist)  
- `eth_getProof` / Merkle Patricia Trie / RLP / Keccak-256 (witness path for Phase 2)  
- BN254 / alt_bn128 precompiles (cheap EVM pairing verify)

## Notes on ceremony / trust

- SP1 Groth16: Aztec Ignition + Succinct contributions (document; Plonk if unacceptable)  
- RISC Zero: own Groth16 ceremony (document)  
- Custom gnark ExportSolidity: https://docs.gnark.consensys.io/HowTo/prove — use only if deliberately owning a custom circuit, not as default “universal verifier” for a zkVM product
