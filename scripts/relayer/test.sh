#!/bin/bash
# Self-check of the USD extractor on the response shapes from CMC's API docs.
set -euo pipefail
cd "$(dirname "$0")"
v3='{"status":{"credit_count":1},"data":[{"id":1839,"symbol":"BNB","quote":[{"id":2781,"symbol":"USD","price":612.5}]}]}'
v5='{"data":{"rwa_assets":[{"symbol":"NVDA","quotes":[{"symbol":"USD","average_tokenized_price":226.46}]}]},"status":{"credit_count":1}}'
err='{"status":{"error_code":1006,"error_message":"plan"},"data":null}'
[ "$(jq -r -f usd.jq <<<"$v3")" = 612.5 ] && [ "$(jq -r -f usd.jq <<<"$v5")" = 226.46 ] && [ -z "$(jq -r -f usd.jq <<<"$err")" ] && echo "usd.jq ok"
