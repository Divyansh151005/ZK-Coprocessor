#!/usr/bin/env bash
# E2E Anvil harness.
#
# Modes:
#   PROVE_MODE=mock  (default) — MockSP1Verifier + prove-mock (simulation)
#   PROVE_MODE=sp1             — SP1VerifierGateway + Groth16 (Milestone A/B)
#
# Groth16 needs Docker ≥16GB RAM locally, or:
#   SP1_PROVER=network NETWORK_PRIVATE_KEY=...
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${HOME}/.sp1/bin:${HOME}/.cargo/bin:${HOME}/.foundry/bin:${PATH}"

# Load SPN / RPC secrets if present (never commit .env).
if [[ -f "${ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${ROOT}/.env"
  set +a
fi

RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
PK="${PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
A="${A:-2}"
B="${B:-3}"
PROVE_MODE="${PROVE_MODE:-mock}"
FIXTURE="${FIXTURE:-${ROOT}/contracts/src/fixtures/groth16-add.json}"

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

echo "== forge test =="
(
  cd "${ROOT}/contracts"
  if [[ ! -d lib/forge-std ]]; then
    git clone --depth 1 https://github.com/foundry-rs/forge-std lib/forge-std
  fi
  forge test -vv
)

if [[ "${PROVE_MODE}" == "sp1" ]]; then
  need cargo-prove
  echo "== Milestone A: cargo prove build (RISC-V ELF) =="
  (cd "${ROOT}/guest" && cargo prove build)

  echo "== build host binaries =="
  (cd "${ROOT}" && cargo build -p zk-coprocessor-host --release \
    --bin vkey --bin prove-groth16 --bin spn-balance)

  # Pre-flight: when proving via Succinct Network, require escrow before spending time.
  # Skip if a fixture already exists (offline replay) or SP1_PROVER is not network.
  SPN_MIN_PROVE="${SPN_MIN_PROVE:-1}"
  if [[ ! -f "${FIXTURE}" ]] && [[ "${SP1_PROVER:-}" == "network" ]]; then
    echo "== SPN escrow pre-flight (min ${SPN_MIN_PROVE} PROVE) =="
    if ! (cd "${ROOT}" && ./target/release/spn-balance --min "${SPN_MIN_PROVE}"); then
      cat <<EOF
BLOCKED: Insufficient SPN escrow balance (need >= ${SPN_MIN_PROVE} PROVE).
  1. Fund requester with mainnet ETH (gas) + PROVE token.
  2. Deposit via Explorer Account UI (SuccinctVApp).
  3. Re-check: ./target/release/spn-balance
  Docs: https://docs.succinct.xyz/docs/sp1/prover-network/quickstart
EOF
      exit 2
    fi
  fi

  if [[ ! -f "${FIXTURE}" ]]; then
    echo "== Milestone A/B: generate Groth16 proof =="
    mkdir -p "$(dirname "${FIXTURE}")"
    if ! (cd "${ROOT}" && ./target/release/prove-groth16 --a "${A}" --b "${B}" --out "${FIXTURE}"); then
      cat <<'EOF'
BLOCKED: Groth16 prove failed.
  - Local wrap needs Docker with ≥16GB RAM (this machine may be lower).
  - Or set SP1_PROVER=network and NETWORK_PRIVATE_KEY for Succinct Prover Network.
  - Gateway deploy + mock-rejection tests still pass via forge (Sp1GatewayLiveTest).
EOF
      exit 2
    fi
  else
    echo "using existing fixture ${FIXTURE}"
  fi

  VKEY=$(jq -r .vkey "${FIXTURE}")
  PUBLIC_VALUES=$(jq -r .publicValues "${FIXTURE}")
  PROOF=$(jq -r .proof "${FIXTURE}")
  SUM=$(jq -r .sum "${FIXTURE}")

  echo "== deploy SP1VerifierGateway =="
  DEPLOY_OUT=$(
    cd "${ROOT}/contracts"
    forge script script/DeploySp1Local.s.sol:DeploySp1Local --rpc-url "${RPC_URL}" --private-key "${PK}" --broadcast -vv
  )
  echo "${DEPLOY_OUT}"
  GATEWAY=$(echo "${DEPLOY_OUT}" | sed -n 's/.*SP1VerifierGateway[[:space:]]*\(0x[0-9a-fA-F]*\).*/\1/p' | tail -1)
  ROUTER=$(echo "${DEPLOY_OUT}" | sed -n 's/.*MinimalRequestRouter[[:space:]]*\(0x[0-9a-fA-F]*\).*/\1/p' | tail -1)
  FULFILLMENT=$(echo "${DEPLOY_OUT}" | sed -n 's/.*MinimalFulfillment[[:space:]]*\(0x[0-9a-fA-F]*\).*/\1/p' | tail -1)
  CONSUMER=$(echo "${DEPLOY_OUT}" | sed -n 's/.*MockConsumer[[:space:]]*\(0x[0-9a-fA-F]*\).*/\1/p' | tail -1)
  echo "GATEWAY=${GATEWAY} ROUTER=${ROUTER} FULFILLMENT=${FULFILLMENT} CONSUMER=${CONSUMER}"
  test -n "${GATEWAY}" && test -n "${ROUTER}" && test -n "${FULFILLMENT}" && test -n "${CONSUMER}"

  echo "== request with real program vkey =="
  TX=$(cast send "${ROUTER}" \
    "request(bytes32,uint64,uint64,address)" \
    "${VKEY}" "${A}" "${B}" "${CONSUMER}" \
    --value 0.01ether \
    --rpc-url "${RPC_URL}" --private-key "${PK}" --json)
  RID_HEX=$(echo "${TX}" | jq -r '.logs[0].topics[1]')
  REQUEST_ID=$(cast to-dec "${RID_HEX}")
  echo "requestId=${REQUEST_ID} vkey=${VKEY}"

  echo "== fulfill via SP1VerifierGateway =="
  cast send "${FULFILLMENT}" \
    "fulfill(uint256,bytes,bytes)" \
    "${REQUEST_ID}" "${PUBLIC_VALUES}" "${PROOF}" \
    --rpc-url "${RPC_URL}" --private-key "${PK}" >/dev/null

  JOURNAL=$(cast call "${CONSUMER}" "lastJournal()(bytes)" --rpc-url "${RPC_URL}")
  JV=$(echo "${JOURNAL}" | tr 'A-F' 'a-f')
  PV=$(echo "${PUBLIC_VALUES}" | tr 'A-F' 'a-f')
  if [[ "${JV}" != "${PV}" ]]; then
    echo "FAIL: journal != publicValues"
    exit 1
  fi
  echo "PASS: SP1 Anvil E2E (request → Groth16 → SP1VerifierGateway → callback sum=${SUM})"
  exit 0
fi

# -------- mock mode (default) --------
VKEY="${PROGRAM_VKEY:-0x00000000000000000000000000000000000000000000000000000000000a11ce}"

echo "== deploy MockSP1Verifier stack =="
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

echo "== fulfill =="
cast send "${FULFILLMENT}" \
  "fulfill(uint256,bytes,bytes)" \
  "${REQUEST_ID}" "${PUBLIC_VALUES}" "${PROOF}" \
  --rpc-url "${RPC_URL}" --private-key "${PK}" >/dev/null

JOURNAL=$(cast call "${CONSUMER}" "lastJournal()(bytes)" --rpc-url "${RPC_URL}")
JV=$(echo "${JOURNAL}" | tr 'A-F' 'a-f')
PV=$(echo "${PUBLIC_VALUES}" | tr 'A-F' 'a-f')
if [[ "${JV}" != "${PV}" ]]; then
  echo "FAIL: journal != publicValues"
  exit 1
fi
echo "PASS: Phase 0 Anvil E2E mock mode (journal == a+b=${SUM})"
