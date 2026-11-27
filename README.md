# KabalKult — KOLs paid in anything, only if the meme performs

> **Testnet only (BSC Testnet, chain 97). Unaudited. Mock assets (mNVDAb, mTSLAb, mAAPLb are not real stocks).**

KOLs who promote a meme are usually paid in that meme. They sell, the chart dumps, holders lose trust.
KabalKult is a [Flap](https://flap.sh) **Pool Launch** launcher where the creator sets KOL wallets and up to ten USD
market-cap milestones at launch. 100% of the token's buy/sell tax collects in a vault. When a milestone is
reached, the vault buys the creator's payout token (a tokenized stock — mock NVDA/TSLA/AAPL on testnet — any token
with a BNB pool, or plain BNB) and splits it equally among the KOLs.
The KOL never holds a meme bag to dump.

**Demo video:** https://youtu.be/_O23MoKVkFE

One-page write-up (problem, data sources, contracts, next steps): [`docs/WRITEUP.md`](docs/WRITEUP.md).

**Live on Flap (BSC Testnet; our Launcher Factory is linked to our UI by Flap):**
[Create a deal](https://test.utter.cash/create/launcher?chain=bnb-testnet&factory=0xb3e793c1111900f3d47eee4d8c22c3c15cd0551f) (our Launcher UI, creation form) ·
[KKULT deal page](https://test.utter.cash/launcher/0x1fcC67DCb185C273b2352267717412Cc899B9495?chain=bnb-testnet) (our Launcher UI, deal page) ·
[KOL vault](https://test.utter.cash/bnb-testnet/0xFf5a76C7748817EaaF3a457b0ad445e1F1Ed7777/taxinfo?artifactPath=vaultui_kabalkult-vault_01M8BFV3PK67GXSAC2XDG89C59%2Fv20261126092021041_kabalkult-vault_a9af6c4a27b7&lang=en) (our Vault UI: live market cap, milestones, claims) ·
[KabalDemo deal page](https://test.utter.cash/launcher/0x9e7891dc2695229fdcd96c7fa0470b7d3b703e32?chain=bnb-testnet) (the deal from the demo video).

**Proven on BSC Testnet** (every transaction in [`docs/ADDRESSES.md`](docs/ADDRESSES.md)):
- **KKULT:** real trades took the market cap from $609 to $1,225; all 4 milestones paid in mNVDAb (1 + 2 in one payout,
  4 by the relayer on its own); new tax kept paying after the last milestone; each named KOL claimed $39.65.
- **Proof of shill:** a real X post naming the deal and the KOL's wallet, proven by Flap's X Verifier and recorded on
  chain with `confirmWithX`; the vault page shows "Confirmed, posted on X as @handle".
- **KabalDemo (demo video):** created, confirmed, joined and launched on camera; trades took it from $611 to $1,095 and
  the relayer paid milestones 1 + 2 about 90 seconds later with nobody pressing a button; milestones 3 and 4 stay locked.
- **Relayer** on Google Cloud (every 5 min, every KabalKult launch): CMC + Atlas prices on chain, waiting tax moved
  into vaults, reached milestones paid. Request log: [`logs/relayer.jsonl`](logs/relayer.jsonl).

## How it works

1. **Create** — the creator calls Flap's `Portal.newLauncher(KabalKultLauncherFactory, config)`. The config holds
   named KOLs, an optional campaign (invited wallets stored on chain, 0–99,999 first-come slots), 1–10 USD
   market-cap milestones each with its share of the payouts, and the creator's options:
   - **buy and sell tax**, each 0–10% (the higher side at least 1%, Flap's rule);
   - **payout token**: a mock stock from `StockDesk`, any token with a BNB pool on the testnet DEX, or BNB;

2. **KOLs join** — named KOLs are always paid; `confirm()` adds a public ✅ badge, and `confirmWithX()` proves an
   X post naming the deal ("proof of shill", checked on chain by Flap's X Verifier). Invited creators take a slot with
   `joinCampaign()`, before or after the launch, until all slots are taken.
3. **Launch** — the creator calls `launch()` with the pool BNB. Flap creates the token, its DEX pool and our vault in
   one transaction (LP burned). The tax slot is 100% `KabalKultVault`.
4. **Tax** — collected in meme tokens, converted to BNB in a batch during a sell, then anyone calls the token's tax
   processor `dispatch()` to send it to the vault.
5. **Payout** — anyone calls `vault.checkMilestone()`. If market cap (pool price × supply × BNB/USD) ≥ the next
   milestone and the price is < 10 minutes old, the vault spends that milestone's share of its BNB on the payout
   token — stocks from `StockDesk` at the CoinMarketCap price, other tokens through the DEX — and books an equal
   share for every KOL listed at that moment. KOLs `claim` whenever they want (pull payments: a payout costs the
   same gas for 1 or 99,999 KOLs). A pump past several milestones pays them in one go; after the last milestone,
   new tax keeps paying KOLs while the market cap stays above it. If the token cannot be bought, that payout is in
   BNB instead, so the vault can never get stuck. Our relayer moves waiting tax into the vault (`dispatch()`) and calls `checkMilestone()` after each price update, for every deal launched through our factory
   (found from the factory's `KabalKultLauncherCreated` events, plus a known-vault list as a fallback).

## Price data: CoinMarketCap + Atlas

Market cap, milestone checks and stock purchases all use prices our relayer (`scripts/relayer/relay.sh`) writes to
`PriceRelay` every 5 minutes. It runs on Google Cloud (Cloud Run job + Cloud Scheduler, keys in Secret Manager;
container in `scripts/relayer/Dockerfile`), so prices stay live without any laptop. Each round:

1. **CoinMarketCap Pro API** (server side, key only in Secret Manager / `.env`): BNB/USD from `GET /v3/cryptocurrency/quotes/latest?id=1839`,
   NVDA/TSLA/AAPL from `GET /v5/real-world-assets/quotes/latest?symbol=NVDA,TSLA,AAPL` (tokenized-stock prices, 1 credit).
2. **Atlas on-chain feeds** on BSC Testnet, read with `latestRoundData()`: BNB/USD `0x3957d289ee9C38272377786787ea34F9dd29788D`
   and NVDAB/USD (the real NVIDIA bStock) `0x3ef39d6361efa1e8ca066751f438077da81082a6`.
3. **Cross-check:** CMC and Atlas must agree within 1% (BNB) and 3% (NVDA vs NVDAB), and the Atlas feeds must be
   less than 1 hour old. Otherwise the round is skipped: prices on chain go stale after 10 minutes and payouts wait.
4. **Push:** BNB/USD and stock prices go on chain with a source string that records the agreement, e.g.
   `CMC Pro API (BNB v3, stocks v5 RWA) + Atlas feeds (BNB/USD, NVDAB/USD) agree: BNB 0.02%, NVDA 0.03%`.
   The Atlas NVDAB price is stored too (`PriceRelay.stockUsd("NVDAB")`). Every payout event carries this source string.

How to verify: read `PriceRelay.source()`, `bnbUsd()`, `stockUsd("NVDA")`, `stockUsd("NVDAB")`, `updatedAt()` on BscScan,
or look at the `PricesUpdated` events (one every ~5 minutes). Every CMC request (endpoint, credits used) and every
Atlas reading is also logged by the relayer to [`logs/relayer.jsonl`](logs/relayer.jsonl) (no key in the log):
one JSON line per CMC call (`endpoint`, `credits`, `price`), per Atlas cross-check (`atlasBnbUsd`, `atlasNvdabUsd`,
`gapBnbPct`, `gapNvdaPct`) and per on-chain push (`tx` hash, which you can open on BscScan).
Lines marked `"runner":"cloud"` come from the Google Cloud job (`tools/cloud-relayer.sh logs` exports them); earlier ones from the first local runs.

## Contracts (`contracts/src`)

| Contract | Role |
|---|---|
| `KabalKultLauncherFactory` | Flap `LauncherFactoryBase`. Deploys one Launcher per deal (beacon proxy) and its paired vault factory. |
| `KabalKultLauncher` | Flap `LauncherBase`. KOL list, campaign slots, X-post confirm, milestones, `launch()`. |
| `KabalKultVaultFactory` | Flap `DirectLaunchVaultFactoryBase`. Only serves our Launchers, mid-launch. |
| `KabalKultVault` | Flap `DirectLaunchVaultBase`. Receives tax BNB; `checkMilestone()` books payouts, KOLs `claim()`. |
| `PriceRelay` | BNB/USD + NVDA/TSLA/AAPL USD with timestamp and source, pushed by our relayer (CMC Pro API, cross-checked against Atlas on-chain feeds). |
| `StockDesk` / `MockStock` | Testnet stand-in for buying a real bStock (mNVDAb, mTSLAb, mAAPLb) at the oracle price. |

`contracts/src/flap/` is copied unchanged from [FlapPoolLaunchVaultExample](https://github.com/flap-sh/FlapPoolLaunchVaultExample).
Deployed addresses and transactions: [`docs/ADDRESSES.md`](docs/ADDRESSES.md). All v2 contracts are source-verified on BscScan,
e.g. [KabalKultLauncherFactory](https://testnet.bscscan.com/address/0xb3E793C1111900F3d47EEe4D8c22c3C15cD0551F#code).

## Build and test

Requires [Foundry](https://getfoundry.sh). Tests fork the live BSC Testnet Portal.

```bash
git clone --recursive <this repo>
cd contracts
BSC_TESTNET_RPC_URL=https://bsc-testnet-dataseed.bnbchain.org forge test
```

The tests fork the live chain, so a busy free RPC can make some fail with `EvmError: Revert`. Rerun, or use
`https://bsc-testnet-rpc.publicnode.com`. All 24 pass.

Campaign invites are stored on chain: pass them at creation (`invitees`) or add later with `addInvites` (creator only).

## Known limits

Testnet MVP, unaudited, mock stocks. These are known and on the roadmap before any mainnet use:

- **Spot-price milestones.** Market cap uses the current pool price, so one large buy (even buy, trigger, sell in one
  transaction) can reach a milestone. Fix: hold rule across two checks or a TWAP.
- **DEX payouts have no minimum output.** Buying a non-stock payout token on the DEX uses `amountOutMin = 0`, so a
  sandwich trade can take value. Fix: oracle- or TWAP-based minimum. Mock-stock payouts use StockDesk at the oracle price.
- **One price relayer.** The UI says prices are live from CMC and Atlas; it does not say that one wallet pushes them. One wallet pushes BNB/USD and stock prices (CoinMarketCap, cross-checked with Atlas). It could
  trigger milestones early or set the stock price; if it stops, payouts wait (prices older than 10 minutes are refused).
  Fix: read Atlas feeds on chain and require two sources to agree.
- **Creator can add invitees at any time**, including their own wallets. Each new KOL shares later payouts. Fix: cap or
  lock the invite list at launch.
- **No expiry.** If no milestone is ever reached, the vault's BNB stays in the vault. Fix: expiry with buy-back or refund.
- **Tax runs 30 days** after launch (the Flap tax duration we set).
- **BNB fallback.** If buying the payout token fails, that payout is booked in BNB; `claim()` pays the token and BNB
  together, so a token that blocks transfers also blocks the BNB part. Fix: separate claims.
- **Upgradeable.** Launchers and vaults are beacon proxies; only the Flap Guardian can upgrade them (stated here, not in the UI).
- **Named KOLs are paid with or without confirming.** Confirm is only a public badge.
- **Testnet X Verifier key (fixed).** On 27 Nov Flap's testnet X Verifier briefly trusted an old oracle key, so fresh
  proofs failed; we reported it, Flap updated the key, and the proof above went through.
- **No full public KOL roster yet.** The vault page has a "Check a wallet" box (KOL number, confirm badge, proven X
  handle and USD earned for any wallet). A full list needs the KOL list from the deal's launcher, which Flap's Vault UI
  rules don't allow reading (only the vault, token, factory or fixed declared contracts). Fix: a vault view that returns
  the KOL list (vault upgrade by the Flap Guardian), or a reviewed exception from Flap.

## How this was built

Code written with [Claude Code](https://claude.com/claude-code) (AI coding assistant), directed and reviewed by the
solo builder. The product itself uses no AI: payouts are decided by on-chain rules and CoinMarketCap + Atlas price data.
