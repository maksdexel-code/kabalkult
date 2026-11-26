# KabalKult — KOLs paid in stock, only if the meme performs

> **Testnet only (BSC Testnet, chain 97). Unaudited. Mock assets (mNVDAb, mTSLAb, mAAPLb are not real stocks).**

KOLs who promote a meme are usually paid in that meme. They sell, the chart dumps, holders lose trust.
KabalKult is a [Flap](https://flap.sh) **Pool Launch** launcher where the creator sets KOL wallets and two USD
market-cap milestones at launch. 100% of the token's buy/sell tax collects in a vault. When a milestone is
reached, the vault buys the creator's payout token (a tokenized stock — mock NVDA/TSLA/AAPL on testnet — any token
with a BNB pool, or plain BNB) and splits it equally among the KOLs.
The KOL never holds a meme bag to dump.

## How it works

1. **Create** — the creator calls Flap's `Portal.newLauncher(KabalKultLauncherFactory, config)`. The config holds
   named KOLs, an optional campaign (Merkle allowlist of invited creators, 50 first-come slots), two USD
   market-cap milestones, and the creator's options:
   - **buy and sell tax**, each 0–10% (the higher side at least 1%, Flap's rule);
   - **payout token**: a mock stock from `StockDesk`, any token with a BNB pool on the testnet DEX, or BNB;
   - **split**: the share of the vault paid at milestone 1 (milestone 2 gets the rest).
2. **KOLs join** — named KOLs are always paid; `confirm()` adds a public ✅ badge. Invited creators take a slot with
   `joinCampaign(proof)`, before or after the launch, until 50 are taken.
3. **Launch** — the creator calls `launch()` with the pool BNB. Flap creates the token, its DEX pool and our vault in
   one transaction (LP burned). The tax slot is 100% `KabalKultVault`.
4. **Tax** — collected in meme tokens, converted to BNB in a batch during a sell, then anyone calls the token's tax
   processor `dispatch()` to send it to the vault.
5. **Payout** — anyone calls `vault.checkMilestone()`. If market cap (pool price × supply × BNB/USD) ≥ the next
   milestone and the price is < 10 minutes old, the vault spends its BNB (milestone 1: the creator's share,
   milestone 2: the rest) on the payout token — stocks from `StockDesk` at the CoinMarketCap price, other tokens
   through the DEX — and sends an equal share to every KOL listed at that moment. If the token cannot be bought or
   sent, that milestone pays in BNB instead, so the vault can never get stuck.

## Contracts (`contracts/src`)

| Contract | Role |
|---|---|
| `KabalKultLauncherFactory` | Flap `LauncherFactoryBase`. Deploys one Launcher per deal (beacon proxy) and its paired vault factory. |
| `KabalKultLauncher` | Flap `LauncherBase`. KOL list, campaign slots, milestones, `launch()`. |
| `KabalKultVaultFactory` | Flap `DirectLaunchVaultFactoryBase`. Only serves our Launchers, mid-launch. |
| `KabalKultVault` | Flap `DirectLaunchVaultBase`. Receives tax BNB, `checkMilestone()` pays out in stock. |
| `PriceRelay` | BNB/USD + NVDA/TSLA/AAPL USD with timestamp and source, pushed by our relayer (CMC Pro API). |
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

Campaign allowlist (invite list → Merkle root + proofs): `cd scripts/campaign && npm i && node merkle.mjs invited.json tree.json`.

## Known limits

- Market cap uses the spot pool price, so one large buy can trigger a milestone (hold rule / TWAP is on the roadmap).
- Tax stops 30 days after launch (Flap tax duration we set).
- Buying a non-stock payout token on the DEX has no minimum-output check, so a sandwich trade can take value
  (an oracle/TWAP minimum is the mainnet fix).
