# Milestone A/B — real SP1 path

**Date:** 2026-08-02

## A — Toolchain + RISC-V ELF

- Installed `cargo-prove` **v6.3.1** (direct GitHub release; bypassed hung `sp1up` curl installer).
- Installed `succinct` rustup toolchain (`riscv32im-succinct-zkvm-elf`).
- `cd guest && cargo prove build` →  
  `guest/target/elf-compilation/riscv64im-succinct-zkvm-elf/release/add-guest`
- Program vkey (from `./target/release/vkey`):  
  `0x0035a57384181f4dab15ee06e5a10943477beb8bc09fb20619a48482e338f488`

## B — SP1VerifierGateway on Anvil

- `forge install` path: `contracts/lib/sp1-contracts` (+ OZ submodule).
- `script/DeploySp1Local.s.sol` deploys:
  - `SP1VerifierGateway` (owner = deployer)
  - `SP1Verifier` Groth16 **v6.1.0** (`VERIFIER_HASH = 0x4388a21c…`)
  - `gateway.addRoute(verifier)`
  - app router / fulfillment / consumer wired to **gateway** (not MockSP1Verifier)
- Foundry: `Sp1GatewayLiveTest` — route registered; **mock proofs rejected** by real gateway.
- Full suite: **25 passed**.

## Groth16 prove status (hardware)

- Docker Desktop reports **~3.8 GiB** memory; Succinct docs require **≥16GB** for local Groth16 wrap.
- `prove-groth16` starts (STARK phase) but wrap is expected to fail/OOM or run very long locally.
- Escape hatch: `SP1_PROVER=network NETWORK_PRIVATE_KEY=…` then:
  ```bash
  PROVE_MODE=sp1 ./scripts/e2e-anvil.sh
  ```
- Until a fixture exists at `contracts/src/fixtures/groth16-add.json`, SP1 E2E happy-path is **BLOCKED on this machine**; gateway wiring + ELF + mock-rejection are green.

## Commands

```bash
export PATH="$HOME/.sp1/bin:$HOME/.cargo/bin:$HOME/.foundry/bin:$PATH"
cd guest && cargo prove build
cargo build -p zk-coprocessor-host --release --bin vkey --bin prove-groth16
./target/release/vkey
# optional: generate fixture (needs RAM or SPN)
./target/release/prove-groth16 --a 2 --b 3 --out contracts/src/fixtures/groth16-add.json
PROVE_MODE=sp1 ./scripts/e2e-anvil.sh
```
