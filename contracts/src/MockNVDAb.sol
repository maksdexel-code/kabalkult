// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";

/// @title MockNVDAb
/// @notice TESTNET ONLY. A mock of a tokenized NVIDIA share. Not a real asset, no redemption.
contract MockNVDAb is ERC20 {
    constructor(address to) ERC20("Mock NVIDIA bStock", "mNVDAb") {
        _mint(to, 1_000_000_000 ether);
    }
}
