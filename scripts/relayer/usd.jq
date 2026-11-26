# USD price of $sym from a CMC Pro API response: inside the object with symbol $sym, the first quote with symbol "USD".
# v3 crypto quotes: data[] {symbol, quote[] {symbol:"USD", price}}; v5 RWA: data.rwa_assets[] {symbol, quotes[] {symbol:"USD", average_tokenized_price}}.
[.. | objects | select(.symbol == $sym) | .. | objects | select(.symbol == "USD") | (.price // .average_tokenized_price // empty)][0] // empty
