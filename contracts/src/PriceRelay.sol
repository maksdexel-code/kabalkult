// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title PriceRelay
/// @notice BNB/USD and NVDA/USD (18 decimals) pushed on chain by our relayer, with time and data source.
///         Readers use `fresh()`, which refuses prices older than MAX_AGE.
contract PriceRelay {
    uint256 public constant MAX_AGE = 10 minutes;
    address public immutable updater;

    uint256 public bnbUsd;
    uint256 public nvdaUsd;
    uint256 public updatedAt;
    string public source;

    event PricesUpdated(uint256 bnbUsd, uint256 nvdaUsd, string source);

    error NotUpdater();
    error ZeroPrice();
    error StalePrice(uint256 updatedAt);

    constructor(address updater_) {
        updater = updater_;
    }

    function update(uint256 bnbUsd_, uint256 nvdaUsd_, string calldata source_) external {
        if (msg.sender != updater) revert NotUpdater();
        if (bnbUsd_ == 0 || nvdaUsd_ == 0) revert ZeroPrice();
        bnbUsd = bnbUsd_;
        nvdaUsd = nvdaUsd_;
        updatedAt = block.timestamp;
        source = source_;
        emit PricesUpdated(bnbUsd_, nvdaUsd_, source_);
    }

    /// @notice Both prices, or a revert if they are older than MAX_AGE (or were never set).
    function fresh() external view returns (uint256, uint256) {
        if (block.timestamp - updatedAt > MAX_AGE) revert StalePrice(updatedAt);
        return (bnbUsd, nvdaUsd);
    }
}
