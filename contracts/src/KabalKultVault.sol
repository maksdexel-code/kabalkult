// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Initializable} from "@openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {Strings} from "@openzeppelin/utils/Strings.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {DirectLaunchVaultBase} from "src/flap/DirectLaunchVaultBase.sol";
import {VaultUISchema, VaultMethodSchema, FieldDescriptor} from "src/flap/IVaultSchemas.sol";
import {PriceRelay} from "./PriceRelay.sol";
import {StockDesk} from "./StockDesk.sol";

interface IKabalKultLauncher {
    function pool() external view returns (address);
    function milestoneUsd(uint256 id) external view returns (uint256);
    function kolList() external view returns (address[] memory);
    function payoutToken() external view returns (address);
    function milestone1ShareBps() external view returns (uint16);
}

interface IV2RouterLike {
    function WETH() external view returns (address);
    function swapExactETHForTokensSupportingFeeOnTransferTokens(uint256, address[] calldata, address, uint256)
        external
        payable;
}

interface IV2PairLike {
    function token0() external view returns (address);
    function getReserves() external view returns (uint112, uint112, uint32);
}

/// @title KabalKultVault
/// @notice Receives 100% of the token's tax in BNB. When the market cap reaches the next USD milestone,
///         anyone calls `checkMilestone()`: the vault buys the creator's payout token with its BNB (milestone 1:
///         the creator-set share, milestone 2: the rest) and splits it equally among the KOLs listed on the
///         Launcher at that moment. Payout token: a StockDesk mock stock (bought at the CMC price), any token
///         with a BNB pool (bought on the DEX), or plain BNB. If the token cannot be bought or sent, that
///         milestone pays in BNB instead, so the vault can never get stuck.
///
///         Market cap (USD) = pool BNB reserve / pool token reserve × total supply × BNB/USD (from PriceRelay).
/// @dev shortcut: spot pool price, so one big buy can trigger a milestone; a hold rule / TWAP is the upgrade.
///      Native BNB only. Deployed per launch as a beacon proxy by `KabalKultVaultFactory`.
contract KabalKultVault is DirectLaunchVaultBase, Initializable, ReentrancyGuard {
    using SafeTransferLib for address;
    using Strings for uint256;

    uint256 public constant MILESTONES = 2;

    address public token;
    IKabalKultLauncher public launcher;
    PriceRelay public relay;
    StockDesk public desk;
    IV2RouterLike public router;

    uint256 public milestonesPaid;
    /// @notice BNB spent on payouts so far.
    uint256 public totalSpent;
    /// @notice Amount of each token (address(0) = BNB) paid to each KOL so far.
    mapping(address kol => mapping(address token => uint256)) public earned;
    /// @notice USD value of everything paid to each KOL, at the BNB price of each payout.
    mapping(address kol => uint256) public earnedUsd;

    event MilestonePaid(
        uint256 indexed milestoneId,
        uint256 kolCount,
        address paidToken,
        uint256 amount,
        uint256 usdValue,
        string priceSource
    );

    error AllPaid();
    error NotReached(uint256 marketCapUsd, uint256 targetUsd);
    error NoKols();
    error NothingToPay();
    error OnlySelf();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address token_, address launcher_, address relay_, address desk_, address router_)
        external
        initializer
    {
        token = token_;
        launcher = IKabalKultLauncher(launcher_);
        relay = PriceRelay(relay_);
        desk = StockDesk(desk_);
        router = IV2RouterLike(router_);
    }

    receive() external payable {}

    function version() external pure returns (string memory) {
        return "v1.1.0";
    }

    /// @notice Every BNB the vault ever received. Payouts move BNB from balance to totalSpent, so never count twice.
    function totalRevenue() public view returns (uint256) {
        return address(this).balance + totalSpent;
    }

    /// @notice Live market cap in USD (18 decimals). Reverts if the price is stale.
    function marketCapUsd() public view returns (uint256) {
        return _marketCapUsd(relay.freshBnbUsd());
    }

    function _marketCapUsd(uint256 bnbUsd) internal view returns (uint256) {
        IV2PairLike pair = IV2PairLike(launcher.pool());
        (uint256 r0, uint256 r1,) = pair.getReserves();
        (uint256 rToken, uint256 rBnb) = pair.token0() == token ? (r0, r1) : (r1, r0);
        return rBnb * IERC20(token).totalSupply() / rToken * bnbUsd / 1e18;
    }

    /// @notice Pay the next milestone if the market cap has reached it. Anyone can call.
    function checkMilestone() external nonReentrant {
        uint256 id = milestonesPaid;
        if (id == MILESTONES) revert AllPaid();
        uint256 bnbUsd = relay.freshBnbUsd();
        uint256 mc = _marketCapUsd(bnbUsd);
        uint256 target = launcher.milestoneUsd(id);
        if (mc < target) revert NotReached(mc, target);
        address[] memory kols = launcher.kolList();
        if (kols.length == 0) revert NoKols();
        uint256 bnb =
            id == 0 ? address(this).balance * launcher.milestone1ShareBps() / 10_000 : address(this).balance;
        if (bnb == 0) revert NothingToPay();

        milestonesPaid = id + 1;
        totalSpent += bnb;
        address paid = launcher.payoutToken();
        uint256 amount;
        if (paid != address(0)) {
            // A token that cannot be bought or sent must not lock the vault: pay this milestone in BNB instead.
            try this.payInToken(paid, bnb, kols) returns (uint256 out) {
                amount = out;
            } catch {
                paid = address(0);
            }
        }
        if (paid == address(0)) amount = _split(address(0), bnb, kols);

        uint256 usd = bnb * bnbUsd / 1e18;
        for (uint256 i; i < kols.length; ++i) {
            earnedUsd[kols[i]] += usd / kols.length;
        }
        emit MilestonePaid(id, kols.length, paid, amount, usd, relay.source());
    }

    /// @dev Self-call only, so `checkMilestone` can catch a failing token and fall back to BNB.
    function payInToken(address payToken, uint256 bnb, address[] calldata kols) external returns (uint256) {
        if (msg.sender != address(this)) revert OnlySelf();
        uint256 before = IERC20(payToken).balanceOf(address(this));
        if (desk.isStock(payToken)) {
            desk.buy{value: bnb}(payToken);
        } else {
            address[] memory path = new address[](2);
            path[0] = router.WETH();
            path[1] = payToken;
            // shortcut: no minimum output, so a sandwich trade can take value; on mainnet use an oracle/TWAP minimum.
            router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: bnb}(0, path, address(this), block.timestamp);
        }
        return _split(payToken, IERC20(payToken).balanceOf(address(this)) - before, kols);
    }

    /// @dev Equal shares; rounding dust stays in the vault.
    function _split(address payToken, uint256 amount, address[] memory kols) private returns (uint256) {
        uint256 share = amount / kols.length;
        for (uint256 i; i < kols.length; ++i) {
            earned[kols[i]][payToken] += share;
            if (payToken == address(0)) kols[i].forceSafeTransferETH(share);
            else payToken.safeTransfer(kols[i], share);
        }
        return amount;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // IDirectLaunchVault
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc DirectLaunchVaultBase
    function description() public view override returns (string memory) {
        return string.concat(
            "KabalKult vault (testnet): receives 100% of the token tax in BNB. At milestone 1 (market cap $",
            (launcher.milestoneUsd(0) / 1e18).toString(),
            ") it spends ",
            (uint256(launcher.milestone1ShareBps()) / 100).toString(),
            "% of its BNB, at milestone 2 ($",
            (launcher.milestoneUsd(1) / 1e18).toString(),
            ") the rest, on payout token ",
            Strings.toHexString(launcher.payoutToken()),
            " (0x0 = BNB) and splits it equally among the KOLs listed on launcher ",
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
            "KOL payout in tokenized stock (or any token, or BNB) at two USD market-cap milestones. Anyone can trigger a reached milestone.";
        schema.methods = new VaultMethodSchema[](6);

        schema.methods[0].name = "marketCapUsd";
        schema.methods[0].description = "Live market cap in USD.";
        schema.methods[0].outputs = new FieldDescriptor[](1);
        schema.methods[0].outputs[0] = FieldDescriptor("usd", "uint256", "Market cap in USD", 18);

        schema.methods[1].name = "milestonesPaid";
        schema.methods[1].description = "How many of the 2 milestones are paid.";
        schema.methods[1].outputs = new FieldDescriptor[](1);
        schema.methods[1].outputs[0] = FieldDescriptor("count", "uint256", "Milestones paid", 0);

        schema.methods[2].name = "earned";
        schema.methods[2].description = "Amount of a token a KOL has received (0x0 = BNB).";
        schema.methods[2].inputs = new FieldDescriptor[](2);
        schema.methods[2].inputs[0] = FieldDescriptor("kol", "address", "KOL wallet", 0);
        schema.methods[2].inputs[1] = FieldDescriptor("token", "address", "Payout token (0x0 = BNB)", 0);
        schema.methods[2].outputs = new FieldDescriptor[](1);
        schema.methods[2].outputs[0] = FieldDescriptor("amount", "uint256", "Amount received", 18);

        schema.methods[3].name = "totalRevenue";
        schema.methods[3].description = "BNB the vault has received so far.";
        schema.methods[3].outputs = new FieldDescriptor[](1);
        schema.methods[3].outputs[0] = FieldDescriptor("amount", "uint256", "Total BNB received", 18);

        schema.methods[4].name = "checkMilestone";
        schema.methods[4].description = "Pay the next milestone if the market cap has reached it.";
        schema.methods[4].isWriteMethod = true;

        schema.methods[5].name = "earnedUsd";
        schema.methods[5].description = "USD value a KOL has received, at the BNB price of each payout.";
        schema.methods[5].inputs = new FieldDescriptor[](1);
        schema.methods[5].inputs[0] = FieldDescriptor("kol", "address", "KOL wallet", 0);
        schema.methods[5].outputs = new FieldDescriptor[](1);
        schema.methods[5].outputs[0] = FieldDescriptor("usd", "uint256", "USD received", 18);
    }
}
