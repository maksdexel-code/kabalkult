// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";

/// @title MockStock
/// @notice TESTNET ONLY. A mock of a tokenized share (e.g. "Mock NVIDIA bStock", mNVDAb). Not a real asset.
contract MockStock is ERC20 {
    constructor(string memory name_, string memory symbol_, address to) ERC20(name_, symbol_) {
        _mint(to, 1_000_000_000 ether);
    }
}
