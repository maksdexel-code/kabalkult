// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {ClonesUpgradeable} from "@openzeppelin-contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import {IPortal} from "src/flap/IPortal.sol";
import {LaunchVaultAddresses} from "src/flap/LaunchVaultAddresses.sol";
import {KabalKultLauncher, KabalKultConfig} from "src/KabalKultLauncher.sol";

/// @notice One real launch: Portal.newLauncher (salt lock fee) then launcher.launch (poolQuote BNB, locked forever).
///         Milestones are 1.3x and 1.8x the launch market cap (= poolQuote x KK_BNB_USD, whole supply in the pool).
contract Launch is Script {
    address constant TOKEN_IMPL = 0x7777c57ff7dc441c1715b2e36fa581c48B782222;

    function run() external {
        require(block.chainid == 97, "BSC Testnet only");
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address factory = vm.envAddress("KK_FACTORY");
        uint256 bnbUsd = vm.envUint("KK_BNB_USD"); // 18 decimals
        IPortal portal = IPortal(LaunchVaultAddresses.hub());

        KabalKultConfig memory c;
        c.name = vm.envString("KK_NAME");
        c.symbol = vm.envString("KK_SYMBOL");
        c.meta = vm.envString("KK_META");
        c.salt = _mineSalt(keccak256(abi.encode(c.name, c.symbol, block.timestamp)), address(portal));
        c.poolQuote = vm.envOr("KK_POOL_QUOTE", uint256(1.1 ether));
        c.namedKols = vm.envAddress("KK_NAMED_KOLS", ",");
        c.campaignRoot = vm.envOr("KK_CAMPAIGN_ROOT", bytes32(0));
        uint256 launchMc = c.poolQuote * bnbUsd / 1e18;
        c.milestone1Usd = launchMc * 13 / 10;
        c.milestone2Usd = launchMc * 18 / 10;

        vm.startBroadcast(pk);
        KabalKultLauncher l =
            KabalKultLauncher(portal.newLauncher{value: portal.SALT_LOCK_FEE()}(factory, abi.encode(c)));
        l.launch{value: c.poolQuote}();
        vm.stopBroadcast();

        (address vault,) = portal.getLaunchVault(l.token());
        console2.log("Launcher", address(l));
        console2.log("Token   ", l.token());
        console2.log("Pool    ", l.pool());
        console2.log("Vault   ", vault);
        console2.log("Launch MC USD   ", launchMc / 1e18);
        console2.log("Milestone 1 USD ", c.milestone1Usd / 1e18);
        console2.log("Milestone 2 USD ", c.milestone2Usd / 1e18);
    }

    /// @dev Same as Flap's ForkBase: the Portal requires the token address to end in 0x7777.
    function _mineSalt(bytes32 seed, address portal) internal pure returns (bytes32 salt) {
        for (uint256 i;; ++i) {
            assembly ("memory-safe") {
                mstore(0x00, seed)
                mstore(0x20, i)
                salt := keccak256(0x00, 0x40)
            }
            if (uint16(uint160(ClonesUpgradeable.predictDeterministicAddress(TOKEN_IMPL, salt, portal))) == 0x7777) {
                return salt;
            }
        }
    }
}
