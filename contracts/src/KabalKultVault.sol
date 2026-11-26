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
    function milestoneShareBps(uint256 id) external view returns (uint16);
    function milestoneCount() external view returns (uint256);
    function kolCount() external view returns (uint256);
    function kolNumber(address kol) external view returns (uint256);
    function payoutToken() external view returns (address);
}

interface IV2PairLike {
    function token0() external view returns (address);
    function getReserves() external view returns (uint112, uint112, uint32);
}

interface IV2RouterLike {
    function WETH() external view returns (address);
    function swapExactETHForTokensSupportingFeeOnTransferTokens(uint256, address[] calldata, address, uint256)
        external
        payable;
}

/// @title KabalKultVault
/// @notice Receives 100% of the token's tax in BNB. When the market cap reaches the next USD milestone, anyone calls
///         `checkMilestone()`: the vault spends that milestone's share of its BNB on the creator's payout token and
///         books an equal share for every KOL on the Launcher's list at that moment. KOLs `claim` when they want.
///
///         - Shares: milestone i pays share[i] / (shares not yet paid) of the BNB on hand, so with no new tax the
///           payouts match the planned split exactly; tax arriving later flows to later milestones.
///         - Catch-up: a pump past several milestones pays them all in one payout.
///         - After the last milestone: new tax keeps paying KOLs, as long as the market cap stays above it.
///         - Payout token: a StockDesk mock stock (CMC price), any token with a BNB pool (DEX), or BNB. If the token
///           cannot be bought, that payout is in BNB instead, so the vault can never get stuck.
///         - Market cap (USD) = pool BNB reserve / pool token reserve × total supply × BNB/USD (PriceRelay).
/// @dev shortcut: spot pool price, so one big buy can trigger a milestone; a hold rule / TWAP is the upgrade.
///      Pull payments: a payout costs the same gas for 1 KOL or 99,999. Deployed per launch as a beacon proxy.
contract KabalKultVault is DirectLaunchVaultBase, Initializable, ReentrancyGuard {
    using SafeTransferLib for address;
    using Strings for uint256;

    address public token;
    IKabalKultLauncher public launcher;
    PriceRelay public relay;
    StockDesk public desk;
    IV2RouterLike public router;

    /// @notice Milestones paid so far (all of them = the vault is in "after the last milestone" mode).
    uint256 public milestonesPaid;
    /// @notice Sum of the shares (bps) of the milestones paid so far.
    uint256 public paidShareBps;
    /// @notice BNB allocated to payouts so far (spent on tokens, or booked as BNB for KOLs).
    uint256 public totalSpent;
    /// @notice BNB booked for KOLs and not claimed yet; not available for new payouts.
    uint256 public bnbOwed;

    /// @dev Per payout: KOL count at that moment, and running per-KOL totals (payout token, BNB, USD).
    ///      KOL number k (1-based join order) shares payout i iff kolCountAt[i] >= k; counts never go down.
    uint256[] public kolCountAt;
    uint256[] internal cumToken;
    uint256[] internal cumBnb;
    uint256[] internal cumUsd;
    mapping(address kol => uint256) public claimedToken;
    mapping(address kol => uint256) public claimedBnb;

    event Payout(
        uint256 indexed payoutId,
        uint256 milestonesPaid,
        uint256 kolCount,
        address paidToken,
        uint256 amount,
        uint256 usdValue,
        string priceSource
    );
    event Claimed(address indexed kol, address paidToken, uint256 tokenAmount, uint256 bnbAmount);

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
        return "v2.0.0";
    }

    /// @notice Every BNB the vault ever received (payouts and claims move BNB around, never count it twice).
    function totalRevenue() public view returns (uint256) {
        return address(this).balance + totalSpent - bnbOwed;
    }

    /// @notice BNB available for the next payout.
    function available() public view returns (uint256) {
        return address(this).balance - bnbOwed;
    }

    function payoutCount() external view returns (uint256) {
        return kolCountAt.length;
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

    /// @notice Pay every milestone the market cap has reached (or, after the last one, the new tax). Anyone can call.
    function checkMilestone() external nonReentrant {
        uint256 bnbUsd = relay.freshBnbUsd();
        uint256 mc = _marketCapUsd(bnbUsd);
        uint256 n = launcher.milestoneCount();
        uint256 id = milestonesPaid;
        uint256 target = launcher.milestoneUsd(id < n ? id : n - 1);
        if (mc < target) revert NotReached(mc, target);

        uint256 bnb = available();
        if (id < n) {
            uint256 reached;
            uint256 j = id;
            while (j < n && mc >= launcher.milestoneUsd(j)) {
                reached += launcher.milestoneShareBps(j);
                ++j;
            }
            if (j < n) bnb = bnb * reached / (10_000 - paidShareBps); // the last milestone takes everything
            milestonesPaid = j;
            paidShareBps += reached;
        }
        uint256 kols = launcher.kolCount();
        if (kols == 0) revert NoKols();
        if (bnb == 0) revert NothingToPay();
        totalSpent += bnb;

        address paid = launcher.payoutToken();
        uint256 amount = bnb;
        if (paid != address(0)) {
            // A token that cannot be bought must not lock the vault: pay this one in BNB instead.
            try this.buyPayoutToken(paid, bnb) returns (uint256 out) {
                amount = out;
            } catch {
                paid = address(0);
            }
        }
        if (paid == address(0)) bnbOwed += bnb;

        uint256 usd = bnb * bnbUsd / 1e18;
        uint256 k = kolCountAt.length;
        kolCountAt.push(kols);
        cumToken.push(_last(cumToken) + (paid == address(0) ? 0 : amount / kols)); // rounding dust stays here
        cumBnb.push(_last(cumBnb) + (paid == address(0) ? amount / kols : 0));
        cumUsd.push(_last(cumUsd) + usd / kols);
        emit Payout(k, milestonesPaid, kols, paid, amount, usd, relay.source());
    }

    /// @dev Self-call only, so `checkMilestone` can catch a failing purchase and fall back to BNB.
    function buyPayoutToken(address payToken, uint256 bnb) external returns (uint256) {
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
        return IERC20(payToken).balanceOf(address(this)) - before;
    }

    /// @notice Everything a KOL has earned so far: payout token, BNB (fallback or BNB payout), and USD at payout time.
    function earned(address kol) public view returns (uint256 tokenAmount, uint256 bnbAmount, uint256 usd) {
        uint256 len = kolCountAt.length;
        uint256 f = _firstPayoutFor(launcher.kolNumber(kol));
        if (f == len) return (0, 0, 0);
        tokenAmount = cumToken[len - 1] - (f == 0 ? 0 : cumToken[f - 1]);
        bnbAmount = cumBnb[len - 1] - (f == 0 ? 0 : cumBnb[f - 1]);
        usd = cumUsd[len - 1] - (f == 0 ? 0 : cumUsd[f - 1]);
    }

    /// @notice What a KOL can claim right now.
    function claimable(address kol) public view returns (uint256 tokenAmount, uint256 bnbAmount) {
        (uint256 t, uint256 b,) = earned(kol);
        return (t - claimedToken[kol], b - claimedBnb[kol]);
    }

    /// @notice Send a KOL everything they earned. Anyone can call; the funds only ever go to the KOL.
    function claim(address kol) external nonReentrant {
        (uint256 t, uint256 b) = claimable(kol);
        if (t == 0 && b == 0) revert NothingToPay();
        claimedToken[kol] += t;
        claimedBnb[kol] += b;
        bnbOwed -= b;
        address paid = launcher.payoutToken();
        if (t > 0) paid.safeTransfer(kol, t);
        if (b > 0) kol.forceSafeTransferETH(b);
        emit Claimed(kol, paid, t, b);
    }

    /// @dev First payout KOL number `k` shares (binary search; kolCountAt never goes down). len = none; k = 0 = none.
    function _firstPayoutFor(uint256 k) internal view returns (uint256 lo) {
        uint256 hi = kolCountAt.length;
        if (k == 0) return hi;
        while (lo < hi) {
            uint256 mid = (lo + hi) / 2;
            if (kolCountAt[mid] >= k) hi = mid;
            else lo = mid + 1;
        }
    }

    function _last(uint256[] storage a) private view returns (uint256) {
        return a.length == 0 ? 0 : a[a.length - 1];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // IDirectLaunchVault
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc DirectLaunchVaultBase
    function description() public view override returns (string memory) {
        return string.concat(
            "KabalKult vault (testnet): receives 100% of the token tax in BNB. At each of ",
            launcher.milestoneCount().toString(),
            " USD market-cap milestones (next: $",
            (launcher.milestoneUsd(milestonesPaid < launcher.milestoneCount() ? milestonesPaid : launcher.milestoneCount() - 1) / 1e18).toString(),
            ") it spends that milestone's share of its BNB on payout token ",
            Strings.toHexString(launcher.payoutToken()),
            " (0x0 = BNB); every KOL on launcher ",
            Strings.toHexString(address(launcher)),
            " claims an equal share. No fee, no creator share. Milestones paid: ",
            milestonesPaid.toString(),
            "/",
            launcher.milestoneCount().toString(),
            ". Revenue so far: ",
            totalRevenue().toString(),
            " wei."
        );
    }

    /// @inheritdoc DirectLaunchVaultBase
    function vaultUISchema() public pure override returns (VaultUISchema memory schema) {
        schema.vaultType = "KabalKultVault";
        schema.description =
            "KOL payout in tokenized stock (or any token, or BNB) at up to 10 USD market-cap milestones. Anyone can trigger a reached milestone; KOLs claim.";
        schema.methods = new VaultMethodSchema[](7);

        schema.methods[0].name = "marketCapUsd";
        schema.methods[0].description = "Live market cap in USD.";
        schema.methods[0].outputs = new FieldDescriptor[](1);
        schema.methods[0].outputs[0] = FieldDescriptor("usd", "uint256", "Market cap in USD", 18);

        schema.methods[1].name = "milestonesPaid";
        schema.methods[1].description = "How many milestones are paid.";
        schema.methods[1].outputs = new FieldDescriptor[](1);
        schema.methods[1].outputs[0] = FieldDescriptor("count", "uint256", "Milestones paid", 0);

        schema.methods[2].name = "earned";
        schema.methods[2].description = "Everything a KOL has earned: payout token, BNB, USD value.";
        schema.methods[2].inputs = new FieldDescriptor[](1);
        schema.methods[2].inputs[0] = FieldDescriptor("kol", "address", "KOL wallet", 0);
        schema.methods[2].outputs = new FieldDescriptor[](3);
        schema.methods[2].outputs[0] = FieldDescriptor("tokenAmount", "uint256", "Payout token earned", 18);
        schema.methods[2].outputs[1] = FieldDescriptor("bnbAmount", "uint256", "BNB earned", 18);
        schema.methods[2].outputs[2] = FieldDescriptor("usd", "uint256", "USD value at payout", 18);

        schema.methods[3].name = "totalRevenue";
        schema.methods[3].description = "BNB the vault has received so far.";
        schema.methods[3].outputs = new FieldDescriptor[](1);
        schema.methods[3].outputs[0] = FieldDescriptor("amount", "uint256", "Total BNB received", 18);

        schema.methods[4].name = "checkMilestone";
        schema.methods[4].description = "Pay every milestone the market cap has reached.";
        schema.methods[4].isWriteMethod = true;

        schema.methods[5].name = "claimable";
        schema.methods[5].description = "What a KOL can claim now.";
        schema.methods[5].inputs = new FieldDescriptor[](1);
        schema.methods[5].inputs[0] = FieldDescriptor("kol", "address", "KOL wallet", 0);
        schema.methods[5].outputs = new FieldDescriptor[](2);
        schema.methods[5].outputs[0] = FieldDescriptor("tokenAmount", "uint256", "Payout token", 18);
        schema.methods[5].outputs[1] = FieldDescriptor("bnbAmount", "uint256", "BNB", 18);

        schema.methods[6].name = "claim";
        schema.methods[6].description = "Send a KOL everything they earned (anyone can call; funds go to the KOL).";
        schema.methods[6].isWriteMethod = true;
        schema.methods[6].inputs = new FieldDescriptor[](1);
        schema.methods[6].inputs[0] = FieldDescriptor("kol", "address", "KOL wallet", 0);
    }
}
