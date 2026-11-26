// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {LibClone} from "solady/utils/LibClone.sol";
import {UpgradeableBeacon} from "solady/utils/UpgradeableBeacon.sol";
import {LauncherFactoryBase} from "src/flap/LauncherFactoryBase.sol";
import {LauncherDataSchema, FieldDescriptor} from "src/flap/IVaultSchemas.sol";
import {KabalKultLauncher, KabalKultConfig} from "./KabalKultLauncher.sol";
import {KabalKultVaultFactory} from "./KabalKultVaultFactory.sol";

/// @title KabalKultLauncherFactory
/// @notice Called by the Portal's `newLauncher`; deploys one `KabalKultLauncher` per deal.
///         Deploys its paired `KabalKultVaultFactory` itself, so every Launcher uses that vault factory.
///         Upgrades: Guardian only, through the beacon. No other privileged function.
contract KabalKultLauncherFactory is LauncherFactoryBase {
    address public immutable beacon;
    address public immutable vaultFactory;

    uint256 public constant MAX_NAMED_KOLS = 100;
    uint256 public constant MAX_CAMPAIGN_SLOTS = 99_999;
    uint256 public constant MAX_MILESTONES = 10;

    error InvalidData();
    error EmptyField();
    error InvalidMilestones();
    error InvalidKols();
    error InvalidTax();
    error InvalidPayout();

    event KabalKultLauncherCreated(address indexed launcher, address indexed creator, bytes32 launchSalt);
    event FlapLauncherImplementationUpgraded(address implementation);

    /// @dev The Launcher and Vault implementations are deployed first and passed in: together with this factory
    ///      they are over the 48 KB contract-creation limit.
    constructor(address relay, address desk, address router, address launcherImpl, address vaultImpl) {
        beacon = address(new UpgradeableBeacon(address(this), launcherImpl));
        vaultFactory = address(new KabalKultVaultFactory(address(this), relay, desk, router, vaultImpl));
    }

    function _newLauncher(address creator, bytes calldata data) internal override returns (address launcher) {
        // `abi.decode` ignores trailing bytes, so insist on the canonical encoding.
        KabalKultConfig memory c = abi.decode(data, (KabalKultConfig));
        if (keccak256(abi.encode(c)) != keccak256(data)) revert InvalidData();

        if (bytes(c.name).length == 0 || bytes(c.symbol).length == 0 || c.salt == bytes32(0) || c.poolQuote == 0) {
            revert EmptyField();
        }
        _checkMilestones(c.milestoneUsd, c.milestoneShareBps);
        // Somebody must be able to get paid, or the vault's BNB would never move.
        bool campaign = c.campaignRoot != bytes32(0) && c.campaignSlots > 0;
        if (c.namedKols.length > MAX_NAMED_KOLS || c.campaignSlots > MAX_CAMPAIGN_SLOTS || (c.namedKols.length == 0 && !campaign)) {
            revert InvalidKols();
        }
        // Flap's rule (same as its launch template): each side 0-10%, the higher side at least 1%.
        uint16 maxTax = c.buyTaxBps > c.sellTaxBps ? c.buyTaxBps : c.sellTaxBps;
        if (c.buyTaxBps > 1000 || c.sellTaxBps > 1000 || maxTax < 100) revert InvalidTax();
        if (c.payoutToken != address(0) && c.payoutToken.code.length == 0) revert InvalidPayout();

        launcher = LibClone.deployDeterministicERC1967BeaconProxy(beacon, c.salt);
        KabalKultLauncher(launcher).initialize{value: msg.value}(creator, vaultFactory, c);
        emit KabalKultLauncherCreated(launcher, creator, c.salt);
    }

    /// @dev 1..10 milestones, targets strictly rising, every share > 0, shares sum to 100%.
    function _checkMilestones(uint256[] memory usd, uint16[] memory shareBps) private pure {
        uint256 n = usd.length;
        if (n == 0 || n > MAX_MILESTONES || shareBps.length != n || usd[0] == 0) revert InvalidMilestones();
        uint256 sum;
        for (uint256 i; i < n; ++i) {
            if ((i > 0 && usd[i] <= usd[i - 1]) || shareBps[i] == 0) revert InvalidMilestones();
            sum += shareBps[i];
        }
        if (sum != 10_000) revert InvalidMilestones();
    }

    function upgradeVaultImplementation(address newImplementation) external override onlyGuardian {
        UpgradeableBeacon(beacon).upgradeTo(newImplementation);
        emit FlapLauncherImplementationUpgraded(newImplementation);
    }

    function launcherDataSchema() external pure override returns (LauncherDataSchema memory schema) {
        schema.description =
            "KabalKult: KOLs paid in tokenized stock, only if the meme performs. 100% of the creator-set tax goes to a vault that buys the payout token (mock stock, any token with a BNB pool, or BNB) at up to 10 USD market-cap milestones; named KOLs and campaign slot holders claim equal shares.";
        FieldDescriptor[] memory f = new FieldDescriptor[](13);
        f[0] = FieldDescriptor("name", "string", "Token name", 0);
        f[1] = FieldDescriptor("symbol", "string", "Token symbol", 0);
        f[2] = FieldDescriptor("meta", "string", "Metadata URI", 0);
        f[3] = FieldDescriptor("salt", "bytes32", "Vanity-mined launch salt (token ends in 7777)", 0);
        f[4] = FieldDescriptor("poolQuote", "uint256", "BNB seeded into the pool at launch", 18);
        f[5] = FieldDescriptor("namedKols", "address[]", "Named KOL wallets (max 100), always paid", 0);
        f[6] = FieldDescriptor("campaignRoot", "bytes32", "Merkle root of invited creators (0 = none)", 0);
        f[7] = FieldDescriptor("campaignSlots", "uint32", "Campaign slots, first come first served (0-99999)", 0);
        f[8] = FieldDescriptor("milestoneUsd", "uint256[]", "1-10 market-cap targets in USD, rising", 18);
        f[9] = FieldDescriptor("milestoneShareBps", "uint16[]", "Payout share per milestone in bps, sum 10000", 0);
        f[10] = FieldDescriptor("buyTaxBps", "uint16", "Buy tax in bps (0-1000)", 0);
        f[11] = FieldDescriptor("sellTaxBps", "uint16", "Sell tax in bps (0-1000; higher side >= 100)", 0);
        f[12] = FieldDescriptor("payoutToken", "address", "KOL payout token: mock stock, any token with a BNB pool, or 0x0 = BNB", 0);
        schema.fields = f;
    }
}
