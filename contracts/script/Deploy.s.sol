// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {PriceRelay} from "src/PriceRelay.sol";
import {StockDesk} from "src/StockDesk.sol";
import {KabalKultLauncherFactory} from "src/KabalKultLauncherFactory.sol";

/// @notice Deploys PriceRelay, StockDesk (+ MockNVDAb) and the Launcher factory (+ its vault factory).
///         The deployer becomes the PriceRelay updater (our relayer).
contract Deploy is Script {
    function run() external {
        require(block.chainid == 97, "BSC Testnet only");
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(pk);
        PriceRelay relay = new PriceRelay(vm.addr(pk));
        StockDesk desk = new StockDesk(relay);
        KabalKultLauncherFactory lf = new KabalKultLauncherFactory(address(relay), address(desk));
        vm.stopBroadcast();

        console2.log("PriceRelay              ", address(relay));
        console2.log("StockDesk               ", address(desk));
        console2.log("MockNVDAb               ", address(desk.stock()));
        console2.log("KabalKultLauncherFactory", address(lf));
        console2.log("KabalKultVaultFactory   ", lf.vaultFactory());
    }
}
