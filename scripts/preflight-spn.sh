#!/usr/bin/env bash
# CI / local pre-flight: require Succinct Prover Network escrow before SPN Groth16.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${HOME}/.sp1/bin:${HOME}/.cargo/bin:${PATH}"

if [[ -f "${ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${ROOT}/.env"
  set +a
fi

MIN="${SPN_MIN_PROVE:-1}"

if [[ -z "${NETWORK_PRIVATE_KEY:-}" ]]; then
  echo "BLOCKED_UNFUNDED: NETWORK_PRIVATE_KEY unset (copy .env.example → .env)."
  exit 2
fi

echo "== build spn-balance =="
(cd "${ROOT}" && cargo build -p zk-coprocessor-host --release --bin spn-balance)

echo "== SPN escrow pre-flight (min ${MIN} PROVE) =="
if ! "${ROOT}/target/release/spn-balance" --min "${MIN}"; then
  cat <<EOF
BLOCKED_UNFUNDED: SPN escrow below ${MIN} PROVE.
  1. Fund requester with mainnet ETH (gas) + PROVE (0x6BEF15D938d4E72056AC92Ea4bDD0D76B1C4ad29).
  2. Deposit via https://explorer.succinct.xyz Account UI.
  3. Re-run: ./scripts/preflight-spn.sh
  Docs: NOTES/PHASE4_SEPOLIA.md · NOTES/MILESTONE_AB_SP1.md
EOF
  exit 2
fi

echo "PASS: SPN escrow pre-flight (>= ${MIN} PROVE)"
