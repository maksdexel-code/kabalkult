// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Initializable} from "@openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {Strings} from "@openzeppelin/utils/Strings.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {DirectLaunchVaultBase} from "src/flap/DirectLaunchVaultBase.sol";
import {VaultUISchema, VaultMethodSchema, FieldDescriptor} from "src/flap/IVaultSchemas.sol";
import {PriceRelay} from "./PriceRelay.sol";
import {StockDesk} from "./StockDesk.sol";

interface IKabalKultLauncher {
    function pool() external view returns (address);
    function milestoneUsd(uint256 id) external view returns (uint256);
    function kolList() external view returns (address[] memory);
}

interface IV2PairLike {
    function token0() external view returns (address);
    function getReserves() external view returns (uint112, uint112, uint32);
}

/// @title KabalKultVault
/// @notice Receives 100% of the token's tax in BNB. When the market cap reaches the next USD milestone,
///         anyone calls `checkMilestone()`: the vault buys mNVDAb with its BNB (milestone 1: half, milestone 2:
///         the rest) and splits it equally among the KOLs listed on the Launcher at that moment.
///
///         Market cap (USD) = pool BNB reserve / pool token reserve × total supply × BNB/USD (from PriceRelay).
/// @dev shortcut: spot pool price, so one big buy can trigger a milestone; a hold rule / TWAP is the upgrade.
///      Native BNB only. Deployed per launch as a beacon proxy by `KabalKultVaultFactory`.
contract KabalKultVault is DirectLaunchVaultBase, Initializable {
    using SafeTransferLib for address;
    using Strings for uint256;

    uint256 public constant MILESTONES = 2;

    address public token;
    IKabalKultLauncher public launcher;
    PriceRelay public relay;
    StockDesk public desk;

    uint256 public milestonesPaid;
    /// @notice BNB spent on stock so far.
    uint256 public totalSpent;
    /// @notice mNVDAb paid to each KOL so far.
    mapping(address => uint256) public earned;

    event MilestonePaid(
        uint256 indexed milestoneId, uint256 kolCount, uint256 stockAmount, uint256 usdValue, string priceSource
    );

    error AllPaid();
    error NotReached(uint256 marketCapUsd, uint256 targetUsd);
    error NoKols();
    error NothingToPay();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address token_, address launcher_, address relay_, address desk_) external initializer {
        token = token_;
        launcher = IKabalKultLauncher(launcher_);
        relay = PriceRelay(relay_);
        desk = StockDesk(desk_);
    }

    receive() external payable {}

    function version() external pure returns (string memory) {
        return "v1.0.0";
    }

    /// @notice Every BNB the vault ever received. Payouts move BNB from balance to totalSpent, so never count twice.
    function totalRevenue() public view returns (uint256) {
        return address(this).balance + totalSpent;
    }

    /// @notice Live market cap in USD (18 decimals). Reverts if the price is stale.
    function marketCapUsd() public view returns (uint256) {
        (uint256 bnbUsd,) = relay.fresh();
        return _marketCapUsd(bnbUsd);
    }

    function _marketCapUsd(uint256 bnbUsd) internal view returns (uint256) {
        IV2PairLike pair = IV2PairLike(launcher.pool());
        (uint256 r0, uint256 r1,) = pair.getReserves();
        (uint256 rToken, uint256 rBnb) = pair.token0() == token ? (r0, r1) : (r1, r0);
        return rBnb * IERC20(token).totalSupply() / rToken * bnbUsd / 1e18;
    }

    /// @notice Pay the next milestone if the market cap has reached it. Anyone can call.
    function checkMilestone() external {
        uint256 id = milestonesPaid;
        if (id == MILESTONES) revert AllPaid();
        (uint256 bnbUsd,) = relay.fresh();
        uint256 mc = _marketCapUsd(bnbUsd);
        uint256 target = launcher.milestoneUsd(id);
        if (mc < target) revert NotReached(mc, target);
        address[] memory kols = launcher.kolList();
        if (kols.length == 0) revert NoKols();
        uint256 bnb = id == 0 ? address(this).balance / 2 : address(this).balance;
        if (bnb == 0) revert NothingToPay();

        milestonesPaid = id + 1;
        totalSpent += bnb;
        uint256 stockAmount = desk.buy{value: bnb}();
        uint256 share = stockAmount / kols.length; // rounding dust stays in the vault
        address stock = address(desk.stock());
        for (uint256 i; i < kols.length; ++i) {
            earned[kols[i]] += share;
            stock.safeTransfer(kols[i], share);
        }
        emit MilestonePaid(id, kols.length, stockAmount, bnb * bnbUsd / 1e18, relay.source());
    }

    // ─────────────────────────────────────────────────────────────────────────
    // IDirectLaunchVault
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc DirectLaunchVaultBase
    function description() public view override returns (string memory) {
        return string.concat(
            "KabalKult vault (testnet, mock stock): receives 100% of the token tax in BNB. At milestone 1 (market cap $",
            (launcher.milestoneUsd(0) / 1e18).toString(),
            ") it buys mNVDAb with half its BNB, at milestone 2 ($",
            (launcher.milestoneUsd(1) / 1e18).toString(),
            ") with the rest, and splits the stock equally among the KOLs listed on launcher ",
            Strings.toHexString(address(launcher)),
            ". No fee, no creator share. Milestones paid: ",
            milestonesPaid.toString(),
            "/2. Revenue so far: ",
            totalRevenue().toString(),
            " wei."
        );
    }

    /// @inheritdoc DirectLaunchVaultBase
    function vaultUISchema() public pure override returns (VaultUISchema memory schema) {
        schema.vaultType = "KabalKultVault";
        schema.description =
            "KOL payout in tokenized stock at two USD market-cap milestones. Anyone can trigger a reached milestone.";
        schema.methods = new VaultMethodSchema[](5);

        schema.methods[0].name = "marketCapUsd";
        schema.methods[0].description = "Live market cap in USD.";
        schema.methods[0].outputs = new FieldDescriptor[](1);
        schema.methods[0].outputs[0] = FieldDescriptor("usd", "uint256", "Market cap in USD", 18);

        schema.methods[1].name = "milestonesPaid";
        schema.methods[1].description = "How many of the 2 milestones are paid.";
        schema.methods[1].outputs = new FieldDescriptor[](1);
        schema.methods[1].outputs[0] = FieldDescriptor("count", "uint256", "Milestones paid", 0);

        schema.methods[2].name = "earned";
        schema.methods[2].description = "mNVDAb a KOL has received.";
        schema.methods[2].inputs = new FieldDescriptor[](1);
        schema.methods[2].inputs[0] = FieldDescriptor("kol", "address", "KOL wallet", 0);
        schema.methods[2].outputs = new FieldDescriptor[](1);
        schema.methods[2].outputs[0] = FieldDescriptor("amount", "uint256", "mNVDAb received", 18);

        schema.methods[3].name = "totalRevenue";
        schema.methods[3].description = "BNB the vault has received so far.";
        schema.methods[3].outputs = new FieldDescriptor[](1);
        schema.methods[3].outputs[0] = FieldDescriptor("amount", "uint256", "Total BNB received", 18);

        schema.methods[4].name = "checkMilestone";
        schema.methods[4].description = "Pay the next milestone if the market cap has reached it.";
        schema.methods[4].isWriteMethod = true;
    }
}
