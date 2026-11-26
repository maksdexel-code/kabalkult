// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {UpgradeableBeacon} from "solady/utils/UpgradeableBeacon.sol";
import {IPortalTypes} from "src/flap/IPortal.sol";
import {Distribution} from "src/flap/Distribution.sol";
import {LauncherFactoryBase} from "src/flap/LauncherFactoryBase.sol";
import {DirectLaunchVaultFactoryBase} from "src/flap/DirectLaunchVaultFactoryBase.sol";
import {PriceRelay} from "src/PriceRelay.sol";
import {StockDesk} from "src/StockDesk.sol";
import {KabalKultLauncher, KabalKultConfig} from "src/KabalKultLauncher.sol";
import {KabalKultLauncherFactory} from "src/KabalKultLauncherFactory.sol";
import {KabalKultVault} from "src/KabalKultVault.sol";
import {KabalKultVaultFactory} from "src/KabalKultVaultFactory.sol";
import {ForkBase} from "test/ForkBase.sol";
import {ForkAddresses} from "test/ForkAddresses.sol";

/// @notice Full KabalKult flow on a fork of BNB Testnet's live Portal. Needs `BSC_TESTNET_RPC_URL`.
contract KabalKultForkTest is ForkBase {
    uint256 constant BNB_USD = 600e18;
    uint256 constant NVDA_USD = 180e18;
    uint256 constant POOL_QUOTE = 1.1 ether;
    uint256 constant LAUNCH_MC = POOL_QUOTE * BNB_USD / 1e18; // whole supply in the pool
    uint256 constant M1 = LAUNCH_MC * 13 / 10;
    uint256 constant M2 = LAUNCH_MC * 18 / 10;

    PriceRelay relay;
    StockDesk desk;
    IERC20 stock;
    KabalKultLauncherFactory lf;
    KabalKultVaultFactory vf;

    address kolA = address(uint160(0xC0DE1001));
    address kolB = address(uint160(0xC0DE1002));

    function _addrs() internal pure override returns (ForkAddresses.Addrs memory) {
        return ForkAddresses.bscTest();
    }

    // ─── setup helpers ───────────────────────────────────────────────────────

    function _deploy() internal {
        _unpause(); // match live testnet: creation open
        relay = new PriceRelay(address(this));
        _price(BNB_USD);
        desk = new StockDesk(relay);
        stock = IERC20(desk.stocks()[0]); // mNVDAb
        lf = new KabalKultLauncherFactory(address(relay), address(desk), v2Router);
        vf = KabalKultVaultFactory(lf.vaultFactory());
    }

    function _price(uint256 bnbUsd) internal {
        string[] memory t = new string[](3);
        (t[0], t[1], t[2]) = ("NVDA", "TSLA", "AAPL");
        uint256[] memory p = new uint256[](3);
        (p[0], p[1], p[2]) = (NVDA_USD, 400e18, 230e18);
        relay.update(bnbUsd, t, p, "test");
    }

    function _config(bytes32 seed) internal returns (KabalKultConfig memory c) {
        c.name = "KabalKult Test";
        c.symbol = "KKT";
        c.meta = "bafkreig4y5nwb4izyilbbmiydumvkld446d4k7j4ohg3x3q2lfel3fo4yq";
        c.salt = _mineSalt(seed);
        c.poolQuote = POOL_QUOTE;
        c.namedKols = new address[](2);
        c.namedKols[0] = kolA;
        c.namedKols[1] = kolB;
        c.campaignRoot = _root(_leaves());
        c.milestone1Usd = M1;
        c.milestone2Usd = M2;
        c.buyTaxBps = 500;
        c.sellTaxBps = 500;
        c.payoutToken = address(stock);
        c.milestone1ShareBps = 5000;
    }

    function _newKK(bytes32 seed) internal returns (KabalKultLauncher) {
        return _newKK(_config(seed));
    }

    function _newKK(KabalKultConfig memory c) internal returns (KabalKultLauncher) {
        return KabalKultLauncher(_newLauncher(address(lf), abi.encode(c)));
    }

    function _launch(KabalKultLauncher l) internal returns (KabalKultVault) {
        vm.prank(creator);
        l.launch{value: POOL_QUOTE}();
        (address v,) = portal.getLaunchVault(l.token());
        return KabalKultVault(payable(v));
    }

    /// @dev Launch, trade until tax reaches the vault, refresh the price (trading warps past MAX_AGE).
    function _launchAndEarn(bytes32 seed) internal returns (KabalKultLauncher l, KabalKultVault v) {
        return _launchAndEarn(_config(seed));
    }

    function _launchAndEarn(KabalKultConfig memory c) internal returns (KabalKultLauncher l, KabalKultVault v) {
        l = _newKK(c);
        v = _launch(l);
        _generateTaxAndDispatch(l.token());
        _price(BNB_USD);
        assertGt(address(v).balance, 0, "tax reached the vault");
    }

    // ─── Merkle helpers (OZ StandardMerkleTree leaf, sorted-pair hashing) ────

    function _guest(uint256 i) internal pure returns (address) {
        return address(uint160(0xC0DE2000 + i));
    }

    function _leaf(address a) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(a))));
    }

    function _leaves() internal pure returns (bytes32[] memory l) {
        l = new bytes32[](64);
        for (uint256 i; i < 64; ++i) {
            l[i] = _leaf(_guest(i));
        }
    }

    function _up(bytes32[] memory layer) internal pure returns (bytes32[] memory next) {
        next = new bytes32[](layer.length / 2);
        for (uint256 i; i < next.length; ++i) {
            (bytes32 a, bytes32 b) = (layer[2 * i], layer[2 * i + 1]);
            next[i] = a < b ? keccak256(abi.encode(a, b)) : keccak256(abi.encode(b, a));
        }
    }

    function _root(bytes32[] memory layer) internal pure returns (bytes32) {
        while (layer.length > 1) layer = _up(layer);
        return layer[0];
    }

    function _proof(uint256 idx) internal pure returns (bytes32[] memory p) {
        bytes32[] memory layer = _leaves();
        p = new bytes32[](6);
        for (uint256 k; layer.length > 1; ++k) {
            p[k] = layer[idx ^ 1];
            layer = _up(layer);
            idx /= 2;
        }
    }

    function _join(KabalKultLauncher l, uint256 i) internal {
        vm.prank(_guest(i));
        l.joinCampaign(_proof(i));
    }

    // ─── tests ───────────────────────────────────────────────────────────────

    function test_launchThroughOurFactory() public {
        _deploy();
        KabalKultLauncher l = _newKK("launch");
        assertEq(portal.getLauncher(address(l)).launcherFactory, address(lf), "Portal recorded our Launcher");
        _assertContains(l.description(), '"name":"KabalKult Test"', "launcher description");

        KabalKultVault v = _launch(l);
        (, address vfAddr) = portal.getLaunchVault(l.token());
        assertEq(vfAddr, address(vf), "vault came from our vault factory");
        assertEq(address(v.launcher()), address(l), "vault reads this launcher");
        assertEq(v.token(), l.token(), "vault knows the token");
        assertEq(uint16(uint160(l.token())), 0x7777, "vanity token address");
        assertApproxEqRel(v.marketCapUsd(), LAUNCH_MC, 0.01e18, "launch MC = poolQuote x BNB/USD");

        vm.prank(creator);
        vm.expectRevert(KabalKultLauncher.AlreadyLaunched.selector);
        l.launch{value: POOL_QUOTE}();
    }

    function test_milestoneNotReached_noPayout() public {
        _deploy();
        KabalKultVault v = _launch(_newKK("not-reached"));
        vm.deal(address(v), 1 ether); // money is there, the market cap is not

        vm.expectRevert(abi.encodeWithSelector(KabalKultVault.NotReached.selector, v.marketCapUsd(), M1));
        v.checkMilestone();
        assertEq(v.milestonesPaid(), 0);
        assertEq(stock.balanceOf(kolA) + stock.balanceOf(kolB), 0, "no KOL paid");
    }

    function test_reached_equalSplit_lateJoinerSharesLaterOnly() public {
        _deploy();
        (KabalKultLauncher l, KabalKultVault v) = _launchAndEarn("split");
        uint256 bal = address(v).balance;

        // Milestone 1: half the vault, split between the 2 named KOLs.
        v.checkMilestone();
        uint256 share1 = (bal / 2) * BNB_USD / NVDA_USD / 2;
        assertEq(stock.balanceOf(kolA), share1, "kolA M1");
        assertEq(stock.balanceOf(kolB), share1, "kolB M1");
        assertEq(v.earned(kolA, address(stock)), share1);
        assertEq(v.earnedUsd(kolA), (bal / 2) * BNB_USD / 1e18 / 2, "USD value at payout");

        // A campaign creator joins after the launch: shares milestone 2 only.
        _join(l, 0);
        uint256 rest = address(v).balance;
        assertEq(rest, bal - bal / 2);
        v.checkMilestone();
        uint256 share2 = rest * BNB_USD / NVDA_USD / 3;
        assertEq(stock.balanceOf(kolA), share1 + share2, "kolA M1+M2");
        assertEq(stock.balanceOf(kolB), share1 + share2, "kolB M1+M2");
        assertEq(stock.balanceOf(_guest(0)), share2, "late joiner M2 only");
        assertEq(address(v).balance, 0, "vault spent");
        assertEq(v.milestonesPaid(), 2);
    }

    function test_doublePayout_reverts() public {
        _deploy();
        (, KabalKultVault v) = _launchAndEarn("double");
        v.checkMilestone();

        // Price the market cap between M1 and M2: M1 must not pay again.
        uint256 between = BNB_USD * ((M1 + M2) / 2) / v.marketCapUsd();
        _price(between);
        vm.expectRevert(abi.encodeWithSelector(KabalKultVault.NotReached.selector, v.marketCapUsd(), M2));
        v.checkMilestone();
        assertEq(v.milestonesPaid(), 1);

        _price(BNB_USD);
        v.checkMilestone();
        vm.expectRevert(KabalKultVault.AllPaid.selector);
        v.checkMilestone();
    }

    function test_stalePrice_reverts() public {
        _deploy();
        (, KabalKultVault v) = _launchAndEarn("stale");
        uint256 at = relay.updatedAt();
        vm.warp(block.timestamp + relay.MAX_AGE() + 1);
        vm.expectRevert(abi.encodeWithSelector(PriceRelay.StalePrice.selector, at));
        v.checkMilestone();
    }

    function test_revenueCreditedOnce() public {
        _deploy();
        (, KabalKultVault v) = _launchAndEarn("revenue");
        uint256 rev = v.totalRevenue();
        assertEq(rev, address(v).balance);

        v.checkMilestone();
        assertEq(v.totalRevenue(), rev, "a payout is not new revenue");
        assertEq(v.totalSpent(), rev / 2);

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(v).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(v.totalRevenue(), rev + 1 ether, "new BNB counted exactly once");
    }

    function test_newVault_onlyHub() public {
        _deploy();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(DirectLaunchVaultFactoryBase.NotHub.selector, alice));
        vf.newVault(address(0x7777), alice, 0, "");
    }

    function test_strangerLauncherRefused() public {
        _deploy();
        IPortalTypes.FeeConfig[] memory fees = new IPortalTypes.FeeConfig[](1);
        fees[0] = IPortalTypes.FeeConfig({
            feeType: IPortalTypes.FeeSlotType.VAULT,
            bps: 10_000,
            configData: abi.encode(IPortalTypes.FeeConfigVault({vaultFactory: address(vf), vaultData: abi.encode(creator)}))
        });
        IPortalTypes.CreateTaxTokenParams memory p;
        p.name = "Stranger";
        p.symbol = "STR";
        p.meta = "bafkreig4y5nwb4izyilbbmiydumvkld446d4k7j4ohg3x3q2lfel3fo4yq";
        p.totalSupply = 1_000_000_000 ether;
        p.salt = _mineSalt("stranger");
        p.poolQuote = POOL_QUOTE;
        p.poolToken = p.totalSupply;
        p.buyTaxRate = 500;
        p.sellTaxRate = 500;
        p.taxDuration = 30 days;
        p.antiFarmerDuration = 1 days;
        p.feeConfigs = fees;
        Distribution memory d;
        IPortalTypes.CreatorBuyParams memory noBuy;

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(KabalKultVaultFactory.NotFromLauncherFactory.selector, creator));
        portal.launchTaxTokenV2{value: POOL_QUOTE}(p, d, noBuy);
    }

    function test_guardianOnlyUpgrade() public {
        _deploy();
        address newLauncherImpl = address(new KabalKultLauncher());
        address newVaultImpl = address(new KabalKultVault());

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(LauncherFactoryBase.NotGuardian.selector, alice));
        lf.upgradeVaultImplementation(newLauncherImpl);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(DirectLaunchVaultFactoryBase.NotGuardian.selector, alice));
        vf.upgradeVaultImplementation(newVaultImpl);

        vm.startPrank(guardian);
        lf.upgradeVaultImplementation(newLauncherImpl);
        vf.upgradeVaultImplementation(newVaultImpl);
        vm.stopPrank();
        assertEq(UpgradeableBeacon(lf.beacon()).implementation(), newLauncherImpl);
        assertEq(UpgradeableBeacon(vf.beacon()).implementation(), newVaultImpl);
    }

    function test_campaign_slotCap_invalidProof_and52KolPayout() public {
        _deploy();
        KabalKultLauncher l = _newKK("campaign");

        vm.prank(alice); // not invited
        vm.expectRevert(KabalKultLauncher.NotInvited.selector);
        l.joinCampaign(_proof(0));
        vm.prank(_guest(0)); // invited, but someone else's proof
        vm.expectRevert(KabalKultLauncher.NotInvited.selector);
        l.joinCampaign(_proof(1));

        for (uint256 i; i < 25; ++i) _join(l, i); // before launch
        KabalKultVault v = _launch(l);
        for (uint256 i = 25; i < 50; ++i) _join(l, i); // after launch

        vm.prank(_guest(50));
        vm.expectRevert(KabalKultLauncher.CampaignFull.selector);
        l.joinCampaign(_proof(50));
        vm.prank(_guest(0));
        vm.expectRevert(KabalKultLauncher.AlreadyKol.selector);
        l.joinCampaign(_proof(0));
        assertEq(l.campaignSlotsTaken(), 50);
        assertEq(l.kolList().length, 52);
        assertTrue(l.confirmed(_guest(49)));

        // The largest possible payout (2 named + 50 slots) fits easily in a block.
        _generateTaxAndDispatch(l.token());
        _price(BNB_USD);
        uint256 g = gasleft();
        v.checkMilestone();
        emit log_named_uint("gas for a 52-KOL payout", g - gasleft());
        assertGt(stock.balanceOf(_guest(49)), 0);
    }

    function test_namedKolConfirmBadge() public {
        _deploy();
        KabalKultLauncher l = _newKK("confirm");
        assertFalse(l.confirmed(kolA));
        vm.prank(kolA);
        l.confirm();
        assertTrue(l.confirmed(kolA));
        assertFalse(l.confirmed(kolB), "unconfirmed named KOL is still listed");
        assertTrue(l.isKol(kolB));

        vm.prank(kolA);
        vm.expectRevert(KabalKultLauncher.AlreadyConfirmed.selector);
        l.confirm();
        vm.prank(alice);
        vm.expectRevert(KabalKultLauncher.NotKol.selector);
        l.confirm();
    }

    function test_factoryRejectsBadConfig() public {
        _deploy();
        uint256 fee = portal.SALT_LOCK_FEE();

        KabalKultConfig memory c = _config("bad-ms");
        c.milestone2Usd = c.milestone1Usd;
        vm.prank(creator);
        vm.expectRevert(KabalKultLauncherFactory.InvalidMilestones.selector);
        portal.newLauncher{value: fee}(address(lf), abi.encode(c));

        c = _config("bad-kols");
        c.namedKols = new address[](0);
        c.campaignRoot = bytes32(0);
        vm.prank(creator);
        vm.expectRevert(KabalKultLauncherFactory.InvalidKols.selector);
        portal.newLauncher{value: fee}(address(lf), abi.encode(c));

        c = _config("dup-kol");
        c.namedKols[1] = kolA;
        vm.prank(creator);
        vm.expectRevert(KabalKultLauncher.InvalidConfig.selector);
        portal.newLauncher{value: fee}(address(lf), abi.encode(c));
    }

    // ─── creator options: tax, payout token, split ───────────────────────────

    function test_customTaxAndSplit() public {
        _deploy();
        KabalKultConfig memory c = _config("tax-split");
        (c.buyTaxBps, c.sellTaxBps, c.milestone1ShareBps) = (0, 300, 3000); // sell-only tax, M1 spends 30%
        (KabalKultLauncher l, KabalKultVault v) = _launchAndEarn(c);
        assertEq(l.buyTaxBps(), 0);
        assertEq(l.sellTaxBps(), 300);
        uint256 bal = address(v).balance;
        v.checkMilestone();
        assertEq(v.totalSpent(), bal * 3000 / 10_000, "M1 spends the creator's share");
        assertEq(stock.balanceOf(kolA), (bal * 3000 / 10_000) * BNB_USD / NVDA_USD / 2);
        v.checkMilestone();
        assertEq(address(v).balance, 0, "M2 spends the rest");
    }

    function test_maxTaxLaunches() public {
        _deploy();
        KabalKultConfig memory c = _config("tax-max");
        (c.buyTaxBps, c.sellTaxBps) = (1000, 1000);
        _launchAndEarn(c);
    }

    function test_payoutInBnb() public {
        _deploy();
        KabalKultConfig memory c = _config("bnb");
        c.payoutToken = address(0);
        (, KabalKultVault v) = _launchAndEarn(c);
        uint256 bal = address(v).balance;
        uint256 a0 = kolA.balance;
        v.checkMilestone();
        assertEq(kolA.balance - a0, bal / 2 / 2, "kolA got BNB");
        assertEq(v.earned(kolA, address(0)), bal / 2 / 2);
    }

    function test_payoutInAnyPooledToken() public {
        _deploy();
        // Any token with a BNB pool works: here another meme launched through Flap a moment ago.
        address other = _launch(_newKK("other")).token();
        vm.warp(block.timestamp + 601);
        KabalKultConfig memory c = _config("any-token");
        c.payoutToken = other;
        (, KabalKultVault v) = _launchAndEarn(c);
        v.checkMilestone();
        assertGt(IERC20(other).balanceOf(kolA), 0, "kolA got the chosen token");
        assertEq(v.earned(kolA, other), IERC20(other).balanceOf(kolA));
        assertEq(v.earned(kolA, address(0)), 0, "no BNB fallback needed");
    }

    function test_unbuyableTokenFallsBackToBnb() public {
        _deploy();
        KabalKultConfig memory c = _config("fallback");
        c.payoutToken = address(relay); // has code, but is not a token and has no pool
        (, KabalKultVault v) = _launchAndEarn(c);
        uint256 bal = address(v).balance;
        v.checkMilestone();
        assertEq(v.milestonesPaid(), 1, "the milestone still pays");
        assertEq(kolA.balance, bal / 2 / 2, "paid in BNB instead");
        assertEq(v.earned(kolA, address(0)), bal / 2 / 2);
    }

    function test_factoryRejectsBadOptions() public {
        _deploy();
        KabalKultConfig memory c = _config("opts");
        c.buyTaxBps = 1001;
        _expectNewLauncherRevert(c, KabalKultLauncherFactory.InvalidTax.selector);
        (c.buyTaxBps, c.sellTaxBps) = (50, 99); // higher side under 1%
        _expectNewLauncherRevert(c, KabalKultLauncherFactory.InvalidTax.selector);
        (c.buyTaxBps, c.sellTaxBps) = (500, 500);
        c.milestone1ShareBps = 0;
        _expectNewLauncherRevert(c, KabalKultLauncherFactory.InvalidPayout.selector);
        c.milestone1ShareBps = 10_000;
        _expectNewLauncherRevert(c, KabalKultLauncherFactory.InvalidPayout.selector);
        c.milestone1ShareBps = 5000;
        c.payoutToken = alice; // a wallet, not a token
        _expectNewLauncherRevert(c, KabalKultLauncherFactory.InvalidPayout.selector);
    }

    function _expectNewLauncherRevert(KabalKultConfig memory c, bytes4 sel) internal {
        uint256 fee = portal.SALT_LOCK_FEE();
        vm.prank(creator);
        vm.expectRevert(sel);
        portal.newLauncher{value: fee}(address(lf), abi.encode(c));
    }
}
