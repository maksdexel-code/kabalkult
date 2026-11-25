#!/bin/bash
# Demo trades on the launched token with the BUYER wallet:
#   scripts/demo/trade.sh status | buy <tBNB> | sell <percent of BUYER's tokens> | dispatch | check
# dispatch = token's tax processor sends collected tax BNB to the vault; check = vault.checkMilestone().
set -euo pipefail
cd "$(dirname "$0")/../.."
export PATH="$HOME/.foundry/bin:$PATH"
set -a; . ./.env; set +a
K="0x${BUYER_PRIVATE_KEY#0x}"; R=${RPC:-$BSC_TESTNET_RPC_URL}; ME=$(cast wallet address --private-key "$K")
WBNB=0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd; ROUTER=0xc9D63ddCB9549578057EAB6A83a543DdFEE2b8c3
T=${KK_TOKEN:-$(awk '/Token/{print $2; exit}' launch/launch.txt)}; V=${KK_VAULT:-$(awk '/Vault/{print $2; exit}' launch/launch.txt)}
send() { cast send "$@" --private-key "$K" --rpc-url "$R" --json | jq -r '"tx " + .transactionHash'; }
deadline() { echo $(( $(date +%s) + 600 )); }

case "${1:-status}" in
buy) send $ROUTER "swapExactETHForTokensSupportingFeeOnTransferTokens(uint256,address[],address,uint256)" \
       0 "[$WBNB,$T]" $ME "$(deadline)" --value "${2:?amount}ether" ;;
sell) AMT=$(cast call $T "balanceOf(address)(uint256)" $ME --rpc-url $R | awk -v p="${2:?percent}" '{printf "%.0f", $1 * p / 100}')
      send $T "approve(address,uint256)" $ROUTER $AMT
      send $ROUTER "swapExactTokensForETHSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)" \
       $AMT 0 "[$T,$WBNB]" $ME "$(deadline)" ;;
dispatch) send "$(cast call $T "taxProcessor()(address)" --rpc-url $R)" "dispatch()" ;;
check) send $V "checkMilestone()" ;;
status) ;;
*) echo "usage: scripts/demo/trade.sh status|buy <tBNB>|sell <percent>|dispatch|check"; exit 1 ;;
esac
echo "BUYER $(cast balance $ME --ether --rpc-url $R) tBNB | vault $(cast balance $V --ether --rpc-url $R) tBNB | paid $(cast call $V 'milestonesPaid()(uint256)' --rpc-url $R)/2"
echo "market cap \$$(cast call $V 'marketCapUsd()(uint256)' --rpc-url $R 2>/dev/null | awk '{printf "%.0f", $1/1e18}' || echo '? (price stale: run the relayer)')"
