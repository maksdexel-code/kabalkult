#!/bin/bash
# CMC Pro API (server side) -> PriceRelay.update(bnbUsd, tickers, stockUsd, source) on BSC Testnet.
# Prices: BNB (v3 quotes) + NVDA, TSLA, AAPL (v5 RWA, one call), cross-checked against Atlas on-chain feeds
# (BNB/USD, NVDAB/USD): if CMC and Atlas disagree, the round is skipped, prices go stale and payouts wait. Every request is logged to logs/relayer.jsonl (time, endpoint, CMC credits, price, tx hash). The key is never logged.
# Usage: scripts/relayer/relay.sh [--once] [--dry-run]     (loops every RELAY_EVERY seconds, default 300)
set -euo pipefail
cd "$(dirname "$0")/../.."
export PATH="$HOME/.foundry/bin:$PATH"
[ -f .env ] && { set -a; . ./.env; set +a; }   # in the cloud, settings come from env vars + Secret Manager
DEPLOYER_PRIVATE_KEY="0x${DEPLOYER_PRIVATE_KEY#0x}"  # MetaMask exports keys without 0x
: "${CMC_API_KEY:?CMC_API_KEY is empty in .env}"
ONCE=0; DRY=0; for a in "$@"; do [ "$a" = --once ] && ONCE=1; [ "$a" = --dry-run ] && DRY=1; done
API=https://pro-api.coinmarketcap.com
LOG=logs/relayer.jsonl
USD=scripts/relayer/usd.jq
RELAY=${KK_RELAY:-$(jq -r '.transactions[] | select(.contractName=="PriceRelay") | .contractAddress' contracts/broadcast/Deploy.s.sol/97/run-latest.json)}

log() {  # one JSON line per event; RELAY_LOG_STDOUT=1 also prints it (Cloud Logging picks it up in the cloud)
  local line; line=$(jq -nc --arg t "$(date -u +%FT%TZ)" "$@" '$ARGS.named + {time: $t}')
  echo "$line" >> "$LOG"; [ "${RELAY_LOG_STDOUT:-0}" = 1 ] && echo "$line"; return 0
}

TICKERS=(NVDA TSLA AAPL)   # the StockDesk's mock stocks

# Atlas oracle feeds on BSC Testnet (Chainlink-style, 18 decimals; addresses from the Atlas team, see docs/ADDRESSES.md).
ATLAS_BNB=0x3957d289ee9C38272377786787ea34F9dd29788D
ATLAS_NVDAB=0x3ef39d6361efa1e8ca066751f438077da81082a6
MAX_GAP_BNB=${MAX_GAP_BNB:-1}      # % CMC vs Atlas BNB/USD may differ
MAX_GAP_NVDA=${MAX_GAP_NVDA:-3}     # % CMC NVDA vs Atlas NVDAB (tokenized stock, can trade at a small premium)
ATLAS_MAX_AGE=${ATLAS_MAX_AGE:-3600} # seconds

# atlas <feed> -> USD price, or fails if the feed is unreadable or older than ATLAS_MAX_AGE.
atlas() {
  local r; r=$(cast call "$1" "latestRoundData()(uint80,int256,uint256,uint256,uint80)" --rpc-url "${RPC:-$BSC_TESTNET_RPC_URL}") || return 1
  local answer updated; answer=$(sed -n 2p <<<"$r" | cut -d' ' -f1); updated=$(sed -n 4p <<<"$r" | cut -d' ' -f1)
  (( $(date +%s) - updated <= ATLAS_MAX_AGE )) || return 1
  cast from-wei "$answer"
}
# gap <a> <b> -> |a-b|/b in %, 2 decimals.
gap() { awk -v a="$1" -v b="$2" 'BEGIN { d = (a - b) / b * 100; if (d < 0) d = -d; printf "%.2f", d }'; }
within() { awk -v g="$1" -v m="$2" 'BEGIN { exit !(g ~ /^[0-9.]+$/ && g + 0 <= m + 0) }'; }  # empty/garbage = disagree

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
  # Atlas cross-check. The Atlas NVDAB price is also published on chain as ticker "NVDAB".
  local aBnb aNvdab gBnb gNvda
  aBnb=$(atlas $ATLAS_BNB) && aNvdab=$(atlas $ATLAS_NVDAB) || { log --arg error "atlas feed unreadable or stale, round skipped"; echo "atlas feed unreadable or stale, round skipped"; return 1; }
  gBnb=$(gap "$BNB" "$aBnb"); gNvda=$(gap "$(usd NVDA)" "$aNvdab")
  log --arg atlasBnbUsd "$aBnb" --arg atlasNvdabUsd "$aNvdab" --arg gapBnbPct "$gBnb" --arg gapNvdaPct "$gNvda"
  if ! within "$gBnb" $MAX_GAP_BNB || ! within "$gNvda" $MAX_GAP_NVDA; then
    log --arg error "CMC and Atlas disagree (BNB ${gBnb}%, NVDA ${gNvda}%), round skipped"
    echo "CMC and Atlas disagree (BNB ${gBnb}%, NVDA ${gNvda}%), round skipped"; return 1
  fi
  TICKERS+=(NVDAB); wei+=("$(cast to-wei "$aNvdab")"); STOCKS+="NVDAB(Atlas) \$$aNvdab  "
  SRC="CMC Pro API (BNB v3, stocks v5 RWA) + Atlas feeds (BNB/USD, NVDAB/USD) agree: BNB ${gBnb}%, NVDA ${gNvda}%"
  echo "BNB \$$BNB  ${STOCKS}($SRC)"
  [ "$DRY" = 1 ] && return 0
  local out; out=$(cast send "$RELAY" "update(uint256,string[],uint256[],string)" "$(cast to-wei "$BNB")" \
    "[$(IFS=,; echo "${TICKERS[*]}")]" "[$(IFS=,; echo "${wei[*]}")]" "$SRC" \
    --private-key "$DEPLOYER_PRIVATE_KEY" --gas-price 0.1gwei --priority-gas-price 0.1gwei --rpc-url "${RPC:-$BSC_TESTNET_RPC_URL}" --json 2>&1 || true)
  TX=$(jq -r '.transactionHash // empty' <<<"$out" 2>/dev/null || true)
  [ -n "$TX" ] || { log --arg error "push failed: ${out:0:300}"; echo "push failed: ${out:0:300}"; return 1; }
  log --arg relay "$RELAY" --arg bnbUsd "$BNB" --arg stocks "$STOCKS" --arg source "$SRC" --arg tx "$TX"
  echo "pushed: $TX"
  autopay
}

# Every launched KabalKult deal: the factory's KabalKultLauncherCreated events, read from a node that allows
# event searches (the default BSC node refuses them; publicnode allows 50,000 blocks per call).
FACTORY=${KK_FACTORY:-0xb3E793C1111900F3d47EEe4D8c22c3C15cD0551F}
FACTORY_BLOCK=${KK_FACTORY_BLOCK:-144947353}   # factory deploy block
LOGS_RPC=${KK_LOGS_RPC:-https://bsc-testnet-rpc.publicnode.com}
vaults() {
  local rpc=${RPC:-$BSC_TESTNET_RPC_URL} n s l
  n=$(cast block-number --rpc-url "$LOGS_RPC") || return 1
  for ((s = FACTORY_BLOCK; s <= n; s += 50000)); do
    cast logs --address "$FACTORY" "KabalKultLauncherCreated(address indexed,address indexed,bytes32)" \
      --from-block $s --to-block $((s + 49999 > n ? n : s + 49999)) --rpc-url "$LOGS_RPC" --json | jq -r '.[].topics[1]' || return 1
  done | while read -r l; do
    l=0x${l: -40}
    [ "$(cast call "$l" "launched()(bool)" --rpc-url "$rpc")" = true ] && cast call "$l" "vault()(address)" --rpc-url "$rpc"
  done
}

# With fresh prices on chain, pay any reached milestone in every deal (a dry call first, so nothing is spent when
# there is none). Deals = factory events + KK_VAULTS (comma-separated known vaults, a fallback for when the event
# search is refused, e.g. publicnode blocks some cloud IPs).
# Move waiting tax from the token's tax processor (Flap) into the vault, so a reached milestone has BNB to pay.
# Only when the processor holds BNB or tax tokens, and only if a dry call passes (no gas wasted otherwise).
dispatch() {
  local rpc=${RPC:-$BSC_TESTNET_RPC_URL} t p tx
  t=$(cast call "$1" "token()(address)" --rpc-url "$rpc") || return 0
  p=$(cast call "$t" "taxProcessor()(address)" --rpc-url "$rpc") || return 0
  [ "$(cast balance "$p" --rpc-url "$rpc")" != 0 ] || [ "$(cast call "$t" "balanceOf(address)(uint256)" "$p" --rpc-url "$rpc" | cut -d' ' -f1)" != 0 ] || return 0
  cast call "$p" "dispatch()" --from "$(cast wallet address --private-key "$DEPLOYER_PRIVATE_KEY")" --rpc-url "$rpc" >/dev/null 2>&1 || return 0
  tx=$(cast send "$p" "dispatch()" --private-key "$DEPLOYER_PRIVATE_KEY" --gas-price 0.1gwei --priority-gas-price 0.1gwei \
    --rpc-url "$rpc" --json | jq -r .transactionHash) || return 0
  log --arg vault "$1" --arg action dispatch --arg tx "$tx"
  echo "tax dispatched ($1): $tx"
}

autopay() {
  local v list found
  found=$(vaults) || { found=""; log --arg error "event search failed, using KK_VAULTS only"; }
  list=$(printf '%s\n' ${KK_VAULTS//,/ } $found | tr 'A-F' 'a-f' | sort -u)
  for v in $list; do
    dispatch "$v"
    cast call "$v" "checkMilestone()" --from "$(cast wallet address --private-key "$DEPLOYER_PRIVATE_KEY")" \
      --rpc-url "${RPC:-$BSC_TESTNET_RPC_URL}" >/dev/null 2>&1 || continue
    TX=$(cast send "$v" "checkMilestone()" --private-key "$DEPLOYER_PRIVATE_KEY" --gas-price 0.1gwei --priority-gas-price 0.1gwei \
      --rpc-url "${RPC:-$BSC_TESTNET_RPC_URL}" --json | jq -r .transactionHash) || continue
    log --arg vault "$v" --arg action checkMilestone --arg tx "$TX"
    echo "milestone paid ($v): $TX"
  done
}

while true; do
  STOCKS=""; TICKERS=(NVDA TSLA AAPL)
  tick || echo "tick failed (see $LOG)"
  [ "$ONCE" = 1 ] && break
  sleep "${RELAY_EVERY:-300}"
done
