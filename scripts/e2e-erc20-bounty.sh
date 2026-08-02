#!/usr/bin/env bash
# Milestone 4: ERC-20 bounty Anvil path (Foundry suite covers unit/E2E-style).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${HOME}/.foundry/bin:${PATH}"

cd "${ROOT}/contracts"
forge test --match-contract Phase1GatewayTest -vv
echo "PASS: ERC-20 bounty Foundry suite (incl. fulfill + refund + negatives)"
