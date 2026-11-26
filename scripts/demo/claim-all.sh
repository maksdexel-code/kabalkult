#!/bin/bash
# Claim every named KOL's share from the live vault (anyone can trigger; funds only go to the KOL).
cd "$(dirname "$0")/../.."
export PATH="$HOME/.foundry/bin:$PATH"
set -a; . ./.env; set +a
R=$BSC_TESTNET_RPC_URL
V=$(awk '/Vault/{print $2; exit}' launch/launch.txt)
S=$(cast call "$V" 'payoutToken()(address)' --rpc-url "$R")
for k in ${KK_NAMED_KOLS//,/ }; do
  echo "claim $k $(scripts/demo/trade.sh claim "$k" | head -1)" | tee -a launch/demo-trades.txt
  bal=$(cast call "$S" 'balanceOf(address)(uint256)' "$k" --rpc-url "$R" | awk '{printf "%.6f", $1/1e18}')
  usd=$(cast call "$V" 'earned(address)(uint256,uint256,uint256)' "$k" --rpc-url "$R" | sed -n 3p | awk '{printf "%.2f", $1/1e18}')
  echo "  holds $bal of the payout token, earned \$$usd"
done
