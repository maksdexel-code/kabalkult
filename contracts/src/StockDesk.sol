// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {PriceRelay} from "./PriceRelay.sol";
import {MockStock} from "./MockStock.sol";

/// @title StockDesk
/// @notice Testnet stand-in for buying a real bStock: sells mock NVDA, TSLA and AAPL shares for BNB at the
///         relay's fresh CoinMarketCap prices.
/// @dev shortcut: the desk keeps the BNB it receives and holds the whole mock supply; on mainnet this is
///      replaced by a real bStock purchase route.
contract StockDesk {
    using SafeTransferLib for address;

    PriceRelay public immutable relay;
    address[] internal _stocks;
    /// @notice CMC ticker of each mock stock ("" = not sold here).
    mapping(address stock => string) public ticker;

    event StockBought(address indexed buyer, address indexed stock, uint256 bnbIn, uint256 stockOut);

    error NotAStock(address token);
    error NothingToBuy();

    constructor(PriceRelay relay_) {
        relay = relay_;
        _list("Mock NVIDIA bStock", "mNVDAb", "NVDA");
        _list("Mock Tesla bStock", "mTSLAb", "TSLA");
        _list("Mock Apple bStock", "mAAPLb", "AAPL");
    }

    function _list(string memory name, string memory symbol, string memory ticker_) private {
        address s = address(new MockStock(name, symbol, address(this)));
        _stocks.push(s);
        ticker[s] = ticker_;
    }

    /// @notice The mock stocks sold here: mNVDAb, mTSLAb, mAAPLb.
    function stocks() external view returns (address[] memory) {
        return _stocks;
    }

    function isStock(address token) public view returns (bool) {
        return bytes(ticker[token]).length != 0;
    }

    function buy(address stock) external payable returns (uint256 out) {
        if (!isStock(stock)) revert NotAStock(stock);
        out = msg.value * relay.freshBnbUsd() / relay.freshStockUsd(ticker[stock]);
        if (out == 0) revert NothingToBuy();
        stock.safeTransfer(msg.sender, out);
        emit StockBought(msg.sender, stock, msg.value, out);
    }
}
