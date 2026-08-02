# TypeScript SDK

Journal decode helpers for ZK-Coprocessor consumers.

```bash
npm test --prefix sdk/ts   # if package scripts exist
node -e "const {decodePhase0Journal,assertSum}=require('./dist'); ..."
```

## Exports

- `decodePhase0Journal` / `assertSum` — add-guest journal
- `decodeStorageJournal` — Milestone C storage journal
- `bountyEstimateEth` — floor helper
- `REQUEST_ABI` — MinimalRequestRouter fragment

Install the Rust CLI for scaffold/deploy:

```bash
cargo install --path cli
create-zk-coprocessor new my-app --template compute
create-zk-coprocessor deploy --network anvil
create-zk-coprocessor store-elf --elf path/to/elf
```
