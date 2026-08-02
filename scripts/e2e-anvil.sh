#!/usr/bin/env bash
# Phase 0 Anvil E2E: deploy → request → mock-prove → fulfill → assert journal == a+b
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${HOME}/.foundry/bin:${PATH}"

RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
PK="${PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
A="${A:-2}"
B="${B:-3}"
VKEY="${PROGRAM_VKEY:-0x00000000000000000000000000000000000000000000000000000000000a11ce}"

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
  echo "starting anvil on ${RPC_URL}..."
  anvil --port 8545 >/tmp/zkc-anvil.log 2>&1 &
  ANVIL_PID=$!
  sleep 1
fi

echo "== forge build/test =="
(
  cd "${ROOT}/contracts"
  if [[ ! -d lib/forge-std ]]; then
    git clone --depth 1 https://github.com/foundry-rs/forge-std lib/forge-std
  fi
  forge test -vv
)

echo "== deploy =="
DEPLOY_OUT=$(
  cd "${ROOT}/contracts"
  forge script script/DeployLocal.s.sol:DeployLocal --rpc-url "${RPC_URL}" --private-key "${PK}" --broadcast -vv
)
echo "${DEPLOY_OUT}"

VERIFIER=$(echo "${DEPLOY_OUT}" | sed -n 's/.*MockSP1Verifier[[:space:]]*\(0x[0-9a-fA-F]*\).*/\1/p' | tail -1)
ROUTER=$(echo "${DEPLOY_OUT}" | sed -n 's/.*MinimalRequestRouter[[:space:]]*\(0x[0-9a-fA-F]*\).*/\1/p' | tail -1)
FULFILLMENT=$(echo "${DEPLOY_OUT}" | sed -n 's/.*MinimalFulfillment[[:space:]]*\(0x[0-9a-fA-F]*\).*/\1/p' | tail -1)
CONSUMER=$(echo "${DEPLOY_OUT}" | sed -n 's/.*MockConsumer[[:space:]]*\(0x[0-9a-fA-F]*\).*/\1/p' | tail -1)

echo "VERIFIER=${VERIFIER}"
echo "ROUTER=${ROUTER}"
echo "FULFILLMENT=${FULFILLMENT}"
echo "CONSUMER=${CONSUMER}"

test -n "${VERIFIER}" && test -n "${ROUTER}" && test -n "${FULFILLMENT}" && test -n "${CONSUMER}"

echo "== request =="
TX=$(cast send "${ROUTER}" \
  "request(bytes32,uint64,uint64,address)" \
  "${VKEY}" "${A}" "${B}" "${CONSUMER}" \
  --value 0.01ether \
  --rpc-url "${RPC_URL}" --private-key "${PK}" --json)
RID_HEX=$(echo "${TX}" | jq -r '.logs[0].topics[1]')
REQUEST_ID=$(cast to-dec "${RID_HEX}")
echo "requestId=${REQUEST_ID}"

echo "== prove-mock =="
PROOF_JSON=$(cargo run -q -p zk-coprocessor-host --bin prove-mock -- --a "${A}" --b "${B}" --vkey "${VKEY}")
PUBLIC_VALUES=$(echo "${PROOF_JSON}" | jq -r .publicValues)
PROOF=$(echo "${PROOF_JSON}" | jq -r .proof)
SUM=$(echo "${PROOF_JSON}" | jq -r .sum)
echo "sum=${SUM} publicValues=${PUBLIC_VALUES}"

echo "== fulfill =="
cast send "${FULFILLMENT}" \
  "fulfill(uint256,bytes,bytes)" \
  "${REQUEST_ID}" "${PUBLIC_VALUES}" "${PROOF}" \
  --rpc-url "${RPC_URL}" --private-key "${PK}" >/dev/null

echo "== assert journal =="
JOURNAL=$(cast call "${CONSUMER}" "lastJournal()(bytes)" --rpc-url "${RPC_URL}")
COUNT=$(cast call "${CONSUMER}" "receiveCount()(uint256)" --rpc-url "${RPC_URL}")
echo "receiveCount=${COUNT}"
echo "journal=${JOURNAL}"

# Normalize hex for compare
JV=$(echo "${JOURNAL}" | tr 'A-F' 'a-f')
PV=$(echo "${PUBLIC_VALUES}" | tr 'A-F' 'a-f')
if [[ "${JV}" != "${PV}" ]]; then
  echo "FAIL: journal != publicValues"
  exit 1
fi

EXPECTED_SUM=$(( (A + B) ))
if [[ "${SUM}" != "${EXPECTED_SUM}" ]]; then
  echo "FAIL: sum ${SUM} != ${EXPECTED_SUM}"
  exit 1
fi

echo "PASS: Phase 0 Anvil E2E (request → mock prove → callback journal == a+b)"
