# Milestone C — In-guest MPT state verification

**Date:** 2026-08-02

## Scope

Replace simulation-only storage reads with **cryptographic MPT verification inside the SP1 guest**, fed by host `eth_getProof`.

## Implementation

| Piece | Path |
| --- | --- |
| Guest ELF | `guest-mpt/` (`mpt-guest`) |
| Deps | `alloy-trie` 0.7 + `alloy-rlp` 0.3 (`default-features = false`) |
| Journal ABI | `StorageProofPublicValues` in `lib/src/lib.rs` |
| Host | `host/src/bin/prove-mpt` — JSON-RPC `eth_getBlockByNumber` + `eth_getProof` → `SP1Stdin` |
| Validate | `scripts/e2e-mpt.sh` (happy + tampered negative) |

### Guest stdin

1. `state_root: [u8; 32]`
2. `address: [u8; 20]`
3. `storage_slot: [u8; 32]`
4. `account_rlp: Vec<u8>`
5. `account_proof: Vec<Vec<u8>>`
6. `storage_proof: Vec<Vec<u8>>`
7. `storage_value: [u8; 32]`

Guest calls `alloy_trie::proof::verify_proof` for account under `stateRoot`, decodes account `storageRoot`, verifies storage leaf (or zero-exclusion), commits ABI journal.

### Host notes

- Avoids `alloy` umbrella crate (would conflict with `sp1-sdk` / `c-kzg` link).
- Blocking `reqwest` (no nested Tokio vs blocking SP1 client).

## Evidence

### Happy path (WETH slot 0 on mainnet public RPC)

```bash
MPT_PROVER=cpu ./scripts/e2e-mpt.sh
# or:
SP1_PROVER=cpu ./target/release/prove-mpt \
  --address 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 \
  --slot 0 --execute-only
```

Observed (2026-08-02): `execute OK cycles=687532`, journal value =
`0x577261707065642045746865720000000000000000000000000000000000001a`
(ASCII “Wrapped Ether” leaf), mpt program vkey =
`0x0056e156c75dfcee484ed4c58c127b625834f1b3b3a97c7774773ef3ea9271a5`.

### Negative

`--tamper` flips one byte of the last account proof node → guest panics (`account MPT proof invalid`).

## Groth16 / SPN

Real Groth16 for this guest still requires `SP1_PROVER=network` + funded PROVE deposit (see `NOTES/MILESTONE_AB_SP1.md`). Local Docker wrap remains ≥16GB RAM.
