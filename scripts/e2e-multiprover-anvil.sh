#!/usr/bin/env bash
# Milestone 6: two-fulfiller ProverNetwork on Anvil (centralized; not EigenLayer AVS).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${HOME}/.foundry/bin:${PATH}"
# Avoid leaking SPN key into forge wallet selection.
unset NETWORK_PRIVATE_KEY || true

cd "${ROOT}/contracts"
forge test --match-contract Phase7ProverNetworkTest -vv

ANVIL_PID=""
cleanup() {
  if [[ -n "${ANVIL_PID}" ]] && kill -0 "${ANVIL_PID}" 2>/dev/null; then
    kill "${ANVIL_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
if ! curl -s -X POST -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
  "${RPC_URL}" | grep -q result; then
  anvil --host 127.0.0.1 --port 8545 >/tmp/anvil-multiprover.log 2>&1 &
  ANVIL_PID=$!
  for _ in $(seq 1 30); do
    if curl -s -X POST -H 'content-type: application/json' \
      --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
      "${RPC_URL}" | grep -q result; then
      break
    fi
    sleep 0.2
  done
fi

PK0=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
PK1=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
PK2=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
ADDR1=$(cast wallet address --private-key "$PK1")
ADDR2=$(cast wallet address --private-key "$PK2")

DEPLOY_OUT=$(forge script script/DeployProverNetwork.s.sol:DeployProverNetwork \
  --rpc-url "${RPC_URL}" --private-key "${PK0}" --broadcast -vv 2>&1)
echo "${DEPLOY_OUT}" | tail -15
NET=$(jq -r '.transactions[] | select(.contractName=="ProverNetwork") | .contractAddress' \
  broadcast/DeployProverNetwork.s.sol/31337/run-latest.json | head -1)
[[ "${NET}" =~ ^0x[0-9a-fA-F]{40}$ ]] || { echo "FAIL: could not parse ProverNetwork address"; exit 1; }
echo "ProverNetwork=${NET}"

cast send "${NET}" "join()" --value 1ether --rpc-url "${RPC_URL}" --private-key "${PK1}" >/dev/null
cast send "${NET}" "join()" --value 1ether --rpc-url "${RPC_URL}" --private-key "${PK2}" >/dev/null

ELIG1=$(cast call "${NET}" "isEligible(address)(bool)" "${ADDR1}" --rpc-url "${RPC_URL}")
ELIG2=$(cast call "${NET}" "isEligible(address)(bool)" "${ADDR2}" --rpc-url "${RPC_URL}")
[[ "${ELIG1}" == "true" && "${ELIG2}" == "true" ]] || { echo "FAIL: both must be eligible"; exit 1; }

cast send "${NET}" "assignJob(uint256,address,uint256)" 1 "${ADDR1}" 100000000000000000 \
  --rpc-url "${RPC_URL}" --private-key "${PK0}" >/dev/null
cast send "${NET}" "assignJob(uint256,address,uint256)" 2 "${ADDR2}" 200000000000000000 \
  --rpc-url "${RPC_URL}" --private-key "${PK0}" >/dev/null
cast send "${NET}" "completeJob(uint256)" 1 --rpc-url "${RPC_URL}" --private-key "${PK0}" >/dev/null
cast send "${NET}" "completeJob(uint256)" 2 --rpc-url "${RPC_URL}" --private-key "${PK0}" >/dev/null

cast send "${NET}" "assignJob(uint256,address,uint256)" 3 "${ADDR1}" 50000000000000000 \
  --rpc-url "${RPC_URL}" --private-key "${PK0}" >/dev/null
cast send "${NET}" "slashMissedJob(uint256,uint256,string)" 3 1000000000000000000 "timeout" \
  --rpc-url "${RPC_URL}" --private-key "${PK0}" >/dev/null

ELIG1_AFTER=$(cast call "${NET}" "isEligible(address)(bool)" "${ADDR1}" --rpc-url "${RPC_URL}")
ELIG2_AFTER=$(cast call "${NET}" "isEligible(address)(bool)" "${ADDR2}" --rpc-url "${RPC_URL}")
[[ "${ELIG1_AFTER}" == "false" ]] || { echo "FAIL: prover1 should be ineligible after slash"; exit 1; }
[[ "${ELIG2_AFTER}" == "true" ]] || { echo "FAIL: prover2 should remain eligible"; exit 1; }

echo "PASS: two-fulfiller ProverNetwork Anvil demo (assign/earn/slash)"
