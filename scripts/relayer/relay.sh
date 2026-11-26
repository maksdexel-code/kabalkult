#!/bin/bash
# CMC Pro API (server side) -> PriceRelay.update(bnbUsd, tickers, stockUsd, source) on BSC Testnet.
# Prices: BNB (v3 quotes) + NVDA, TSLA, AAPL (v5 RWA, one call). Every request is logged to logs/relayer.jsonl (time, endpoint, CMC credits, price, tx hash). The key is never logged.
# Usage: scripts/relayer/relay.sh [--once] [--dry-run]     (loops every RELAY_EVERY seconds, default 300)
set -euo pipefail
cd "$(dirname "$0")/../.."
export PATH="$HOME/.foundry/bin:$PATH"
set -a; . ./.env; set +a
DEPLOYER_PRIVATE_KEY="0x${DEPLOYER_PRIVATE_KEY#0x}"  # MetaMask exports keys without 0x
: "${CMC_API_KEY:?CMC_API_KEY is empty in .env}"
ONCE=0; DRY=0; for a in "$@"; do [ "$a" = --once ] && ONCE=1; [ "$a" = --dry-run ] && DRY=1; done
API=https://pro-api.coinmarketcap.com
LOG=logs/relayer.jsonl
USD=scripts/relayer/usd.jq
RELAY=${KK_RELAY:-$(jq -r '.transactions[] | select(.contractName=="PriceRelay") | .contractAddress' contracts/broadcast/Deploy.s.sol/97/run-latest.json)}

log() { jq -nc --arg t "$(date -u +%FT%TZ)" "$@" '$ARGS.named + {time: $t}' >> "$LOG"; }

TICKERS=(NVDA TSLA AAPL)   # the StockDesk's mock stocks
SRC="CMC Pro API: BNB v3 quotes, stocks v5 RWA"

# cmc <path> -> sets BODY and logs the call (credits, error).
cmc() {
  BODY=$(curl -sS -m 20 -H "X-CMC_PRO_API_KEY: $CMC_API_KEY" -H "Accept: application/json" "$API$1")
  log --arg endpoint "$1" \
    --arg credits "$(jq -r '.status.credit_count // ""' <<<"$BODY" 2>/dev/null)" \
    --arg error "$(jq -r '(.status.error_code // "") | tostring' <<<"$BODY" 2>/dev/null) $(jq -r '.status.error_message // ""' <<<"$BODY" 2>/dev/null)"
}
usd() { jq -r --arg sym "$1" -f "$USD" <<<"$BODY" 2>/dev/null || true; }

# Reject a bad parse before it reaches the chain.
sane() { awk -v p="$1" -v lo="$2" -v hi="$3" 'BEGIN { exit !(p + 0 >= lo && p + 0 <= hi) }'; }

tick() {
  cmc "/v3/cryptocurrency/quotes/latest?id=1839"; BNB=$(usd BNB)   # 1839 = BNB
  sane "$BNB" 50 5000 || { echo "bad BNB price '$BNB'"; return 1; }
  cmc "/v5/real-world-assets/quotes/latest?symbol=$(IFS=,; echo "${TICKERS[*]}")"   # all stocks, 1 credit
  local wei=() t p
  for t in "${TICKERS[@]}"; do
    p=$(usd "$t"); sane "$p" 1 100000 || { echo "bad $t price '$p'"; return 1; }
    STOCKS+="$t \$$p  "; wei+=("$(cast to-wei "$p")")
  done
  echo "BNB \$$BNB  ${STOCKS}($SRC)"
  [ "$DRY" = 1 ] && return 0
  TX=$(cast send "$RELAY" "update(uint256,string[],uint256[],string)" "$(cast to-wei "$BNB")" \
    "[$(IFS=,; echo "${TICKERS[*]}")]" "[$(IFS=,; echo "${wei[*]}")]" "$SRC" \
    --private-key "$DEPLOYER_PRIVATE_KEY" --rpc-url "${RPC:-$BSC_TESTNET_RPC_URL}" --json | jq -r .transactionHash)
  log --arg relay "$RELAY" --arg bnbUsd "$BNB" --arg stocks "$STOCKS" --arg source "$SRC" --arg tx "$TX"
  echo "pushed: $TX"
  autopay
}

# With fresh prices on chain, pay any reached milestone (a dry call first, so nothing is spent when there is none).
autopay() {
  local v=${KK_VAULT:-$(awk '/Vault/{print $2; exit}' launch/launch.txt 2>/dev/null)}
  [ -n "$v" ] || return 0
  cast call "$v" "checkMilestone()" --from "$(cast wallet address --private-key "$DEPLOYER_PRIVATE_KEY")" \
    --rpc-url "${RPC:-$BSC_TESTNET_RPC_URL}" >/dev/null 2>&1 || return 0
  TX=$(cast send "$v" "checkMilestone()" --private-key "$DEPLOYER_PRIVATE_KEY" \
    --rpc-url "${RPC:-$BSC_TESTNET_RPC_URL}" --json | jq -r .transactionHash)
  log --arg vault "$v" --arg action checkMilestone --arg tx "$TX"
  echo "milestone paid: $TX"
}

while true; do
  STOCKS=""
  tick || echo "tick failed (see $LOG)"
  [ "$ONCE" = 1 ] && break
  sleep "${RELAY_EVERY:-300}"
done
