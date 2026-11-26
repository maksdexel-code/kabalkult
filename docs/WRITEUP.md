# KabalKult — KOLs paid in anything, only if the meme performs

**CoinMarketCap × Atlas Challenge — one-page write-up** · BNB Chain (BSC Testnet, chain 97) · Flap Pool Launch
Testnet only · mock stocks (mNVDAb, mTSLAb, mAAPLb), not real shares · unaudited

## Problem and audience

Meme projects pay KOLs (crypto influencers) in the meme itself. The KOL sells, the chart dumps, holders lose trust,
and the project has no on-chain way to pay only for results. **Audience:** meme and small-cap token creators who run
KOL campaigns, the KOLs and creators they hire, and the agencies in between. KOL marketing is a large, mostly
off-chain market built on trust and screenshots.

## What KabalKult does

A launcher on Flap's Pool Launch where **the token launch is the KOL deal.** Before the token exists, the creator
sets the KOL wallets (plus an open campaign of up to 99,999 first-come slots) and 1–10 USD market-cap milestones.
100% of the buy/sell tax goes into a vault. When the market cap passes a milestone, the vault buys **whatever the
creator chose to pay in**: a tokenized stock (mock NVIDIA, Tesla or Apple on testnet, priced by CMC), any token with a
BNB pool, or plain BNB. It splits the payout equally between the KOLs, who claim it whenever they want. The KOL is
paid in anything but the meme, so there is no bag to dump, and only if the meme performs.

## Data sources: what we use and why

Prices drive the core of the product. They decide **when** a KOL is paid (USD market cap vs milestone), **how much
stock** a stock payout buys, and the **USD value** shown to the KOL. A wrong price means a wrong payout, so we use two
independent sources and refuse to act when they disagree.

| Source | Endpoint / feed | Used for | Why |
|---|---|---|---|
| CMC Pro API | `GET /v3/cryptocurrency/quotes/latest?id=1839` (BNB) | BNB/USD → token market cap in USD | Market cap = pool price (BNB) × supply × BNB/USD; milestones are set in USD |
| CMC Pro API | `GET /v5/real-world-assets/quotes/latest?symbol=NVDA,TSLA,AAPL` | Stock prices for buying the payout and its USD value | CMC's RWA endpoint gives tokenized-stock prices: the flagship payout option. 3 stocks, 1 credit |
| Atlas oracle | BNB/USD feed `0x3957d289ee9C38272377786787ea34F9dd29788D` (`latestRoundData()`) | Cross-check of the CMC BNB price | An on-chain, independent source for the number every payout depends on |
| Atlas oracle | NVDAB/USD feed `0x3ef39d6361efa1e8ca066751f438077da81082a6` | Cross-check of the CMC NVDA price; published on chain | NVDAB is the real NVIDIA bStock on BNB Chain: what mNVDAb stands in for on mainnet |

**How they combine** (our relayer on Google Cloud Run, every 5 minutes, CMC key kept server-side in Secret Manager):
1. Call both CMC endpoints (2 credits per round; every call is logged with its endpoint and credit count).
2. Read both Atlas feeds on BSC Testnet; reject a feed older than 1 hour.
3. CMC and Atlas must agree within **1% (BNB)** and **3% (NVDA vs NVDAB)**. If not, the round is skipped.
4. Push prices to our `PriceRelay` contract with a source string that records the agreement, e.g.
   `CMC Pro API (BNB v3, stocks v5 RWA) + Atlas feeds (BNB/USD, NVDAB/USD) agree: BNB 0.02%, NVDA 0.03%`.
   The Atlas NVDAB price is stored on chain too (`stockUsd("NVDAB")`).
5. The vault and stock desk only accept prices **less than 10 minutes old**. No fresh agreed price, no payout.
6. If a milestone is reached, the relayer triggers the payout right away (anyone else can too).

Every `Payout` event stores the price source string, so each payout shows which data it was made with.

## On BNB Chain (BSC Testnet): contracts and data

| Contract | Address | Data it holds or uses |
|---|---|---|
| PriceRelay | `0x5C3A664e4257b280f6d3fA0c599E310068919478` | `bnbUsd`, `stockUsd(NVDA/TSLA/AAPL/NVDAB)`, `updatedAt`, `source`; `PricesUpdated` event every ~5 min |
| StockDesk (mock bStock seller) | `0x71A2399272121489993f3BafA18400BB0966E0A4` | Sells mNVDAb / mTSLAb / mAAPLb at the fresh CMC price |
| KabalKultLauncherFactory (enabled by Flap) | `0xb3E793C1111900F3d47EEe4D8c22c3C15cD0551F` | Creates each deal through Flap's Portal |
| Vault of the live deal (KKULT) | `0x06f8efB571951D0169e10cd626eB4c5Db9BB954a` | Market cap in USD, milestones, payouts with USD value and source |
| KKULT token | `0xFf5a76C7748817EaaF3a457b0ad445e1F1Ed7777` | Flap tax token, 5% / 5% tax to the vault |

**Shown working on testnet (26 Nov):** real buys and sells moved KKULT from $609 to $1,225 market cap. All 4
milestones paid in mNVDAb: milestones 1 + 2 in one payout, milestone 4 triggered automatically by the relayer
after a CMC price push. New tax kept paying KOLs after the last milestone, and paused while a sell pushed the market
cap below it. Each named KOL claimed 0.2651 mNVDAb, worth $39.65 at payout. All transactions are listed in
`docs/ADDRESSES.md`.

**Verify it yourself:** on BscScan, read `PriceRelay.source()`, `bnbUsd()`, `stockUsd("NVDA")`, `stockUsd("NVDAB")`
and `updatedAt()`, or browse its `PricesUpdated` events; compare with the Atlas feeds' `latestRoundData()`. Read
`marketCapUsd()` and the `Payout` events on the vault. The relayer's request log (`logs/relayer.jsonl`: time,
endpoint, credits, Atlas readings, tx hash; no key) is available on request.

## Safety

API key only in a server-side `.env`, never in the front end or the repo. Prices sanity-bounded before they are
sent; two sources must agree; stale prices block payouts. KOLs pull their payouts (constant gas for any number of
KOLs). A payout token that cannot be bought falls back to BNB, so the vault never gets stuck. 24 fork tests against
the live testnet Portal, including: milestone not reached, stale price, double payout.

## Next steps

1. **Mainnet with real bStocks:** pay KOLs in NVDAB and other bStocks bought on BNB Chain DEXs, priced by CMC and Atlas.
2. **Vault reads Atlas directly** as the primary on-chain price, with CMC as a second signer, so no single relayer is trusted.
3. **Hold rule / TWAP** so one large buy cannot trigger a payout, using CMC DEX data on the meme's own price and volume.
4. **KOL reputation:** every payout is on chain, so a KOL's results across launches become a public track record.
5. **Business:** launches stay free (no developer fee); agencies and projects pay for campaign management and KOL analytics.

**Team:** KabalKult (solo builder: Web3 marketing, 9 years of KOL campaigns). Contacts: on the HackQuest submission.
