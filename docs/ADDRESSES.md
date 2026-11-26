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

## Our contracts

_None deployed yet (P1)._
