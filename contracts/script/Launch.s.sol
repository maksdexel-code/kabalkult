// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {ClonesUpgradeable} from "@openzeppelin-contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import {IPortal} from "src/flap/IPortal.sol";
import {LaunchVaultAddresses} from "src/flap/LaunchVaultAddresses.sol";
import {KabalKultLauncher, KabalKultConfig} from "src/KabalKultLauncher.sol";
import {KabalKultLauncherFactory} from "src/KabalKultLauncherFactory.sol";
import {KabalKultVaultFactory} from "src/KabalKultVaultFactory.sol";
import {StockDesk} from "src/StockDesk.sol";

/// @notice One real launch: Portal.newLauncher (salt lock fee) then launcher.launch (poolQuote BNB, locked forever).
///         Launch MC = poolQuote x KK_BNB_USD (whole supply in the pool). Options (env, defaults in brackets):
///         KK_MILESTONES_X10 [13,18 = 1.3x and 1.8x launch MC], KK_MILESTONE_SHARES_BPS [5000,5000],
///         KK_BUY_TAX_BPS [500], KK_SELL_TAX_BPS [500], KK_PAYOUT_TOKEN [the desk's mNVDAb; 0x000…0 = BNB],
///         KK_CAMPAIGN_SLOTS [50].
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
        c.campaignSlots = uint32(vm.envOr("KK_CAMPAIGN_SLOTS", uint256(50)));
        uint256 launchMc = c.poolQuote * bnbUsd / 1e18;
        uint256[] memory x10 = vm.envOr("KK_MILESTONES_X10", ",", _pair(13, 18)); // 13 = 1.3x launch MC
        c.milestoneUsd = new uint256[](x10.length);
        for (uint256 i; i < x10.length; ++i) c.milestoneUsd[i] = launchMc * x10[i] / 10;
        uint256[] memory shares = vm.envOr("KK_MILESTONE_SHARES_BPS", ",", _pair(5000, 5000));
        c.milestoneShareBps = new uint16[](shares.length);
        for (uint256 i; i < shares.length; ++i) c.milestoneShareBps[i] = uint16(shares[i]);
        c.buyTaxBps = uint16(vm.envOr("KK_BUY_TAX_BPS", uint256(500)));
        c.sellTaxBps = uint16(vm.envOr("KK_SELL_TAX_BPS", uint256(500)));
        StockDesk desk = StockDesk(KabalKultVaultFactory(KabalKultLauncherFactory(factory).vaultFactory()).desk());
        c.payoutToken = vm.envOr("KK_PAYOUT_TOKEN", desk.stocks()[0]);

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
        for (uint256 i; i < c.milestoneUsd.length; ++i) {
            console2.log("Milestone USD / share bps", c.milestoneUsd[i] / 1e18, c.milestoneShareBps[i]);
        }
        console2.log("Payout token    ", c.payoutToken);
        console2.log("Tax buy/sell bps", c.buyTaxBps, c.sellTaxBps);
        console2.log("Campaign slots  ", c.campaignSlots);
    }

    function _pair(uint256 a, uint256 b) internal pure returns (uint256[] memory p) {
        p = new uint256[](2);
        (p[0], p[1]) = (a, b);
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
