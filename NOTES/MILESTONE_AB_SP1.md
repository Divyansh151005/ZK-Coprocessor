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

## Groth16 prove status (hardware + SPN)

- Docker Desktop RAM is capped (~8GB on this machine); Succinct docs require **≥16GB** for local Groth16 wrap.
- **SPN path wired** (`SP1_PROVER=network`, `NETWORK_PRIVATE_KEY` via gitignored `.env`):
  - Program registered: `0x1ad2b9c2…338f488`
  - Circuit version: **v6.1.0** (matches on-chain Groth16 verifier)
  - Quote: ~0.4467 PROVE for add-guest Groth16
  - **BLOCKED:** requester `0xbD8bEDd077996625782E1c02d9AE62e83A079223` has **0 PROVE** deposited  
    (`insufficient balance 0.0000 PROVE for request cost 0.4467 PROVE`)
- Escape hatch after deposit ([docs](https://docs.succinct.xyz/docs/sp1/prover-network/quickstart)):
  ```bash
  # fund + deposit PROVE to the requester, then:
  PROVE_MODE=sp1 ./scripts/e2e-anvil.sh
  ```
- Until a fixture exists at `contracts/src/fixtures/groth16-add.json`, SP1 Anvil happy-path fulfillment is **BLOCKED on PROVE funding**; gateway wiring + ELF + mock-rejection remain green.

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
