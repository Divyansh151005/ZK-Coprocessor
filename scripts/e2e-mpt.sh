#!/usr/bin/env bash
# Milestone C: live eth_getProof → mpt-guest execute (+ negative tamper).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${HOME}/.sp1/bin:${HOME}/.cargo/bin:${PATH}"

if [[ -f "${ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${ROOT}/.env"
  set +a
fi

# Prefer CPU execute for local validation (avoid SPN init / PROVE balance).
export SP1_PROVER="${MPT_PROVER:-cpu}"

ADDR="${MPT_ADDRESS:-0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2}"
SLOT="${MPT_SLOT:-0}"
RPC="${ETH_RPC_URL:-https://ethereum-rpc.publicnode.com}"

echo "== build prove-mpt =="
(cd "${ROOT}" && cargo build -p zk-coprocessor-host --release --bin prove-mpt)

echo "== happy path: execute-only =="
"${ROOT}/target/release/prove-mpt" \
  --address "${ADDR}" --slot "${SLOT}" --rpc "${RPC}" --execute-only \
  --out /tmp/zkc-mpt-ok.json >/tmp/zkc-mpt-ok.out 2>&1
grep -q 'execute OK' /tmp/zkc-mpt-ok.out
echo "PASS: MPT execute"

echo "== negative: tampered account proof must fail =="
set +e
"${ROOT}/target/release/prove-mpt" \
  --address "${ADDR}" --slot "${SLOT}" --rpc "${RPC}" --execute-only --tamper \
  >/tmp/zkc-mpt-bad.out 2>&1
RC=$?
set -e
if [[ "${RC}" -eq 0 ]]; then
  echo "FAIL: tampered proof unexpectedly succeeded"
  exit 1
fi
if ! grep -Eqi 'account MPT proof invalid|panic|ProofVerification|failed' /tmp/zkc-mpt-bad.out; then
  echo "FAIL: expected verify panic; got:"
  tail -40 /tmp/zkc-mpt-bad.out
  exit 1
fi
echo "PASS: tampered MPT proof rejected (exit=${RC})"
echo "PASS: Milestone C MPT validation"
