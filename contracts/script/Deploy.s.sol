// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {PriceRelay} from "src/PriceRelay.sol";
import {StockDesk} from "src/StockDesk.sol";
import {KabalKultLauncherFactory} from "src/KabalKultLauncherFactory.sol";

/// @notice Deploys PriceRelay, StockDesk (+ mNVDAb, mTSLAb, mAAPLb) and the Launcher factory (+ its vault factory).
///         The deployer becomes the PriceRelay updater (our relayer).
contract Deploy is Script {
    /// @dev V2 router on PancakeSwap's testnet pools (Flap's ForkAddresses.sol; see docs/ADDRESSES.md).
    address constant ROUTER = 0xc9D63ddCB9549578057EAB6A83a543DdFEE2b8c3;

    function run() external {
        require(block.chainid == 97, "BSC Testnet only");
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(pk);
        PriceRelay relay = new PriceRelay(vm.addr(pk));
        StockDesk desk = new StockDesk(relay);
        KabalKultLauncherFactory lf = new KabalKultLauncherFactory(address(relay), address(desk), ROUTER);
        vm.stopBroadcast();

        console2.log("PriceRelay              ", address(relay));
        console2.log("StockDesk               ", address(desk));
        address[] memory stocks = desk.stocks();
        console2.log("mNVDAb                  ", stocks[0]);
        console2.log("mTSLAb                  ", stocks[1]);
        console2.log("mAAPLb                  ", stocks[2]);
        console2.log("KabalKultLauncherFactory", address(lf));
        console2.log("KabalKultVaultFactory   ", lf.vaultFactory());
    }
}
