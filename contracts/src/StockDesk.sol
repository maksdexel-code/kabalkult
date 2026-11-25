// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {PriceRelay} from "./PriceRelay.sol";
import {MockNVDAb} from "./MockNVDAb.sol";

/// @title StockDesk
/// @notice Testnet stand-in for buying a real bStock: sells mNVDAb for BNB at the relay's fresh price.
/// @dev shortcut: the desk keeps the BNB it receives and holds the whole mock supply; on mainnet this is
///      replaced by a real bStock purchase route.
contract StockDesk {
    using SafeTransferLib for address;

    PriceRelay public immutable relay;
    MockNVDAb public immutable stock;

    event StockBought(address indexed buyer, uint256 bnbIn, uint256 stockOut);

    error NothingToBuy();

    constructor(PriceRelay relay_) {
        relay = relay_;
        stock = new MockNVDAb(address(this));
    }

    function buy() external payable returns (uint256 out) {
        (uint256 bnbUsd, uint256 nvdaUsd) = relay.fresh();
        out = msg.value * bnbUsd / nvdaUsd;
        if (out == 0) revert NothingToBuy();
        address(stock).safeTransfer(msg.sender, out);
        emit StockBought(msg.sender, msg.value, out);
    }
}
