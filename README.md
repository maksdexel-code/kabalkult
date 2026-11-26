# KabalKult — KOLs paid in anything, only if the meme performs

> **Testnet only (BSC Testnet, chain 97). Unaudited. Mock assets (mNVDAb, mTSLAb, mAAPLb are not real stocks).**

KOLs who promote a meme are usually paid in that meme. They sell, the chart dumps, holders lose trust.
KabalKult is a [Flap](https://flap.sh) **Pool Launch** launcher where the creator sets KOL wallets and up to ten USD
market-cap milestones at launch. 100% of the token's buy/sell tax collects in a vault. When a milestone is
reached, the vault buys the creator's payout token (a tokenized stock — mock NVDA/TSLA/AAPL on testnet — any token
with a BNB pool, or plain BNB) and splits it equally among the KOLs.
The KOL never holds a meme bag to dump.

One-page write-up (problem, data sources, contracts, next steps): [`docs/WRITEUP.md`](docs/WRITEUP.md).

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
   BNB instead, so the vault can never get stuck. Our relayer calls `checkMilestone()` after each price update.

## Price data: CoinMarketCap + Atlas

Market cap, milestone checks and stock purchases all use prices our relayer (`scripts/relayer/relay.sh`) writes to
`PriceRelay` every 5 minutes. Each round:

1. **CoinMarketCap Pro API** (server side, key only in `.env`): BNB/USD from `GET /v3/cryptocurrency/quotes/latest?id=1839`,
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
Atlas reading is also logged by the relayer to `logs/relayer.jsonl` (no key in the log).

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
Deployed addresses and transactions: [`docs/ADDRESSES.md`](docs/ADDRESSES.md).

## Build and test

Requires [Foundry](https://getfoundry.sh). Tests fork the live BSC Testnet Portal.

```bash
git clone --recursive <this repo>
cd contracts
BSC_TESTNET_RPC_URL=https://bsc-testnet-dataseed.bnbchain.org forge test
```

Campaign invites are stored on chain: pass them at creation (`invitees`) or add later with `addInvites` (creator only).

## Known limits

- Market cap uses the spot pool price, so one large buy can trigger a milestone (hold rule / TWAP is on the roadmap).
- Tax stops 30 days after launch (Flap tax duration we set).
- If no milestone is ever reached, the vault's BNB stays in the vault (an expiry / buy-back is on the roadmap).
- Buying a non-stock payout token on the DEX has no minimum-output check, so a sandwich trade can take value
  (an oracle/TWAP minimum is the mainnet fix).
