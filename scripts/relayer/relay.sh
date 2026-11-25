#!/bin/bash
# CMC Pro API (server side) -> PriceRelay.update(bnbUsd, nvdaUsd, source) on BSC Testnet.
# Every request is logged to logs/relayer.jsonl (time, endpoint, CMC credits, price, tx hash). The key is never logged.
# Usage: scripts/relayer/relay.sh [--once] [--dry-run]     (loops every RELAY_EVERY seconds, default 300)
set -euo pipefail
cd "$(dirname "$0")/../.."
set -a; . ./.env; set +a
: "${CMC_API_KEY:?CMC_API_KEY is empty in .env}"
ONCE=0; DRY=0; for a in "$@"; do [ "$a" = --once ] && ONCE=1; [ "$a" = --dry-run ] && DRY=1; done
API=https://pro-api.coinmarketcap.com
LOG=logs/relayer.jsonl
USD=scripts/relayer/usd.jq
RELAY=${KK_RELAY:-$(jq -r '.transactions[] | select(.contractName=="PriceRelay") | .contractAddress' contracts/broadcast/Deploy.s.sol/97/run-latest.json)}

log() { jq -nc --arg t "$(date -u +%FT%TZ)" "$@" '$ARGS.named + {time: $t}' >> "$LOG"; }

# cmc <path> -> sets PRICE (empty if not found) and logs the call.
cmc() {
  local body; body=$(curl -sS -m 20 -H "X-CMC_PRO_API_KEY: $CMC_API_KEY" -H "Accept: application/json" "$API$1")
  PRICE=$(jq -r -f "$USD" <<<"$body" 2>/dev/null || true)
  log --arg endpoint "$1" --arg price "$PRICE" \
    --arg credits "$(jq -r '.status.credit_count // ""' <<<"$body" 2>/dev/null)" \
    --arg error "$(jq -r '(.status.error_code // "") | tostring' <<<"$body" 2>/dev/null) $(jq -r '.status.error_message // ""' <<<"$body" 2>/dev/null)"
}

# Reject a bad parse before it reaches the chain.
sane() { awk -v p="$1" -v lo="$2" -v hi="$3" 'BEGIN { exit !(p + 0 >= lo && p + 0 <= hi) }'; }

tick() {
  cmc "/v3/cryptocurrency/quotes/latest?id=1839"; BNB=$PRICE   # 1839 = BNB
  sane "$BNB" 50 5000 || { echo "bad BNB price '$BNB'"; return 1; }
  cmc "/v5/real-world-assets/quotes/latest?symbol=NVDA"; NVDA=$PRICE; SRC="CMC Pro API: BNB v3 quotes, NVDA v5 RWA"
  if ! sane "$NVDA" 10 5000; then  # RWA endpoint not on our plan -> the real NVIDIA bStock listing
    cmc "/v3/cryptocurrency/quotes/latest?id=40215"; NVDA=$PRICE; SRC="CMC Pro API: BNB v3 quotes, NVDA via NVDAB (id 40215)"
    sane "$NVDA" 10 5000 || { echo "bad NVDA price '$NVDA'"; return 1; }
  fi
  echo "BNB \$$BNB  NVDA \$$NVDA  ($SRC)"
  [ "$DRY" = 1 ] && return 0
  TX=$(cast send "$RELAY" "update(uint256,uint256,string)" "$(cast to-wei "$BNB")" "$(cast to-wei "$NVDA")" "$SRC" \
    --private-key "$DEPLOYER_PRIVATE_KEY" --rpc-url "$BSC_TESTNET_RPC_URL" --json | jq -r .transactionHash)
  log --arg relay "$RELAY" --arg bnbUsd "$BNB" --arg nvdaUsd "$NVDA" --arg source "$SRC" --arg tx "$TX"
  echo "pushed: $TX"
}

while true; do
  tick || echo "tick failed (see $LOG)"
  [ "$ONCE" = 1 ] && break
  sleep "${RELAY_EVERY:-300}"
done
