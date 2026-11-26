#!/bin/bash
# Demo trading run on the live launch: random buys, periodic sells, tax dispatch and milestone checks,
# until every milestone is paid or BUYER runs low. KEEP_GOING=1 keeps trading after the last milestone.
# Usage: scripts/demo/spam.sh [max-rounds]
cd "$(dirname "$0")/../.."
export PATH="$HOME/.foundry/bin:$PATH"
set -a; . ./.env; set +a
T=scripts/demo/trade.sh
V=$(awk '/Vault/{print $2; exit}' launch/launch.txt)
R=$BSC_TESTNET_RPC_URL
LOG=launch/demo-trades.txt
ME=$(cast wallet address --private-key "0x${BUYER_PRIVATE_KEY#0x}")
paid() { cast call "$V" 'milestonesPaid()(uint256)' --rpc-url "$R"; }
total=$(cast call "$V" 'milestones()(uint256[],uint16[])' --rpc-url "$R" | head -1 | tr -cd ',' | wc -c | awk '{print $1 + 1}')

for i in $(seq "${1:-60}"); do
  amt=$(awk -v r="$RANDOM" 'BEGIN { printf "%.3f", 0.03 + (r % 31) / 1000 }')
  echo "round $i buy $amt $($T buy "$amt" | head -1)" | tee -a "$LOG"
  if (( i % 3 == 0 )); then
    pct=$(( 15 + RANDOM % 21 ))
    echo "round $i sell ${pct}% $($T sell "$pct" | sed -n 2p)" | tee -a "$LOG"
  fi
  if (( i % 4 == 0 )); then
    echo "round $i dispatch $($T dispatch | head -1)" | tee -a "$LOG"
    before=$(paid)
    out=$($T check 2>/dev/null | head -1)
    [ "$(paid)" != "$before" ] && echo "round $i MILESTONES PAID $before -> $(paid) $out" | tee -a "$LOG"
  fi
  echo "  $($T status | tr '\n' ' ')"
  [ -z "${KEEP_GOING:-}" ] && [ "$(paid)" = "$total" ] && { echo "all $total milestones paid"; break; }
  awk -v b="$(cast balance "$ME" --ether --rpc-url "$R")" 'BEGIN { exit !(b < 0.15) }' && { echo "BUYER low, stopping"; break; }
done
exit 0
