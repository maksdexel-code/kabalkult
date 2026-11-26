// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPortal, IPortalTypes} from "src/flap/IPortal.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {UpgradeableBeacon} from "solady/utils/UpgradeableBeacon.sol";
import {DirectLaunchVaultFactoryBase} from "src/flap/DirectLaunchVaultFactoryBase.sol";
import {Distribution} from "src/flap/Distribution.sol";
import {VaultDataSchema, FieldDescriptor, FactoryPolicy} from "src/flap/IVaultSchemas.sol";
import {KabalKultVault} from "./KabalKultVault.sol";

interface IKabalKultLauncherCheck {
    function launching() external view returns (bool);
}

/// @title KabalKultVaultFactory
/// @notice Vault factory paired with `KabalKultLauncherFactory`, which deploys it. Serves only Launchers that
///         factory created, while they are launching, so a vault always reads the right KOL list.
contract KabalKultVaultFactory is DirectLaunchVaultFactoryBase {
    address public immutable beacon;
    address public immutable launcherFactory;
    address public immutable relay;
    address public immutable desk;
    address public immutable router;

    error NotFromLauncherFactory(address launcher);
    error VaultDataLauncherMismatch(address expected, address got);
    error LauncherNotLaunching(address launcher);

    event FlapVaultImplementationUpgraded(address implementation);
    event KabalKultVaultCreated(address indexed vault, address indexed token, address indexed launcher);

    constructor(address launcherFactory_, address relay_, address desk_, address router_, address vaultImpl) {
        if (launcherFactory_ == address(0) || relay_ == address(0) || desk_ == address(0) || router_ == address(0)) {
            revert ZeroAddress();
        }
        launcherFactory = launcherFactory_;
        relay = relay_;
        desk = desk_;
        router = router_;
        beacon = address(new UpgradeableBeacon(address(this), vaultImpl));
    }

    /// @inheritdoc DirectLaunchVaultFactoryBase
    function newVault(address token, address creator, uint8 launchKind, bytes calldata launchParams)
        external
        override
        onlyHub
        returns (address vault)
    {
        // Native quote, exactly one VAULT slot naming us, no reserve routed here.
        (, Distribution memory d, bytes memory vaultData) = _validateLaunch(token, creator, launchKind, launchParams);
        _requireNoReserveDistribution(d);

        // `creator` is the launch caller: it must be one of our Launchers, mid-launch, naming itself.
        if (IPortal(_getHub()).getLauncher(creator).launcherFactory != launcherFactory) {
            revert NotFromLauncherFactory(creator);
        }
        if (vaultData.length != 32) revert InvalidVaultData();
        address named = abi.decode(vaultData, (address));
        if (named != creator) revert VaultDataLauncherMismatch(creator, named);
        if (!IKabalKultLauncherCheck(creator).launching()) revert LauncherNotLaunching(creator);

        vault = LibClone.deployDeterministicERC1967BeaconProxy(beacon, bytes32(uint256(uint160(token))));
        KabalKultVault(payable(vault)).initialize(token, creator, relay, desk, router);
        emit KabalKultVaultCreated(vault, token, creator);
    }

    /// @inheritdoc DirectLaunchVaultFactoryBase
    function isQuoteTokenSupported(address quoteToken) public pure override returns (bool) {
        return quoteToken == address(0);
    }

    /// @inheritdoc DirectLaunchVaultFactoryBase
    function vaultDataSchema() public pure override returns (VaultDataSchema memory schema) {
        schema.description = "KabalKult vault: set by the launching KabalKultLauncher, not by hand.";
        schema.fields = new FieldDescriptor[](1);
        schema.fields[0] = FieldDescriptor("launcher", "address", "The KabalKultLauncher that is launching", 0);
    }

    /// @inheritdoc DirectLaunchVaultFactoryBase
    function tokenCreationPolicies() public pure override returns (FactoryPolicy[] memory policies) {
        policies = new FactoryPolicy[](1);
        policies[0] = FactoryPolicy({
            target: "quoteToken", operator: "eq", value: abi.encode(address(0)), description: "Native BNB quote only."
        });
    }

    function upgradeVaultImplementation(address newImplementation) external override onlyGuardian {
        UpgradeableBeacon(beacon).upgradeTo(newImplementation);
        emit FlapVaultImplementationUpgraded(newImplementation);
    }
}
