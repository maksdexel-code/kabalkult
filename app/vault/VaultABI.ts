import { parseAbi } from "viem";

// KabalKultVault v2 (BSC Testnet): dashboard views, milestone payout and KOL claims.
// The errors let the wallet/simulation show why a payout was refused (StalePrice comes from the PriceRelay).
export const vaultAbi = parseAbi([
  "function token() view returns (address)",
  "function marketCapUsdLast() view returns (uint256)",
  "function milestones() view returns (uint256[] usd, uint16[] shareBps)",
  "function milestonesPaid() view returns (uint256)",
  "function totalRevenue() view returns (uint256)",
  "function totalSpent() view returns (uint256)",
  "function available() view returns (uint256)",
  "function payoutCount() view returns (uint256)",
  "function payoutToken() view returns (address)",
  "function kolCount() view returns (uint256)",
  "function deal() view returns (address creator, uint16 buyTaxBps, uint16 sellTaxBps, uint32 campaignSlots, uint256 campaignSlotsTaken)",
  "function prices() view returns (uint256 bnbUsd, uint256 payoutUsd, uint256 updatedAt, bool fresh, string source)",
  "function kolStatus(address kol) view returns (uint256 number, bool confirmed, bool invited, string xHandle)",
  "function earned(address kol) view returns (uint256 tokenAmount, uint256 bnbAmount, uint256 usd)",
  "function claimable(address kol) view returns (uint256 tokenAmount, uint256 bnbAmount)",
  "function checkMilestone()",
  "function claim(address kol)",
  "error NotReached(uint256 marketCapUsd, uint256 targetUsd)",
  "error NoKols()",
  "error NothingToPay()",
  "error StalePrice(uint256 updatedAt)",
]);
