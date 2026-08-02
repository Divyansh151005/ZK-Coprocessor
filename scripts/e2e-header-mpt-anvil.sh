#!/usr/bin/env bash
# Milestone 2: HeaderCommitment (mock) + Anvil eth_getProof + mpt-guest execute.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${HOME}/.sp1/bin:${HOME}/.cargo/bin:${HOME}/.foundry/bin:${PATH}"

RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
PK="${PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
UPDATER_VKEY="${UPDATER_VKEY:-0x00000000000000000000000000000000000000000000000000000000000901}"
# DeployHeaderMptLocal uses 0xHDR01 = bytes32(uint256(0xHDR01)) — set after deploy from log

need() { command -v "$1" >/dev/null || { echo "missing $1"; exit 1; }; }
need forge
need cast
need anvil
need cargo
need jq

ANVIL_PID=""
cleanup() {
  if [[ -n "${ANVIL_PID}" ]] && kill -0 "${ANVIL_PID}" 2>/dev/null; then
    kill "${ANVIL_PID}" || true
  fi
}
trap cleanup EXIT

if ! curl -s -X POST -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' \
  "${RPC_URL}" >/dev/null 2>&1; then
  echo "starting anvil..."
  anvil --port 8545 >/tmp/zkc-anvil-header-mpt.log 2>&1 &
  ANVIL_PID=$!
  sleep 1
fi

echo "== cargo test header-commitment + sdk =="
(cd "${ROOT}" && cargo test -p header-commitment -p zk-coprocessor-sdk 2>&1 | tail -30)

echo "== forge Phase2HeaderCommitment =="
(cd "${ROOT}/contracts" && forge test --match-contract Phase2HeaderCommitmentTest -vv)

echo "== build host bins =="
(cd "${ROOT}" && cargo build -p zk-coprocessor-host --release --bin header-commit-encode --bin prove-mpt)

echo "== deploy HeaderCommitment + ToyStorage =="
DEPLOY_OUT=$(
  cd "${ROOT}/contracts"
  forge script script/DeployHeaderMptLocal.s.sol:DeployHeaderMptLocal \
    --rpc-url "${RPC_URL}" --private-key "${PK}" --broadcast -vv
)
echo "${DEPLOY_OUT}"
VERIFIER=$(echo "${DEPLOY_OUT}" | sed -n 's/.*MockSP1Verifier[[:space:]]*\(0x[0-9a-fA-F]*\).*/\1/p' | tail -1)
HEADERS=$(echo "${DEPLOY_OUT}" | sed -n 's/.*HeaderCommitment[[:space:]]*\(0x[0-9a-fA-F]*\).*/\1/p' | tail -1)
TOY=$(echo "${DEPLOY_OUT}" | sed -n 's/.*ToyStorage[[:space:]]*\(0x[0-9a-fA-F]*\).*/\1/p' | tail -1)
UPDATER_VKEY=0x0000000000000000000000000000000000000000000000000000000000000a01
test -n "${VERIFIER}" && test -n "${HEADERS}" && test -n "${TOY}"
echo "VERIFIER=${VERIFIER} HEADERS=${HEADERS} TOY=${TOY} VKEY=${UPDATER_VKEY}"

# Mine so toy storage is in a block
cast rpc anvil_mine --rpc-url "${RPC_URL}" >/dev/null || true
BLOCK_HEX=$(cast block-number --rpc-url "${RPC_URL}")
BLOCK_HEX=$(printf '0x%x' "${BLOCK_HEX}")
STATE_ROOT=$(cast block "${BLOCK_HEX}" --rpc-url "${RPC_URL}" --json | jq -r .stateRoot)
echo "block=${BLOCK_HEX} stateRoot=${STATE_ROOT}"

echo "== commit batch (mock proof) binding stateRoot =="
PV=$("${ROOT}/target/release/header-commit-encode" --state-root "${STATE_ROOT}" --start-block 0)
PROOF=$(cast call "${VERIFIER}" "mockProof(bytes32,bytes)(bytes)" "${UPDATER_VKEY}" "${PV}" --rpc-url "${RPC_URL}")
cast send "${HEADERS}" "commitBatch(bytes,bytes)" "${PV}" "${PROOF}" \
  --rpc-url "${RPC_URL}" --private-key "${PK}" >/dev/null
COMMITTED=$(cast call "${HEADERS}" "historicalRoots(uint64)(bytes32)" 0 --rpc-url "${RPC_URL}")
echo "committed batchRoot=${COMMITTED}"

echo "== negative: wrong root must not match commitment helper =="
# prove-mpt against public RPC would use different root; here verify encode rejects mismatch via cargo test already.
# Tamper: try commit duplicate start → revert
set +e
cast send "${HEADERS}" "commitBatch(bytes,bytes)" "${PV}" "${PROOF}" \
  --rpc-url "${RPC_URL}" --private-key "${PK}" >/tmp/zkc-dup-commit.out 2>&1
DUP_RC=$?
set -e
if [[ "${DUP_RC}" -eq 0 ]]; then
  echo "FAIL: duplicate commit should revert"
  exit 1
fi
echo "PASS: duplicate batch rejected"

echo "== Anvil eth_getProof + mpt-guest execute =="
export SP1_PROVER=cpu
export MPT_PROVER=cpu
"${ROOT}/target/release/prove-mpt" \
  --address "${TOY}" --slot 0 --rpc "${RPC_URL}" --block "${BLOCK_HEX}" --execute-only \
  >/tmp/zkc-header-mpt-ok.out 2>&1
grep -q 'execute OK' /tmp/zkc-header-mpt-ok.out
# Journal value should be 42
grep -q '000000000000000000000000000000000000000000000000000000000000002a' /tmp/zkc-header-mpt-ok.out \
  || (echo "FAIL: expected value 42 in journal"; cat /tmp/zkc-header-mpt-ok.out; exit 1)

echo "== negative: tampered MPT =="
set +e
"${ROOT}/target/release/prove-mpt" \
  --address "${TOY}" --slot 0 --rpc "${RPC_URL}" --block "${BLOCK_HEX}" --execute-only --tamper \
  >/tmp/zkc-header-mpt-bad.out 2>&1
TAMPER_RC=$?
set -e
if [[ "${TAMPER_RC}" -eq 0 ]]; then
  echo "FAIL: tampered proof succeeded"
  exit 1
fi
echo "PASS: Milestone 2 header+MPT Anvil E2E"
