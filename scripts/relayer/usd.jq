# USD price from a CMC Pro API response: the first object with symbol "USD" anywhere in it.
# v3 crypto quotes: data[].quote[] {symbol:"USD", price}; v5 RWA: data.rwa_assets[].quotes[] {symbol:"USD", average_tokenized_price}.
[.. | objects | select(.symbol == "USD") | (.price // .average_tokenized_price // empty)][0] // empty
