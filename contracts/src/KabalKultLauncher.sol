// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPortalTypes, IPortal} from "src/flap/IPortal.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {MerkleProof} from "@openzeppelin/utils/cryptography/MerkleProof.sol";
import {LauncherBase} from "src/flap/LauncherBase.sol";
import {Distribution} from "src/flap/Distribution.sol";
import {LaunchExtensionHelper} from "src/flap/LaunchExtensionHelper.sol";
import {LaunchVaultAddresses} from "src/flap/LaunchVaultAddresses.sol";
import {LauncherDescription} from "src/flap/LauncherHelper.sol";

string constant KK_TITLE_EN = "KabalKult: KOLs paid in stock, only if the meme performs";
string constant KK_TITLE_ZH = unicode"KabalKult：只有 meme 表现达标，KOL 才获得股票报酬";
string constant KK_SUMMARY_EN =
    "100% of the 5% buy/sell tax collects in a vault. When the market cap reaches the creator's two USD milestones, the vault buys mNVDAb (testnet mock NVIDIA stock) and splits it equally among the listed KOLs: milestone 1 spends half the vault, milestone 2 the rest. KOLs get no meme bag to dump. Testnet only, unaudited.";
string constant KK_SUMMARY_ZH =
    unicode"5% 买卖税全部进入金库。市值达到创建者设定的两个美元里程碑时，金库购买 mNVDAb（测试网模拟英伟达股票）并平均分给名单上的 KOL：第一个里程碑使用金库一半资金，第二个使用剩余部分。KOL 不持有可抛售的 meme 代币。仅限测试网，未经审计。";

/// @notice Payload for `Portal.newLauncher(factory, abi.encode(KabalKultConfig))`.
/// @param salt          Launch salt, mined so the token address ends in `0x7777`.
/// @param poolQuote     BNB the creator seeds into the pool at `launch()` (the whole supply goes in the pool).
/// @param namedKols     KOLs set by the creator. Always paid; `confirm()` only adds a public badge.
/// @param campaignRoot  Merkle root of invited creators (OZ StandardMerkleTree, leaf = address). 0 = no campaign.
/// @param milestone1Usd First market-cap target, USD with 18 decimals.
/// @param milestone2Usd Second market-cap target, USD with 18 decimals. Must be above the first.
struct KabalKultConfig {
    string name;
    string symbol;
    string meta;
    bytes32 salt;
    uint256 poolQuote;
    address[] namedKols;
    bytes32 campaignRoot;
    uint256 milestone1Usd;
    uint256 milestone2Usd;
}

/// @title KabalKultLauncher
/// @notice Holds the deal between a meme creator and its KOLs, before and after the DEX launch:
///         - named KOLs (set at creation, always paid, optional `confirm()` badge);
///         - a campaign: invited wallets (Merkle allowlist) take one of 50 slots with `joinCampaign`,
///           open before and after the launch until full;
///         - two USD market-cap milestones, read by the paired `KabalKultVault` at payout.
///         The creator launches whenever they want; the launch never waits for confirms.
/// @dev Deployed by `KabalKultLauncherFactory` as an ERC1967 beacon proxy.
contract KabalKultLauncher is LauncherBase, Initializable {
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 ether;
    uint16 public constant TAX_BPS = 500;
    uint256 public constant MAX_CAMPAIGN_SLOTS = 50;

    address public creator;
    address public vaultFactory;
    bytes32 public launchSalt;
    uint256 public poolQuote;
    bytes32 public campaignRoot;
    uint256[2] public milestoneUsd;
    string public name;
    string public symbol;
    string public meta;

    /// @dev Named KOLs first, then campaign slot holders in join order.
    address[] internal kols;
    uint256 public campaignSlotsTaken;
    mapping(address => bool) public isKol;
    mapping(address => bool) public confirmed;

    bool public launched;
    /// @notice True only during the Portal launch call; the vault factory checks it.
    bool public launching;
    address public token;
    address public pool;

    event KolConfirmed(address indexed kol, bool campaignSlot);
    event Launched(address indexed token, address indexed pool);

    error InvalidConfig();
    error NotKol();
    error AlreadyConfirmed();
    error AlreadyKol();
    error CampaignFull();
    error NotInvited();
    error NotCreator();
    error AlreadyLaunched();
    error WrongValue();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address creator_, address vaultFactory_, KabalKultConfig calldata c)
        external
        payable
        initializer
    {
        creator = creator_;
        vaultFactory = vaultFactory_;
        launchSalt = c.salt;
        poolQuote = c.poolQuote;
        campaignRoot = c.campaignRoot;
        milestoneUsd = [c.milestone1Usd, c.milestone2Usd];
        name = c.name;
        symbol = c.symbol;
        meta = c.meta;
        for (uint256 i; i < c.namedKols.length; ++i) {
            address k = c.namedKols[i];
            if (k == address(0) || isKol[k]) revert InvalidConfig();
            isKol[k] = true;
            kols.push(k);
        }

        // The Launcher must lock the salt itself: the Portal records the caller as the locker.
        address hub = _getHub();
        uint256 fee = IPortal(hub).SALT_LOCK_FEE();
        if (msg.value != fee) revert InvalidConfig();
        IPortal(hub).lockSalt{value: fee}(c.salt, uint8(IPortalTypes.LaunchKind.DIRECT_V2_POOL_TAX));
    }

    function _getHub() internal view override returns (address) {
        return LaunchVaultAddresses.hub();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // KOLs
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice A named KOL publicly accepts the deal (badge only; named KOLs are paid either way).
    function confirm() external {
        if (!isKol[msg.sender]) revert NotKol();
        if (confirmed[msg.sender]) revert AlreadyConfirmed();
        confirmed[msg.sender] = true;
        emit KolConfirmed(msg.sender, false);
    }

    /// @notice An invited creator takes a campaign slot. First come, first served, until 50 are taken.
    function joinCampaign(bytes32[] calldata proof) external {
        if (isKol[msg.sender]) revert AlreadyKol();
        if (campaignSlotsTaken == MAX_CAMPAIGN_SLOTS) revert CampaignFull();
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(msg.sender))));
        if (!MerkleProof.verifyCalldata(proof, campaignRoot, leaf)) revert NotInvited();
        ++campaignSlotsTaken;
        isKol[msg.sender] = true;
        confirmed[msg.sender] = true;
        kols.push(msg.sender);
        emit KolConfirmed(msg.sender, true);
    }

    /// @notice Everyone the vault pays at the next milestone.
    function kolList() external view returns (address[] memory) {
        return kols;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Launch
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Creator seeds `poolQuote` BNB and launches the token, its pool and its vault in one call.
    function launch() external payable {
        if (msg.sender != creator) revert NotCreator();
        if (launched) revert AlreadyLaunched();
        if (msg.value != poolQuote) revert WrongValue();

        Distribution memory noReserve; // the whole supply goes into the pool
        IPortalTypes.CreatorBuyParams memory noBuy;
        launching = true;
        (address token_, address pool_) = IPortal(_getHub()).launchTaxTokenV2{value: msg.value}(_params(), noReserve, noBuy);
        launching = false;

        launched = true;
        token = token_;
        pool = pool_;
        emit Launched(token_, pool_);
    }

    function _params() private view returns (IPortalTypes.CreateTaxTokenParams memory p) {
        p.name = name;
        p.symbol = symbol;
        p.meta = meta;
        p.totalSupply = TOTAL_SUPPLY;
        p.salt = launchSalt;
        p.poolQuote = poolQuote;
        p.poolToken = TOTAL_SUPPLY;
        p.buyTaxRate = TAX_BPS;
        p.sellTaxRate = TAX_BPS;
        p.taxDuration = 30 days;
        p.antiFarmerDuration = 1 days;
        p.feeConfigs = new IPortalTypes.FeeConfig[](1);
        p.feeConfigs[0] = IPortalTypes.FeeConfig({
            feeType: IPortalTypes.FeeSlotType.VAULT,
            bps: 10_000,
            configData: abi.encode(IPortalTypes.FeeConfigVault({vaultFactory: vaultFactory, vaultData: abi.encode(address(this))}))
        });
        (p.extensionID, p.extensionData) = LaunchExtensionHelper.encodeCreator(creator);
    }

    /// @inheritdoc LauncherBase
    function _description() internal view override returns (LauncherDescription memory d) {
        d.name = name;
        d.symbol = symbol;
        d.targetRaise = poolQuote;
        d.poolTokenRatio = 1e18;
        d.titleZh = KK_TITLE_ZH;
        d.titleEn = KK_TITLE_EN;
        d.summaryZh = KK_SUMMARY_ZH;
        d.summaryEn = KK_SUMMARY_EN;
    }
}
