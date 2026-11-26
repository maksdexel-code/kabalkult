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
| Atlas BNB/USD feed (BSC Testnet, no whitelist) | `0x3957d289ee9C38272377786787ea34F9dd29788D` | Atlas team (booth, 26 Nov) — ✅ `description()` = "SingleFeed BNB/USD", 18 decimals, `latestRoundData()` $552.64 updated < 1 min before check |
| Atlas NVDAB/USD feed (real NVIDIA bStock) | `0x3ef39d6361efa1e8ca066751f438077da81082a6` | Atlas team — ✅ "SingleFeed NVDAB/USD", 18 decimals, $149.37 (CMC NVDA at the same time: $149.88) |
| Atlas BTC/USD, ETH/USD feeds | `0x83B2F2c20df36F166cF5b3f017204cbB7BABcAD0`, `0x35369dEcD8c662954B3D24acc2A862C708A34fD2` | Atlas team — ✅ live, not used |
| Atlas feed interface | Chainlink-compatible `latestRoundData()`, `decimals()`, `description()` | [Atlas docs](https://docs.atlasoracle.io/developers/api-reference/single-feed-contract) |

## Token metadata (IPFS, uploaded through Flap's upload route)

| Item | CID |
|---|---|
| Metadata JSON (`meta` at launch) | `bafkreig3ywcd6pccsoae3gqsxrncx3sqh74klsjxqb6wyqn7b7bauctodm` |
| Logo | `bafkreianrrn7l4jsz2pslmk3sqfeqrm5ld6v3iuwcorzvhmoc3voztvlie` |

## Our contracts — v2 (current, deployed Thu 26 Nov 2026 15:25, BSC Testnet)

**Source verified on BscScan** (26 Nov, `tools/verify-bscscan.sh`): all contracts below plus both beacons (`0x119Fc4570b78E7ddc6D43d303B64593Dc09227d4`, `0x6c61D923410a40c5B605715aFa32b68BF84809f2`). Launchers and vaults are beacon proxies of the verified implementations.

v2 = v1 + on-chain campaign invites (no-argument `joinCampaign()`, works as a button on Flap's launch page) + vault dashboard views for Flap's Vault UI.

| Contract | Address | Deploy |
|---|---|---|
| KabalKultLauncherFactory | [`0xb3E793C1111900F3d47EEe4D8c22c3C15cD0551F`](https://testnet.bscscan.com/address/0xb3E793C1111900F3d47EEe4D8c22c3C15cD0551F) | [tx](https://testnet.bscscan.com/tx/0x66fd82d86d00e61ae10ef0ead79b56a6f73dd7623fc63b42adc972c3008d9b72) |
| KabalKultVaultFactory | [`0xA062092f6a12974b2024EF6B820Bc8250780779C`](https://testnet.bscscan.com/address/0xA062092f6a12974b2024EF6B820Bc8250780779C) | same tx |
| KabalKultLauncher implementation | [`0xae9ff6e42a407c4566344156d8986c3a0489d27b`](https://testnet.bscscan.com/address/0xae9ff6e42a407c4566344156d8986c3a0489d27b) | [tx](https://testnet.bscscan.com/tx/0x7cc1877177afa2a5912248c535536410e6fba0927c328eba34754768125716e5) |
| KabalKultVault implementation | [`0xc56431b201576a81943f4d390c2ef8fb7971b0da`](https://testnet.bscscan.com/address/0xc56431b201576a81943f4d390c2ef8fb7971b0da) | [tx](https://testnet.bscscan.com/tx/0xe30d117057361740f6cbe17b3d0520f208f54ea5eb9e95eaa13ec0194a9ee42d) |
| PriceRelay | [`0x5C3A664e4257b280f6d3fA0c599E310068919478`](https://testnet.bscscan.com/address/0x5C3A664e4257b280f6d3fA0c599E310068919478) | [tx](https://testnet.bscscan.com/tx/0x2f1263d70d7b198a6012ee317a450c51c16acd159766421cedec9befd528851f) |
| StockDesk | [`0x71A2399272121489993f3BafA18400BB0966E0A4`](https://testnet.bscscan.com/address/0x71A2399272121489993f3BafA18400BB0966E0A4) | [tx](https://testnet.bscscan.com/tx/0x32dff7519d40208c992b0e35a20b184df064c0c87ffde2feb2d812ceb53a219d) |
| mNVDAb / mTSLAb / mAAPLb | [`0x687809daD911091f8FdEEf50E392734674CA7AaA`](https://testnet.bscscan.com/address/0x687809daD911091f8FdEEf50E392734674CA7AaA) / [`0x14c502a6920A81A58C14CC554C810Af1389eFa57`](https://testnet.bscscan.com/address/0x14c502a6920A81A58C14CC554C810Af1389eFa57) / [`0x90A95459ED7CaeEa5f1FB427Cf5502B4651E9B38`](https://testnet.bscscan.com/address/0x90A95459ED7CaeEa5f1FB427Cf5502B4651E9B38) | StockDesk tx |

### Launch v2 — KabalKult (KKULT)

| Item | Value |
|---|---|
| `Portal.newLauncher` | [tx](https://testnet.bscscan.com/tx/0xd7ac1c08921ee7edf6b91c18ff9b36b1250a19980435aa893fa943b7847b60fa) |
| `launcher.launch()` | [tx](https://testnet.bscscan.com/tx/0x1da9a9b0583d6d0165b6a9d4decbdc356c21ce9c7bb69d88a132929bd58c0183) |
| Launcher | [`0x1fcC67DCb185C273b2352267717412Cc899B9495`](https://testnet.bscscan.com/address/0x1fcC67DCb185C273b2352267717412Cc899B9495) |
| Token (KKULT) | [`0xFf5a76C7748817EaaF3a457b0ad445e1F1Ed7777`](https://testnet.bscscan.com/address/0xFf5a76C7748817EaaF3a457b0ad445e1F1Ed7777) |
| Pool | [`0xc165Ab54e4d618628c7d37b4069b14285EaeD9E7`](https://testnet.bscscan.com/address/0xc165Ab54e4d618628c7d37b4069b14285EaeD9E7) |
| Vault | [`0x06f8efB571951D0169e10cd626eB4c5Db9BB954a`](https://testnet.bscscan.com/address/0x06f8efB571951D0169e10cd626eB4c5Db9BB954a) |
| Settings | 5%/5% tax · mNVDAb · milestones $731 / $853 / $975 / $1,097 paying 10/20/30/40% · 2 named KOLs · 2 invitees, 50 slots |

### Launch v2 — trading run on testnet (Thu 26 Nov, 16:05–16:30)

| Step | Result | Tx |
|---|---|---|
| Run 1: 18 random buys (0.03–0.06 tBNB) + 6 sells + tax dispatches | market cap $609 → $1,225 | log: `scripts/demo/spam.sh` |
| Milestones 1 + 2 paid **in one payout** (catch-up: the pump passed both) | 30% of the vault → mNVDAb | [tx](https://testnet.bscscan.com/tx/0x4cd5517ce5dec04760283f73fcbc27958fc1a741a8c9ab95a002f64bbd2b2654) |
| Milestone 3 paid | | [tx](https://testnet.bscscan.com/tx/0x434b5e900efeeac8be3609fd9e973b7bff18c3a289a91780f6bf28c90033d56a) |
| Milestone 4 paid **automatically by the CMC relayer** right after a price push | vault spent | [tx](https://testnet.bscscan.com/tx/0x40e14ba24f83f2a5f503b337891ef9fb8f722582f8d9a7bf7005dd37d49150fb) |
| Run 2 (after the last milestone): 20 more rounds of buys and sells | 5 more payouts of new tax to KOLs; one sell dipped market cap to $1,027 (below the last milestone), so that tax waited until it was back above | 8 payouts in total |
| KOLs claim (anyone can trigger, funds go to the KOL) | each named KOL holds **0.2651 mNVDAb, earned $39.65** | [tx](https://testnet.bscscan.com/tx/0x76db6d373e46ebcdf0c994faa47f04a8fd099ebed7b0ac35615cc11214fbcdb6), [tx](https://testnet.bscscan.com/tx/0xf593393900fd6ddbe78227ad5f9d1a3304104d35f192a9b58073b7dfc03d651a) |
| Vault totals | revenue 0.1433 tBNB, all of it paid out | |

## Our contracts — v1 (first launch; full flow proven, superseded by v2)

### v1 contracts

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

## Launch #1 — full flow on testnet (Thu 26 Nov)

| Step | Result | Tx |
|---|---|---|
| 6 buys × 0.05 tBNB (BUYER wallet) | market cap $610 → $987 | [tx](https://testnet.bscscan.com/tx/0x299295c56c9ebd1ec60025c83c6661fd4289b84a1d121f0bd452cff7a1bb2de4) (first) |
| Sell 25% → tax converted to BNB | market cap $854 | [tx](https://testnet.bscscan.com/tx/0x16a3540f5a6ac83c8bebe9a40de2d94506b160fa6a640ef5c51d842771cbb589) |
| `dispatch()` → tax to vault | vault 0.0178 tBNB | [tx](https://testnet.bscscan.com/tx/0xff6a3152d8ed3b16dccdbf22bf08158ff94130fde0912842f09e7ef7610a8cd7) |
| Milestone 1 ($732) paid — 10% of vault → mNVDAb | 2 KOLs | [tx](https://testnet.bscscan.com/tx/0x583719a085a20add3b28fc542a7b916412b1f83cad017c75b5dc53f5436d16b2) |
| Milestone 2 ($854) paid at MC $921 | | [tx](https://testnet.bscscan.com/tx/0x3aa411305bae6543f435fd225e394a5793f02004f43290691fe4e607606b2449) |
| Milestone 3 ($976) paid at MC $990 | | [tx](https://testnet.bscscan.com/tx/0xb150870ade9c982421d1149ecce8f831f85dd8e94a2df91a2aa15f62bbbd8385) |
| Milestone 4 ($1,098) paid at MC $1,136 — vault empty | | [tx](https://testnet.bscscan.com/tx/0xc4e24163d81fee128e2ef3f99555ccb7b842fa010ddf3bec11017c70f0ff64db) |
| KOLs claim (anyone can trigger, funds go to the KOL) | each KOL holds 0.032757 mNVDAb, earned $4.93 | [tx](https://testnet.bscscan.com/tx/0x7c96015a2e6515b0460beab8b5db961c4193be88497cb5dbce9024bd98368fab), [tx](https://testnet.bscscan.com/tx/0x13ca02fc88c721019bbcc71ae797bc61588923676395df7a910e53163037f215) |

