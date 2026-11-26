# Addresses — BSC Testnet (chainId 97)

Every address here is verified from an official source (linked) and, where marked ✅, checked on chain on 25 Nov 2026.
Testnet only. Never use these for mainnet transactions.

## Flap Pool Launch (external)

| Contract | Address | Source | On-chain check |
|---|---|---|---|
| Direct Launch Portal ("Hub") | `0x000042108465206185A077Edc3F3fd2b49060000` | [LaunchVaultAddresses.sol](https://github.com/flap-sh/FlapPoolLaunchVaultExample/blob/main/src/flap/LaunchVaultAddresses.sol), [Flap docs](https://docs.flap.sh/en/flap/v2/developers/deployed-contract-addresses) | ✅ `version()` = `v1.2.0`, `featureFlags()` = 0 (creation not paused), `SALT_LOCK_FEE()` = 0.005 BNB |
| Flap Guardian (testnet) | `0x00004d58290854c5E9880F4b5B1993c6Ad8b0000` | [LaunchVaultAddresses.sol](https://github.com/flap-sh/FlapPoolLaunchVaultExample/blob/main/src/flap/LaunchVaultAddresses.sol) | used in fork tests |
| Portal ProxyAdmin | `0x0000Ed588dfc01749C20bA69b5f8c77d706E0000` | [test/ForkAddresses.sol](https://github.com/flap-sh/FlapPoolLaunchVaultExample/blob/main/test/ForkAddresses.sol) | used in fork tests |
| FlapDirectTaxToken implementation | `0x7777c57ff7dc441c1715b2e36fa581c48B782222` | ForkAddresses.sol + Flap docs | used for salt prediction |
| TokenDockRouter | `0x000048E888aBf09f690a952E1b386b2D031a0000` | LaunchVaultAddresses.sol + Flap docs | — (we don't use the reserve) |
| OpenTokenDock | `0x0000E34C74b9eC7b52F35528249Aa9C4AdE00000` | LaunchVaultAddresses.sol + Flap docs | — |
| VerifiedTokenDock | `0x00004B06D90Df7a39491264744BF187D90Df0000` | LaunchVaultAddresses.sol + Flap docs | — |
| TaxTokenHelper | `0xD64441e5FcD02D342B8cf6eBA10Ef6E40d0dA90f` | Flap docs | — |
| AllocationStrategy | `0x000051353ef814E4779B692cb2Bb3A6Cb3710000` | Flap docs | — |

Do **not** confuse with the bonding-curve Portal `0x5bEacaF7ABCbB3aB280e80D007FD31fcE26510e9` (different product).

## DEX (used by Pool Launch on testnet)

| Contract | Address | Source |
|---|---|---|
| WBNB | `0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd` | [test/ForkAddresses.sol](https://github.com/flap-sh/FlapPoolLaunchVaultExample/blob/main/test/ForkAddresses.sol) |
| V2 Router (buys/sells; vault buys non-stock payout tokens here) | `0xc9D63ddCB9549578057EAB6A83a543DdFEE2b8c3` | test/ForkAddresses.sol — ✅ swaps worked in our fork probe; ✅ `factory()` = `0x6725F303b657a9451d8BA641348b6761A6CC7a17`, the same V2 factory as PancakeSwap's testnet router `0xD99D1c33F9fC3444f8101754aBC46c52416550D1`, so it reaches PancakeSwap testnet pools |

## Flap infrastructure (testnet)

| Contract | Address | Source | On-chain check |
|---|---|---|---|
| X Verifier (XGeneralVerifier) | `0x236C4AF8e0674fB22a139DDE4C2A518CBA819932` | [Flap docs: X Verifier](https://docs.flap.sh/en/flap/v2/developers/flap-infrastructures/flap-x-verifier) | ✅ `oracleKey()` = `0xE93960A4a1233794cC00A4408e8664e4EdB0B9e5`; oracle `https://verifyx.taxed.fun/health` = 200 |

## Flap UI template reference deployment (for comparison only)

| Contract | Address | Source |
|---|---|---|
| Example Launcher Factory | `0xc574f30e2ee26fe638eece6d9876217015cd0a38` | [testnet-example.md](https://github.com/flap-sh/flap-vault-component-template/blob/main/examples/launcher-runtime/testnet-example.md) |
| Example Vault Factory | `0xb89113e16c78989b7bccf5d0e13e99bf2c58dc32` | same |
| Public test CA (Vault UI preview) | `0xf8ac72e7adefbce6ff22d9a9238512933e247777` | [template README](https://github.com/flap-sh/flap-vault-component-template) |

## Data sources

| Item | Value | Source |
|---|---|---|
| CMC Pro base URL | `https://pro-api.coinmarketcap.com` (header `X-CMC_PRO_API_KEY`) | [CMC auth guide](https://coinmarketcap.com/api/documentation/guides/authentication) |
| CMC BNB/USD | `GET /v3/cryptocurrency/quotes/latest?symbol=BNB` | [CMC crypto reference](https://coinmarketcap.com/api/documentation/pro-api-reference/cryptocurrency) |
| CMC stocks (RWA) | `GET /v5/real-world-assets/quotes/latest?symbol=NVDA,TSLA,AAPL` (1 credit for all three; ✅ live call 26 Nov) | [CMC RWA reference](https://coinmarketcap.com/api/documentation/pro-api-reference/real-world-assets) |
| CMC key usage | `GET /v1/key/info` (0 credits) | [CMC tools reference](https://coinmarketcap.com/api/documentation/pro-api-reference/tools) |
| Real NVIDIA bStock on CMC | NVDAB, CMC id 40215 | [CMC tokenized stocks](https://coinmarketcap.com/view/tokenized-stock/) |
| Atlas feeds | **Unknown** — Chainlink-compatible `latestRoundData()`; no public BSC/testnet addresses | [Atlas docs](https://docs.atlasoracle.io/developers/api-reference/single-feed-contract) — ask Atlas booth |

## Token metadata (IPFS, uploaded through Flap's upload route)

| Item | CID |
|---|---|
| Metadata JSON (`meta` at launch) | `bafkreig3ywcd6pccsoae3gqsxrncx3sqh74klsjxqb6wyqn7b7bauctodm` |
| Logo | `bafkreianrrn7l4jsz2pslmk3sqfeqrm5ld6v3iuwcorzvhmoc3voztvlie` |

## Our contracts (deployed Thu 26 Nov 2026, BSC Testnet)

| Contract | Address | Deploy |
|---|---|---|
| KabalKultLauncherFactory | [`0xEe5d815a8a71d3913eC22aB29C5ee8Acf371ebfe`](https://testnet.bscscan.com/address/0xEe5d815a8a71d3913eC22aB29C5ee8Acf371ebfe) | [tx](https://testnet.bscscan.com/tx/0xb509d8cf7a77c9e05ade14db6b717512ac772accd5287afea6e96b6e5e7ebb0d) |
| KabalKultVaultFactory (deployed by the launcher factory) | [`0x99beC1Df4A1a533114eAFAf2dCDa4764AD692e9a`](https://testnet.bscscan.com/address/0x99beC1Df4A1a533114eAFAf2dCDa4764AD692e9a) | same tx |
| KabalKultLauncher implementation | [`0x4aD60d58AEB98244d3Ee9E387e17aBF6a48E3d54`](https://testnet.bscscan.com/address/0x4aD60d58AEB98244d3Ee9E387e17aBF6a48E3d54) | [tx](https://testnet.bscscan.com/tx/0xa2857afff96588b9c7844bebc3c527ccb9cf12ebb5db24578d07e73851d1686c) |
| KabalKultVault implementation | [`0x2ac0D6A5dD2Da2190abe5Be3DDf0C42E061A8cA1`](https://testnet.bscscan.com/address/0x2ac0D6A5dD2Da2190abe5Be3DDf0C42E061A8cA1) | [tx](https://testnet.bscscan.com/tx/0x0bcc5b226820f358054f12350d96289c9d32d46bbf15595085232d78db81922c) |
| PriceRelay (CMC prices, updater = deployer) | [`0x61E6Ef43982a1Ae9E3E0F6bc9843E3819C02b416`](https://testnet.bscscan.com/address/0x61E6Ef43982a1Ae9E3E0F6bc9843E3819C02b416) | [tx](https://testnet.bscscan.com/tx/0x3d680521b0265eda30cb3c236cabc0f218a02e64ce906549e762233744ad3d80) |
| StockDesk | [`0x5086eb9D0D3ab0dbEE9ea70cF7eB3b2F90cD4ea2`](https://testnet.bscscan.com/address/0x5086eb9D0D3ab0dbEE9ea70cF7eB3b2F90cD4ea2) | [tx](https://testnet.bscscan.com/tx/0xf457004095e6fcd487d15d2c9542145edc4687fb0e1ef94383fe379a12c6b2b9) |
| mNVDAb (Mock NVIDIA bStock) | [`0x1f2029441D7E6449EddA16B79CaB5E7629ef4495`](https://testnet.bscscan.com/address/0x1f2029441D7E6449EddA16B79CaB5E7629ef4495) | StockDesk tx |
| mTSLAb (Mock Tesla bStock) | [`0x1310a58273E25490B04CF9e30ac87cEF793c32eA`](https://testnet.bscscan.com/address/0x1310a58273E25490B04CF9e30ac87cEF793c32eA) | StockDesk tx |
| mAAPLb (Mock Apple bStock) | [`0xdccbCcAB80a0Fb2957D6Db49c4809982623564EC`](https://testnet.bscscan.com/address/0xdccbCcAB80a0Fb2957D6Db49c4809982623564EC) | StockDesk tx |

Deployer / creator: `0xE2cAe010EcEcc7225a5dCfC4A324cd49eB766090`.

## Launch #1 — KabalKult (KKULT), through our Launcher Factory

| Item | Value |
|---|---|
| `Portal.newLauncher` | [tx](https://testnet.bscscan.com/tx/0x4f5880dbed82eaa95b0d52b767b941c5509bebb856f79310187ebd80ec927d3e) |
| `launcher.launch()` (token + pool + vault, LP burned) | [tx](https://testnet.bscscan.com/tx/0x1aca37df5a0a8d4eb1e2a8625081e5d573e114a8a8ca02116ab2b5bce50bb532) |
| Launcher | [`0xd5455B377b83416A6BA91a49E771D5dF31FC1df7`](https://testnet.bscscan.com/address/0xd5455B377b83416A6BA91a49E771D5dF31FC1df7) |
| Token (KKULT) | [`0x2D6AC40ABc205FA58dEc02500E6b9F7762E87777`](https://testnet.bscscan.com/address/0x2D6AC40ABc205FA58dEc02500E6b9F7762E87777) |
| Pool (V2, 1.1 tBNB + 100% supply) | [`0x4e54481Aa60D2D97016C96A8f18F3d522c8E7334`](https://testnet.bscscan.com/address/0x4e54481Aa60D2D97016C96A8f18F3d522c8E7334) |
| Vault | [`0xda65B00Bc719d49cbA44a5f2526C2506859E3a09`](https://testnet.bscscan.com/address/0xda65B00Bc719d49cbA44a5f2526C2506859E3a09) — ✅ `Portal.getLaunchVault(token)` = this vault + our vault factory |
| Tax | 5% buy / 5% sell, 100% to the vault, 30 days |
| Milestones (launch MC $610 at BNB $554.84) | $732 / $854 / $976 / $1,098 (1.2× / 1.4× / 1.6× / 1.8×), paying 10 / 20 / 30 / 40% |
| Payout token | mNVDAb |
| KOLs | 2 named + campaign (50 slots, Merkle root `0x459b8ef073b29450ac92b55e55706eeb43c5f2180cf761eb8207dc83059c470d`) |
| First CMC price push | [tx](https://testnet.bscscan.com/tx/0xe37987bed9e7f25b8447d1a89172ec1842e6e9243ce3dfae11b5faa70430734d) (relayer log: `logs/relayer.jsonl`) |
