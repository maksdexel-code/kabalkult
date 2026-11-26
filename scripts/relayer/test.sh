#!/bin/bash
# Self-check of the USD extractor on the response shapes from CMC's API docs.
set -euo pipefail
cd "$(dirname "$0")"
usd() { jq -r --arg sym "$1" -f usd.jq <<<"$2"; }
v3='{"status":{"credit_count":1},"data":[{"id":1839,"symbol":"BNB","quote":[{"id":2781,"symbol":"USD","price":612.5}]}]}'
v5='{"data":{"rwa_assets":[{"symbol":"NVDA","quotes":[{"symbol":"USD","average_tokenized_price":226.46}]},{"symbol":"TSLA","quotes":[{"symbol":"USD","average_tokenized_price":381.5}]}]},"status":{"credit_count":1}}'
err='{"status":{"error_code":1006,"error_message":"plan"},"data":null}'
[ "$(usd BNB "$v3")" = 612.5 ] && [ "$(usd NVDA "$v5")" = 226.46 ] && [ "$(usd TSLA "$v5")" = 381.5 ] \
  && [ -z "$(usd AAPL "$v5")" ] && [ -z "$(usd BNB "$err")" ] && echo "usd.jq ok"
