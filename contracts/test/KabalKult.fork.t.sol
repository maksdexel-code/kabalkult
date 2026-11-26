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
import {KabalKultLauncher, KabalKultConfig, IXGeneralVerifier} from "src/KabalKultLauncher.sol";
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
        lf = new KabalKultLauncherFactory(
            address(relay), address(desk), v2Router, address(new KabalKultLauncher()), address(new KabalKultVault())
        );
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
        c.invitees = _guests(64);
        c.campaignSlots = 50;
        c.milestoneUsd = new uint256[](2);
        (c.milestoneUsd[0], c.milestoneUsd[1]) = (M1, M2);
        c.milestoneShareBps = new uint16[](2);
        (c.milestoneShareBps[0], c.milestoneShareBps[1]) = (5000, 5000);
        c.buyTaxBps = 500;
        c.sellTaxBps = 500;
        c.payoutToken = address(stock);
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

    // ─── campaign helpers ────────────────────────────────────────────────────

    function _guest(uint256 i) internal pure returns (address) {
        return address(uint160(0xC0DE2000 + i));
    }

    function _guests(uint256 n) internal pure returns (address[] memory g) {
        g = new address[](n);
        for (uint256 i; i < n; ++i) g[i] = _guest(i);
    }

    function _join(KabalKultLauncher l, uint256 i) internal {
        vm.prank(_guest(i));
        l.joinCampaign();
    }

    function _claimAll(KabalKultLauncher l, KabalKultVault v) internal {
        address[] memory k = l.kolList();
        for (uint256 i; i < k.length; ++i) {
            (uint256 t, uint256 b) = v.claimable(k[i]);
            if (t + b > 0) v.claim(k[i]);
        }
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
        _assertContains(v.description(), "Milestones paid: 0/2", "vault description");
        assertEq(l.vault(), address(v), "launcher knows its vault");

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
        assertEq(v.payoutCount(), 0, "nothing booked");
    }

    function test_reached_equalSplit_lateJoinerSharesLaterOnly() public {
        _deploy();
        (KabalKultLauncher l, KabalKultVault v) = _launchAndEarn("split");
        uint256 bal = address(v).balance;

        // Price between M1 and M2: only milestone 1 pays, half the vault, booked for the 2 named KOLs.
        _price(BNB_USD * ((M1 + M2) / 2) / v.marketCapUsd());
        uint256 bnbUsd1 = relay.bnbUsd();
        v.checkMilestone();
        assertEq(v.milestonesPaid(), 1);
        uint256 share1 = (bal / 2) * bnbUsd1 / NVDA_USD / 2;
        (uint256 t,,) = v.earned(kolA);
        assertEq(t, share1, "kolA M1 booked");
        assertEq(stock.balanceOf(kolA), 0, "pull: nothing sent before claim");
        v.claim(kolA);
        assertEq(stock.balanceOf(kolA), share1, "kolA claimed M1");

        // A campaign creator joins after the launch: shares milestone 2 only.
        _join(l, 0);
        (uint256 gt, uint256 gb) = v.claimable(_guest(0));
        assertEq(gt + gb, 0, "joiner has nothing from M1");
        _price(BNB_USD);
        uint256 rest = address(v).balance;
        assertEq(rest, bal - bal / 2);
        v.checkMilestone();
        uint256 share2 = rest * BNB_USD / NVDA_USD / 3;
        _claimAll(l, v);
        assertEq(stock.balanceOf(kolA), share1 + share2, "kolA M1+M2");
        assertEq(stock.balanceOf(kolB), share1 + share2, "kolB M1+M2");
        assertEq(stock.balanceOf(_guest(0)), share2, "late joiner M2 only");
        (,, uint256 usdA) = v.earned(kolA);
        assertEq(usdA, (bal / 2) * bnbUsd1 / 1e18 / 2 + rest * BNB_USD / 1e18 / 3, "USD value at payout");
        assertEq(address(v).balance, 0, "vault spent");
        assertEq(v.milestonesPaid(), 2);
    }

    function test_tenMilestones_catchUpPaysSeveralAtOnce() public {
        _deploy();
        KabalKultConfig memory c = _config("ten");
        c.milestoneUsd = new uint256[](10);
        c.milestoneShareBps = new uint16[](10);
        for (uint256 i; i < 10; ++i) {
            c.milestoneUsd[i] = LAUNCH_MC * (11 + i) / 10; // 1.1x .. 2.0x
            c.milestoneShareBps[i] = 1000;
        }
        (, KabalKultVault v) = _launchAndEarn(c);
        uint256 bal = address(v).balance;
        _price(BNB_USD * (LAUNCH_MC * 145 / 100) / v.marketCapUsd()); // a pump to 1.45x: milestones 1-4 reached
        uint256 reached = 4;

        v.checkMilestone();
        assertEq(v.milestonesPaid(), reached, "all reached milestones paid in one call");
        assertEq(v.payoutCount(), 1, "as one payout");
        assertEq(v.totalSpent(), bal * reached * 1000 / 10_000, "their combined share");
        vm.expectRevert(); // nothing new reached
        v.checkMilestone();
    }

    function test_afterLastMilestone_newTaxKeepsPayingKols() public {
        _deploy();
        (KabalKultLauncher l, KabalKultVault v) = _launchAndEarn("overtime");
        v.checkMilestone(); // trading pumped past both milestones: one payout, everything
        assertEq(v.milestonesPaid(), 2);
        assertEq(v.available(), 0);

        vm.deal(address(v), address(v).balance + 0.01 ether); // new tax arrives
        v.checkMilestone();
        assertEq(v.payoutCount(), 2, "new tax paid out");
        _claimAll(l, v);
        assertGt(stock.balanceOf(kolA), 0);

        // Below the last milestone: new tax waits.
        vm.deal(address(v), address(v).balance + 0.01 ether);
        _price(BNB_USD * (M2 - 1) / v.marketCapUsd());
        vm.expectRevert(abi.encodeWithSelector(KabalKultVault.NotReached.selector, v.marketCapUsd(), M2));
        v.checkMilestone();
    }

    function test_doublePayout_reverts() public {
        _deploy();
        (, KabalKultVault v) = _launchAndEarn("double");
        _price(BNB_USD * ((M1 + M2) / 2) / v.marketCapUsd());
        v.checkMilestone();
        vm.expectRevert(abi.encodeWithSelector(KabalKultVault.NotReached.selector, v.marketCapUsd(), M2));
        v.checkMilestone();
        assertEq(v.milestonesPaid(), 1);

        _price(BNB_USD);
        v.checkMilestone();
        vm.expectRevert(KabalKultVault.NothingToPay.selector); // all paid, no new tax
        v.checkMilestone();
        address k = kolA;
        v.claim(k);
        vm.expectRevert(KabalKultVault.NothingToPay.selector);
        v.claim(k);
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
        KabalKultConfig memory c = _config("revenue");
        c.payoutToken = address(0); // BNB payouts stay in the vault until claimed: must not count twice
        (KabalKultLauncher l, KabalKultVault v) = _launchAndEarn(c);
        uint256 rev = v.totalRevenue();
        assertEq(rev, address(v).balance);

        v.checkMilestone();
        assertEq(v.totalRevenue(), rev, "a payout is not new revenue");
        _claimAll(l, v);
        assertEq(v.totalRevenue(), rev, "a claim is not new revenue");

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(v).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(v.totalRevenue(), rev + 1 ether, "new BNB counted exactly once");
        assertEq(v.available(), 1 ether + address(v).balance - 1 ether - v.bnbOwed());
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

    function test_campaign_slotKnob_invalidProof_and52Kols() public {
        _deploy();
        KabalKultLauncher l = _newKK("campaign");

        vm.prank(alice); // not invited
        vm.expectRevert(KabalKultLauncher.NotInvited.selector);
        l.joinCampaign();
        assertEq(l.inviteCount(), 64);

        for (uint256 i; i < 25; ++i) _join(l, i); // before launch
        KabalKultVault v = _launch(l);
        for (uint256 i = 25; i < 50; ++i) _join(l, i); // after launch

        vm.prank(_guest(50));
        vm.expectRevert(KabalKultLauncher.CampaignFull.selector);
        l.joinCampaign();
        vm.prank(_guest(0));
        vm.expectRevert(KabalKultLauncher.AlreadyKol.selector);
        l.joinCampaign();
        assertEq(l.campaignSlotsTaken(), 50);
        assertEq(l.kolCount(), 52);
        assertTrue(l.confirmed(_guest(49)));

        // Pull payments: the payout costs the same for 52 KOLs as for 1.
        _generateTaxAndDispatch(l.token());
        _price(BNB_USD);
        uint256 g = gasleft();
        v.checkMilestone();
        emit log_named_uint("gas for a 52-KOL payout", g - gasleft());
        assertLt(g - gasleft(), 600_000);
        v.claim(_guest(49));
        assertGt(stock.balanceOf(_guest(49)), 0);
    }

    function test_campaignSlotsCreatorChoice() public {
        _deploy();
        KabalKultConfig memory c = _config("slots");
        c.campaignSlots = 2;
        KabalKultLauncher l = _newKK(c);
        _join(l, 0);
        _join(l, 1);
        vm.prank(_guest(2));
        vm.expectRevert(KabalKultLauncher.CampaignFull.selector);
        l.joinCampaign();
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

    function test_confirmWithX_proofOfShill() public {
        _deploy();
        KabalKultLauncher l = _newKK("x");
        IXGeneralVerifier.XGeneralProof memory p =
            IXGeneralVerifier.XGeneralProof({tweetId: 1, xHandle: "kol_b", xId: 7, substring: l.xPostText(kolB)});
        bytes memory sig = hex"01";
        address verifier = address(l.X_VERIFIER());
        assertGt(verifier.code.length, 0, "Flap X Verifier is live on testnet");
        vm.mockCall(verifier, abi.encodeWithSelector(IXGeneralVerifier.verify.selector, p, sig), abi.encode(true));

        vm.prank(alice); // not a KOL
        vm.expectRevert(KabalKultLauncher.NotKol.selector);
        l.confirmWithX(p, sig);
        vm.prank(kolA); // kolB's post can't confirm kolA
        vm.expectRevert(KabalKultLauncher.WrongXPost.selector);
        l.confirmWithX(p, sig);

        vm.prank(kolB);
        l.confirmWithX(p, sig);
        assertTrue(l.confirmed(kolB));
        assertEq(l.xHandle(kolB), "kol_b");
        _assertContains(l.xPostText(kolB), "kabalkult 0x", "post text");

        vm.clearMockedCalls();
        vm.mockCall(verifier, abi.encodeWithSelector(IXGeneralVerifier.verify.selector), abi.encode(false));
        vm.prank(kolB); // oracle says no
        vm.expectRevert(KabalKultLauncher.WrongXPost.selector);
        l.confirmWithX(p, sig);
    }

    function test_factoryRejectsBadConfig() public {
        _deploy();
        KabalKultConfig memory c = _config("bad");
        c.milestoneUsd[1] = c.milestoneUsd[0]; // not rising
        _expectNewLauncherRevert(c, KabalKultLauncherFactory.InvalidMilestones.selector);
        c = _config("bad");
        c.milestoneShareBps[1] = 4999; // shares don't add up to 100%
        _expectNewLauncherRevert(c, KabalKultLauncherFactory.InvalidMilestones.selector);
        c = _config("bad");
        c.milestoneUsd = new uint256[](11);
        c.milestoneShareBps = new uint16[](11);
        for (uint256 i; i < 11; ++i) (c.milestoneUsd[i], c.milestoneShareBps[i]) = (M1 + i, i == 0 ? 10_000 - 10 : 1);
        _expectNewLauncherRevert(c, KabalKultLauncherFactory.InvalidMilestones.selector); // max 10
        c = _config("bad");
        c.milestoneShareBps[0] = 0;
        c.milestoneShareBps[1] = 10_000;
        _expectNewLauncherRevert(c, KabalKultLauncherFactory.InvalidMilestones.selector); // every share > 0

        c = _config("bad");
        c.namedKols = new address[](0);
        c.campaignSlots = 0; // a campaign with no slots pays nobody
        _expectNewLauncherRevert(c, KabalKultLauncherFactory.InvalidKols.selector);
        c.campaignSlots = 100_000;
        _expectNewLauncherRevert(c, KabalKultLauncherFactory.InvalidKols.selector);

        c = _config("dup-kol");
        c.namedKols[1] = kolA;
        _expectNewLauncherRevert(c, KabalKultLauncher.InvalidConfig.selector);
    }

    // ─── creator options: tax, payout token ──────────────────────────────────

    function test_customTaxAndSplit() public {
        _deploy();
        KabalKultConfig memory c = _config("tax-split");
        (c.buyTaxBps, c.sellTaxBps) = (0, 300); // sell-only tax
        (c.milestoneShareBps[0], c.milestoneShareBps[1]) = (3000, 7000);
        (KabalKultLauncher l, KabalKultVault v) = _launchAndEarn(c);
        assertEq(l.buyTaxBps(), 0);
        assertEq(l.sellTaxBps(), 300);
        uint256 bal = address(v).balance;
        _price(BNB_USD * ((M1 + M2) / 2) / v.marketCapUsd());
        v.checkMilestone();
        assertEq(v.totalSpent(), bal * 3000 / 10_000, "M1 spends its 30%");
        _price(BNB_USD);
        v.checkMilestone();
        assertEq(address(v).balance, v.bnbOwed(), "M2 spends the rest");
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
        v.checkMilestone(); // both milestones reached: everything
        (, uint256 b,) = v.earned(kolA);
        assertEq(b, bal / 2);
        uint256 a0 = kolA.balance;
        v.claim(kolA);
        assertEq(kolA.balance - a0, bal / 2, "kolA got BNB");
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
        (uint256 t, uint256 b,) = v.earned(kolA);
        assertGt(t, 0, "booked in the chosen token");
        assertEq(b, 0, "no BNB fallback needed");
        v.claim(kolA);
        assertGt(IERC20(other).balanceOf(kolA), 0, "kolA got the chosen token");
    }

    function test_unbuyableTokenFallsBackToBnb() public {
        _deploy();
        KabalKultConfig memory c = _config("fallback");
        c.payoutToken = address(relay); // has code, but is not a token and has no pool
        (, KabalKultVault v) = _launchAndEarn(c);
        uint256 bal = address(v).balance;
        v.checkMilestone();
        assertEq(v.milestonesPaid(), 2, "the milestones still pay");
        v.claim(kolA);
        assertEq(kolA.balance, bal / 2, "paid in BNB instead");
    }

    function test_factoryRejectsBadOptions() public {
        _deploy();
        KabalKultConfig memory c = _config("opts");
        c.buyTaxBps = 1001;
        _expectNewLauncherRevert(c, KabalKultLauncherFactory.InvalidTax.selector);
        (c.buyTaxBps, c.sellTaxBps) = (50, 99); // higher side under 1%
        _expectNewLauncherRevert(c, KabalKultLauncherFactory.InvalidTax.selector);
        (c.buyTaxBps, c.sellTaxBps) = (500, 500);
        c.payoutToken = alice; // a wallet, not a token
        _expectNewLauncherRevert(c, KabalKultLauncherFactory.InvalidPayout.selector);
    }

    function _expectNewLauncherRevert(KabalKultConfig memory c, bytes4 sel) internal {
        uint256 fee = portal.SALT_LOCK_FEE();
        vm.prank(creator);
        vm.expectRevert(sel);
        portal.newLauncher{value: fee}(address(lf), abi.encode(c));
    }

    // ─── v2: invites, dashboard views ────────────────────────────────────────

    function test_creatorAddsInvites() public {
        _deploy();
        KabalKultLauncher l = _newKK("invites");
        address[] memory more = new address[](2);
        (more[0], more[1]) = (alice, _guest(0)); // _guest(0) already invited: counted once
        vm.prank(alice);
        vm.expectRevert(KabalKultLauncher.NotCreator.selector);
        l.addInvites(more);
        vm.prank(creator);
        l.addInvites(more);
        assertEq(l.inviteCount(), 65);
        vm.prank(alice);
        l.joinCampaign();
        assertTrue(l.isKol(alice));
    }

    function test_vaultDashboardViews() public {
        _deploy();
        (KabalKultLauncher l, KabalKultVault v) = _launchAndEarn("views");
        _join(l, 3);
        vm.prank(kolA);
        l.confirm();

        {
            (uint256[] memory usd, uint16[] memory share) = v.milestones();
            assertEq(usd.length, 2);
            assertEq(usd[1], M2);
            assertEq(share[0], 5000);
            assertEq(v.payoutToken(), address(stock));
            assertEq(v.kolCount(), 3);
        }
        {
            (uint256 n, bool conf, bool inv, string memory x) = v.kolStatus(_guest(3));
            assertEq(n, 3);
            assertTrue(conf && inv);
            assertEq(bytes(x).length, 0);
            (n, conf, inv,) = v.kolStatus(kolA);
            assertEq(n, 1);
            assertTrue(conf);
            assertFalse(inv);
        }
        {
            (address cr, uint16 buy, uint16 sell, uint32 slots, uint256 taken) = v.deal();
            assertEq(cr, creator);
            assertEq(buy + sell, 1000);
            assertEq(slots, 50);
            assertEq(taken, 1);
        }
        {
            (uint256 bnbUsd, uint256 payoutUsd, uint256 at, bool fresh, string memory src) = v.prices();
            assertEq(bnbUsd, BNB_USD);
            assertEq(payoutUsd, NVDA_USD, "mNVDAb priced from the relay");
            assertEq(at, relay.updatedAt());
            assertTrue(fresh);
            assertEq(src, "test");
            assertEq(v.marketCapUsdLast(), v.marketCapUsd());
        }
        vm.warp(block.timestamp + relay.MAX_AGE() + 1);
        (,,, bool stillFresh,) = v.prices();
        assertFalse(stillFresh, "stale shows as stale, does not revert");
        v.marketCapUsdLast();
    }
}
