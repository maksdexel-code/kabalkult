// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title PriceRelay
/// @notice BNB/USD and stock/USD prices (18 decimals, stocks keyed by ticker, e.g. "NVDA") pushed on chain
///         by our relayer, with time and data source. Readers use `fresh*()`, which refuse prices older than MAX_AGE.
contract PriceRelay {
    uint256 public constant MAX_AGE = 10 minutes;
    address public immutable updater;

    uint256 public bnbUsd;
    mapping(string ticker => uint256) public stockUsd;
    uint256 public updatedAt;
    string public source;

    event PricesUpdated(uint256 bnbUsd, string[] tickers, uint256[] stockUsd, string source);

    error NotUpdater();
    error ZeroPrice();
    error LengthMismatch();
    error StalePrice(uint256 updatedAt);

    constructor(address updater_) {
        updater = updater_;
    }

    function update(uint256 bnbUsd_, string[] calldata tickers, uint256[] calldata prices, string calldata source_)
        external
    {
        if (msg.sender != updater) revert NotUpdater();
        if (tickers.length != prices.length) revert LengthMismatch();
        if (bnbUsd_ == 0) revert ZeroPrice();
        bnbUsd = bnbUsd_;
        for (uint256 i; i < tickers.length; ++i) {
            if (prices[i] == 0) revert ZeroPrice();
            stockUsd[tickers[i]] = prices[i];
        }
        updatedAt = block.timestamp;
        source = source_;
        emit PricesUpdated(bnbUsd_, tickers, prices, source_);
    }

    /// @notice BNB/USD, or a revert if older than MAX_AGE (or never set).
    function freshBnbUsd() public view returns (uint256) {
        if (block.timestamp - updatedAt > MAX_AGE) revert StalePrice(updatedAt);
        return bnbUsd;
    }

    /// @notice A stock's USD price, or a revert if stale or never set.
    function freshStockUsd(string memory ticker) external view returns (uint256 usd) {
        freshBnbUsd();
        usd = stockUsd[ticker];
        if (usd == 0) revert ZeroPrice();
    }
}
