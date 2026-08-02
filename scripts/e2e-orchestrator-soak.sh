#!/usr/bin/env bash
# Milestone 3: orchestrator soak — N requests auto fulfilled via prove-mock.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${HOME}/.sp1/bin:${HOME}/.cargo/bin:${HOME}/.foundry/bin:${PATH}"

RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
PK="${PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
N="${SOAK_N:-8}"
VKEY="${PROGRAM_VKEY:-0x00000000000000000000000000000000000000000000000000000000000a11ce}"
# Unfunded soak uses prove-mock only.
export SP1_PROVER=cpu

need() { command -v "$1" >/dev/null || { echo "missing $1"; exit 1; }; }
need forge; need cast; need anvil; need cargo; need jq

ANVIL_PID=""
ORCH_PID=""
cleanup() {
  if [[ -n "${ORCH_PID}" ]] && kill -0 "${ORCH_PID}" 2>/dev/null; then kill "${ORCH_PID}" || true; fi
  if [[ -n "${ANVIL_PID}" ]] && kill -0 "${ANVIL_PID}" 2>/dev/null; then kill "${ANVIL_PID}" || true; fi
}
trap cleanup EXIT

if ! curl -s -X POST -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' \
  "${RPC_URL}" >/dev/null 2>&1; then
  anvil --port 8545 >/tmp/zkc-anvil-orch.log 2>&1 &
  ANVIL_PID=$!
  sleep 1
fi

echo "== forge build / unit =="
(cd "${ROOT}" && cargo test -p zk-orchestrator 2>&1 | tail -25)
(cd "${ROOT}" && cargo build -p zk-orchestrator --release --bin orchestrator)
(cd "${ROOT}" && cargo build -p zk-coprocessor-host --release --bin prove-mock)

echo "== deploy =="
DEPLOY_OUT=$(
  cd "${ROOT}/contracts"
  forge script script/DeployLocal.s.sol:DeployLocal --rpc-url "${RPC_URL}" --private-key "${PK}" --broadcast -vv
)
ROUTER=$(echo "${DEPLOY_OUT}" | sed -n 's/.*MinimalRequestRouter[[:space:]]*\(0x[0-9a-fA-F]*\).*/\1/p' | tail -1)
FULFILLMENT=$(echo "${DEPLOY_OUT}" | sed -n 's/.*MinimalFulfillment[[:space:]]*\(0x[0-9a-fA-F]*\).*/\1/p' | tail -1)
CONSUMER=$(echo "${DEPLOY_OUT}" | sed -n 's/.*MockConsumer[[:space:]]*\(0x[0-9a-fA-F]*\).*/\1/p' | tail -1)
test -n "${ROUTER}" && test -n "${FULFILLMENT}" && test -n "${CONSUMER}"
echo "ROUTER=${ROUTER} FULFILLMENT=${FULFILLMENT} CONSUMER=${CONSUMER}"

echo "== start orchestrator =="
RUST_LOG=info "${ROOT}/target/release/orchestrator" \
  --rpc "${RPC_URL}" --router "${ROUTER}" --fulfillment "${FULFILLMENT}" \
  --private-key "${PK}" --max-jobs "${N}" --poll-ms 500 \
  >/tmp/zkc-orch.log 2>&1 &
ORCH_PID=$!

echo "== submit ${N} requests =="
for i in $(seq 1 "${N}"); do
  A=$((i))
  B=$((i + 1))
  cast send "${ROUTER}" "request(bytes32,uint64,uint64,address)" \
    "${VKEY}" "${A}" "${B}" "${CONSUMER}" \
    --value 0.001ether \
    --rpc-url "${RPC_URL}" --private-key "${PK}" >/dev/null
done

echo "== wait for orchestrator =="
for _ in $(seq 1 60); do
  if ! kill -0 "${ORCH_PID}" 2>/dev/null; then
    break
  fi
  sleep 1
done
wait "${ORCH_PID}" || true
ORCH_PID=""

CONFIRMED=$(grep -c 'confirmed' /tmp/zkc-orch.log || true)
echo "confirmed_lines=${CONFIRMED}"
if [[ "${CONFIRMED}" -lt "${N}" ]]; then
  echo "FAIL: expected ${N} confirmations"
  cat /tmp/zkc-orch.log
  exit 1
fi
echo "PASS: orchestrator soak N=${N}"
