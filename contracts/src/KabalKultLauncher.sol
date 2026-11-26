// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPortalTypes, IPortal} from "src/flap/IPortal.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {LauncherBase} from "src/flap/LauncherBase.sol";
import {Distribution} from "src/flap/Distribution.sol";
import {LaunchExtensionHelper} from "src/flap/LaunchExtensionHelper.sol";
import {LaunchVaultAddresses} from "src/flap/LaunchVaultAddresses.sol";
import {LauncherDescription} from "src/flap/LauncherHelper.sol";
import {Strings} from "@openzeppelin/utils/Strings.sol";

/// @notice Flap's X Verifier (docs.flap.sh → Flap Infrastructures → X Verifier): an oracle-signed proof that an
///         X account posted a tweet containing `substring` (case-sensitive).
interface IXGeneralVerifier {
    struct XGeneralProof {
        uint128 tweetId;
        string xHandle; // always lowercase
        uint128 xId;
        string substring;
    }

    function verify(XGeneralProof calldata proof, bytes calldata signature) external view returns (bool);
}

string constant KK_TITLE_EN = "KabalKult: KOLs paid in stock, only if the meme performs";
string constant KK_TITLE_ZH = unicode"KabalKult：只有 meme 表现达标，KOL 才获得股票报酬";
string constant KK_SUMMARY_EN =
    "100% of the creator-set buy/sell tax collects in a vault. When the market cap reaches the creator's USD milestones, the vault buys the creator's payout token (a testnet mock stock such as mNVDAb, any token with a BNB pool, or plain BNB) and splits it equally among the listed KOLs: each of up to 10 milestones pays its creator-set share. KOLs claim their part. KOLs get no meme bag to dump. Testnet only, unaudited.";
string constant KK_SUMMARY_ZH =
    unicode"创建者设定的买卖税全部进入金库。市值达到创建者设定的美元里程碑时，金库购买创建者选择的支付代币（测试网模拟股票如 mNVDAb、任何有 BNB 池的代币，或 BNB）并平均分给名单上的 KOL：最多 10 个里程碑，每个支付创建者设定的比例，KOL 自行领取。KOL 不持有可抛售的 meme 代币。仅限测试网，未经审计。";

/// @notice Payload for `Portal.newLauncher(factory, abi.encode(KabalKultConfig))`.
/// @param salt          Launch salt, mined so the token address ends in `0x7777`.
/// @param poolQuote     BNB the creator seeds into the pool at `launch()` (the whole supply goes in the pool).
/// @param namedKols     KOLs set by the creator. Always paid; `confirm()` / `confirmWithX()` only add a badge.
/// @param invitees      Wallets invited to the campaign (stored on chain; the creator can add more later).
/// @param campaignSlots How many invited creators can join (first come, first served), 0..99,999.
/// @param milestoneUsd  1..10 market-cap targets, USD with 18 decimals, strictly rising.
/// @param milestoneShareBps Planned share of the payouts per milestone, in bps; each > 0, sum 10,000.
/// @param buyTaxBps     Buy tax in bps, 0..1000 (10%). The higher of buy/sell must be at least 100 (1%).
/// @param sellTaxBps    Sell tax in bps, 0..1000.
/// @param payoutToken   What KOLs are paid in: a StockDesk mock stock, any token with a BNB pool, or address(0) = BNB.
struct KabalKultConfig {
    string name;
    string symbol;
    string meta;
    bytes32 salt;
    uint256 poolQuote;
    address[] namedKols;
    address[] invitees;
    uint32 campaignSlots;
    uint256[] milestoneUsd;
    uint16[] milestoneShareBps;
    uint16 buyTaxBps;
    uint16 sellTaxBps;
    address payoutToken;
}

/// @title KabalKultLauncher
/// @notice Holds the deal between a meme creator and its KOLs, before and after the DEX launch:
///         - named KOLs (set at creation, always paid, optional `confirm()` badge);
///         - a campaign: invited wallets take one of `campaignSlots` slots with `joinCampaign()`, open before
///           and after the launch until full (no-argument actions, so they work as buttons on Flap's launch page);
///         - "proof of shill": any KOL can confirm with an X post, checked on chain by Flap's X Verifier;
///         - 1..10 USD market-cap milestones with payout shares, read by the paired `KabalKultVault`.
///         The creator launches whenever they want; the launch never waits for confirms.
/// @dev Deployed by `KabalKultLauncherFactory` as an ERC1967 beacon proxy.
contract KabalKultLauncher is LauncherBase, Initializable {
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 ether;
    /// @dev Flap's X Verifier on BSC Testnet (docs.flap.sh, Flap Infrastructures). Mainnet has its own address.
    IXGeneralVerifier public constant X_VERIFIER = IXGeneralVerifier(0x236C4AF8e0674fB22a139DDE4C2A518CBA819932);

    address public creator;
    address public vaultFactory;
    bytes32 public launchSalt;
    uint256 public poolQuote;
    uint32 public campaignSlots;
    uint256[] public milestoneUsd;
    uint16[] public milestoneShareBps;
    uint16 public buyTaxBps;
    uint16 public sellTaxBps;
    address public payoutToken;
    string public name;
    string public symbol;
    string public meta;

    /// @dev Named KOLs first, then campaign slot holders in join order.
    address[] internal kols;
    uint256 public campaignSlotsTaken;
    mapping(address => bool) public invited;
    uint256 public inviteCount;
    /// @notice Position in the KOL list + 1 (0 = not a KOL). The vault uses it to know which payouts a KOL shares.
    mapping(address => uint256) public kolNumber;
    mapping(address => bool) public confirmed;
    /// @notice X handle a KOL proved with a post (empty = not proved).
    mapping(address => string) public xHandle;

    bool public launched;
    /// @notice True only during the Portal launch call; the vault factory checks it.
    bool public launching;
    address public token;
    address public pool;
    /// @notice The vault Flap created at launch (pays the KOLs).
    address public vault;

    event KolConfirmed(address indexed kol, bool campaignSlot);
    event KolPostedOnX(address indexed kol, string xHandle, uint128 tweetId);
    event Invited(uint256 count);
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
    error WrongXPost();

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
        _invite(c.invitees);
        campaignSlots = c.campaignSlots;
        milestoneUsd = c.milestoneUsd;
        milestoneShareBps = c.milestoneShareBps;
        buyTaxBps = c.buyTaxBps;
        sellTaxBps = c.sellTaxBps;
        payoutToken = c.payoutToken;
        name = c.name;
        symbol = c.symbol;
        meta = c.meta;
        for (uint256 i; i < c.namedKols.length; ++i) {
            address k = c.namedKols[i];
            if (k == address(0) || kolNumber[k] != 0) revert InvalidConfig();
            kols.push(k);
            kolNumber[k] = kols.length;
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
        if (kolNumber[msg.sender] == 0) revert NotKol();
        if (confirmed[msg.sender]) revert AlreadyConfirmed();
        confirmed[msg.sender] = true;
        emit KolConfirmed(msg.sender, false);
    }

    /// @notice An invited creator takes a campaign slot. First come, first served, until all slots are taken.
    function joinCampaign() external {
        if (kolNumber[msg.sender] != 0) revert AlreadyKol();
        if (campaignSlotsTaken >= campaignSlots) revert CampaignFull();
        if (!invited[msg.sender]) revert NotInvited();
        ++campaignSlotsTaken;
        confirmed[msg.sender] = true;
        kols.push(msg.sender);
        kolNumber[msg.sender] = kols.length;
        emit KolConfirmed(msg.sender, true);
    }

    /// @notice The creator invites more wallets (before or after launch).
    function addInvites(address[] calldata wallets) external {
        if (msg.sender != creator) revert NotCreator();
        _invite(wallets);
    }

    function _invite(address[] memory wallets) private {
        for (uint256 i; i < wallets.length; ++i) {
            if (!invited[wallets[i]]) {
                invited[wallets[i]] = true;
                ++inviteCount;
            }
        }
        emit Invited(inviteCount);
    }

    /// @notice The text a KOL must post on X: it names this deal and the KOL's wallet, so a post can't be reused.
    function xPostText(address kol) public view returns (string memory) {
        return string.concat("kabalkult ", Strings.toHexString(address(this)), " ", Strings.toHexString(kol));
    }

    /// @notice "Proof of shill": a KOL proves an X post containing `xPostText(msg.sender)`. The proof and signature
    ///         come from Flap's X Verifier oracle (POST https://verifyx.taxed.fun/prove?chain_id=97).
    function confirmWithX(IXGeneralVerifier.XGeneralProof calldata proof, bytes calldata signature) external {
        if (kolNumber[msg.sender] == 0) revert NotKol();
        if (keccak256(bytes(proof.substring)) != keccak256(bytes(xPostText(msg.sender)))) revert WrongXPost();
        if (!X_VERIFIER.verify(proof, signature)) revert WrongXPost();
        confirmed[msg.sender] = true;
        xHandle[msg.sender] = proof.xHandle;
        emit KolPostedOnX(msg.sender, proof.xHandle, proof.tweetId);
    }

    function isKol(address a) external view returns (bool) {
        return kolNumber[a] != 0;
    }

    /// @notice Everyone on the deal, in join order (named KOLs first).
    function kolList() external view returns (address[] memory) {
        return kols;
    }

    function kolCount() external view returns (uint256) {
        return kols.length;
    }

    function milestoneCount() external view returns (uint256) {
        return milestoneUsd.length;
    }

    /// @notice All milestone targets (USD, 18 decimals) and their payout shares (bps).
    function milestones() external view returns (uint256[] memory usd, uint16[] memory shareBps) {
        return (milestoneUsd, milestoneShareBps);
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
        (vault,) = IPortal(_getHub()).getLaunchVault(token_);
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
        p.buyTaxRate = buyTaxBps;
        p.sellTaxRate = sellTaxBps;
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
