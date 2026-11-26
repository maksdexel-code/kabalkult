"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { VaultComponentProps } from "@/src/sdk";
import { formatTokenAmount, handleTxError, isActionAvailableForPhase, readTaxVaultHostContext, useFlapSdk } from "@/src/sdk";
import { AddressLink, Alert, Button, Input, StatusBadge } from "@/src/ui";
import { vaultAbi } from "./VaultABI";

// KabalKult KOL vault: black stock, acid-lime rules and type (the mascot's colour), magenta only as a fill.
type Hex = `0x${string}`;
type Deal = {
  mc: bigint; usd: readonly bigint[]; share: readonly number[]; paid: bigint; revenue: bigint; spent: bigint;
  available: bigint; payouts: bigint; payoutToken: Hex; kols: bigint; creator: Hex; buyTax: number; sellTax: number;
  slots: number; slotsTaken: bigint; bnbUsd: bigint; payoutUsd: bigint; updatedAt: bigint; fresh: boolean; source: string;
};
type Me = { number: bigint; confirmed: boolean; invited: boolean; xHandle: string; earnedToken: bigint; earnedBnb: bigint; earnedUsd: bigint; claimToken: bigint; claimBnb: bigint };
type Found = { address: Hex; number: bigint; confirmed: boolean; invited: boolean; xHandle: string; earnedUsd: bigint };

// Mock stocks sold by our StockDesk (declared in manifest externalContracts). Anything else shows as its address.
const STOCK_LABELS: Record<string, string> = {
  "0x687809dad911091f8fdeef50e392734674ca7aaa": "mNVDAb",
  "0x14c502a6920a81a58c14cc554c810af1389efa57": "mTSLAb",
  "0x90a95459ed7caeea5f1fb427cf5502b4651e9b38": "mAAPLb",
};
const RULES = ["rules.tax", "rules.marketCap", "rules.size", "rules.purchase", "rules.kols", "rules.expiry"];
const display = "font-['Impact','Haettenschweiler','Arial_Narrow_Bold',sans-serif] uppercase leading-[0.95] tracking-[0.01em] text-[#c4f004] break-normal [hyphens:none] [text-wrap:balance]"; // whole words only
const cell = "min-w-0 border-[3px] border-[#c4f004] -ml-[3px] -mt-[3px] bg-[#050505] p-4";
const label = "block text-sm text-[#a3ab8c]";
// Amounts stay bigint; only the text gets thousands separators.
const commas = (s: string) => { const [w, f] = s.split("."); return w.replace(/\B(?=(\d{3})+(?!\d))/g, ",") + (f ? `.${f}` : ""); };
const usd = (v: bigint) => `$${commas(formatTokenAmount(v, 18, 0))}`;
const usd2 = (v: bigint) => `$${commas(formatTokenAmount(v, 18, 2))}`;
const isZero = (a: string) => /^0x0{40}$/i.test(a);
const isAddress = (a: string) => /^0x[0-9a-fA-F]{40}$/.test(a);
const short = (a: string) => `${a.slice(0, 6)}…${a.slice(-4)}`;

/** BNB the next checkMilestone() would spend, mirroring KabalKultVault.checkMilestone (0 = it would revert). */
function nextPayout(d: Deal): bigint {
  const n = d.usd.length;
  const paid = Number(d.paid);
  if (!d.fresh || d.kols === 0n || n === 0) return 0n;
  if (paid >= n) return d.mc >= (d.usd[n - 1] ?? 0n) ? d.available : 0n; // after the last milestone: all new tax
  let reached = 0, j = paid;
  while (j < n && d.mc >= (d.usd[j] ?? 0n)) { reached += d.share[j] ?? 0; j++; }
  if (reached === 0) return 0n;
  if (j >= n) return d.available; // the last milestone takes everything
  const paidShare = d.share.slice(0, paid).reduce((a, s) => a + s, 0);
  return (d.available * BigInt(reached)) / BigInt(10_000 - paidShare);
}

export default function KabalkultVault(_props: VaultComponentProps) {
  const sdk = useFlapSdk();
  const { context, i18n, wallet } = sdk;
  const t = i18n.t;
  const host = readTaxVaultHostContext(context.host);
  const riskLevel = host.vaultInfo?.riskLevel ?? host.taxInfo?.vaultInfo?.riskLevel ?? null;
  const riskLabel = riskLevel === 1 ? t("risk.low") : riskLevel === 2 ? t("risk.lowMedium") : riskLevel === 3 ? t("risk.medium") : riskLevel === 4 ? t("risk.high") : riskLevel === 0 ? t("risk.unverified") : t("risk.missing");
  const riskTone = riskLevel === null || riskLevel === 0 || riskLevel >= 4 ? "danger" : riskLevel >= 3 ? "warning" : "success";
  const stageOk = isActionAvailableForPhase("dex-listed", host.marketPhase);
  const validVault = /^0x[0-9a-fA-F]{40}$/.test(context.vaultAddress) && !/^0x0{40}$/i.test(context.vaultAddress);
  const [deal, setDeal] = useState<Deal | null>(null);
  const [me, setMe] = useState<Me | null>(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<"claim" | "pay" | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);
  const [query, setQuery] = useState("");
  const [found, setFound] = useState<Found | null>(null);
  const [lookupError, setLookupError] = useState<string | null>(null);
  const [looking, setLooking] = useState(false);
  const lock = useRef(false);
  const revision = useRef(0);
  const txMessages = useMemo(() => ({ userRejected: t("errors.userRejected"), walletDisconnected: t("errors.walletDisconnected"), insufficientFunds: t("errors.insufficientFunds"), simulationFailed: t("errors.simulationFailed"), reverted: t("errors.reverted"), unknown: t("errors.transaction") }), [t]);

  const read = useCallback(<T,>(functionName: string, args?: readonly unknown[]) =>
    sdk.readContract<T>({ contract: "vault", address: context.vaultAddress, abi: vaultAbi, functionName: functionName as never, args: args as never }),
  [context.vaultAddress, sdk]);

  const load = useCallback(async () => {
    const rev = ++revision.current;
    if (!validVault) { setDeal(null); setMe(null); setLoading(false); setError(t("errors.binding")); return; }
    try {
      const [token, mc, ms, paid, revenue, spent, available, payouts, payoutToken, kols, d, p] = await Promise.all([
        read<Hex>("token"), read<bigint>("marketCapUsdLast"), read<readonly [readonly bigint[], readonly number[]]>("milestones"),
        read<bigint>("milestonesPaid"), read<bigint>("totalRevenue"), read<bigint>("totalSpent"), read<bigint>("available"),
        read<bigint>("payoutCount"), read<Hex>("payoutToken"), read<bigint>("kolCount"),
        read<readonly [Hex, number, number, number, bigint]>("deal"), read<readonly [bigint, bigint, bigint, boolean, string]>("prices"),
      ]);
      if (rev !== revision.current) return;
      if (token.toLowerCase() !== context.tokenAddress.toLowerCase()) { setDeal(null); setError(t("errors.binding")); return; }
      setDeal({
        mc, usd: ms[0], share: ms[1], paid, revenue, spent, available, payouts, payoutToken, kols,
        creator: d[0], buyTax: d[1], sellTax: d[2], slots: d[3], slotsTaken: d[4],
        bnbUsd: p[0], payoutUsd: p[1], updatedAt: p[2], fresh: p[3], source: p[4],
      });
      if (context.userAddress && !wallet.isWrongNetwork) {
        const args = [context.userAddress];
        const [s, e, c] = await Promise.all([
          read<readonly [bigint, boolean, boolean, string]>("kolStatus", args),
          read<readonly [bigint, bigint, bigint]>("earned", args),
          read<readonly [bigint, bigint]>("claimable", args),
        ]);
        if (rev !== revision.current) return;
        setMe({ number: s[0], confirmed: s[1], invited: s[2], xHandle: s[3], earnedToken: e[0], earnedBnb: e[1], earnedUsd: e[2], claimToken: c[0], claimBnb: c[1] });
      } else setMe(null);
      setError(null);
    } catch {
      if (rev === revision.current) { setDeal(null); setMe(null); setError(t("errors.read")); }
    } finally { if (rev === revision.current) setLoading(false); }
  }, [context.tokenAddress, context.userAddress, read, t, validVault, wallet.isWrongNetwork]);

  useEffect(() => {
    setLoading(true); setDone(null);
    void load();
    const timer = setInterval(() => void load(), 15000);
    return () => { clearInterval(timer); revision.current += 1; };
  }, [load, sdk.refetchNonce]);

  // Public check of any wallet: KOL number, confirm badge, proved X handle, USD earned (vault reads only).
  async function lookup() {
    const a = query.trim().toLowerCase(); // lowercase: a mistyped checksum (mixed case) must not fail the read
    setFound(null); setLookupError(null);
    if (!isAddress(a)) { setLookupError(t("errors.badAddress")); return; }
    setLooking(true);
    try {
      const [s, e] = await Promise.all([
        read<readonly [bigint, boolean, boolean, string]>("kolStatus", [a]),
        read<readonly [bigint, bigint, bigint]>("earned", [a]),
      ]);
      setFound({ address: a as Hex, number: s[0], confirmed: s[1], invited: s[2], xHandle: s[3], earnedUsd: e[2] });
    } catch { setLookupError(t("errors.read")); } finally { setLooking(false); }
  }

  const total = deal?.usd.length ?? 0;
  const paidCount = deal ? parseInt(deal.paid.toString(), 10) : 0;
  const next = deal && paidCount < total ? deal.usd[paidCount] : null;
  const payNow = deal ? nextPayout(deal) : 0n;
  const reachedNow = !!deal && deal.fresh && (next !== null ? deal.mc >= next : deal.mc >= (deal.usd[total - 1] ?? 0n));
  const isBnb = !!deal && isZero(deal.payoutToken);
  const payoutLabel = deal ? (isBnb ? "BNB" : STOCK_LABELS[deal.payoutToken.toLowerCase()] ?? null) : null;
  const unit = payoutLabel ?? (deal ? short(deal.payoutToken) : "");
  const walletBlock = !validVault ? t("errors.binding") : wallet.isWrongNetwork ? t("states.wrongNetwork") : !context.userAddress || !wallet.isConnected ? t("states.connect") : !stageOk ? t("states.phase") : loading || !deal ? t("states.loading") : null;
  const claimBlock = walletBlock ?? (!me || (me.claimToken === 0n && me.claimBnb === 0n) ? t("states.nothingToClaim") : null);
  const payBlock = walletBlock ?? (!deal?.fresh ? t("states.stale") : !reachedNow ? t("states.notReached") : payNow === 0n ? t("states.nothingToPay") : null);

  async function send(kind: "claim" | "pay") {
    if (lock.current || (kind === "claim" ? claimBlock : payBlock)) return;
    lock.current = true; setBusy(kind); setError(null); setDone(null);
    try {
      const simulation = await sdk.simulateContract({
        contract: "vault", address: context.vaultAddress, abi: vaultAbi,
        functionName: kind === "claim" ? "claim" : "checkMilestone", args: kind === "claim" ? [context.userAddress] : [],
      } as never);
      const hash = await sdk.writeContract(simulation.request);
      const receipt = await sdk.waitForTx(hash);
      if (receipt.status !== "success") { setError(t("errors.reverted")); return; }
      setDone(kind === "claim" ? t("messages.claimed") : t("messages.paid"));
      sdk.notify.success(kind === "claim" ? t("messages.claimed") : t("messages.paid"));
      await sdk.refetch();
    } catch (cause) {
      // Name the vault's own refusals; everything else goes through the SDK's wallet/tx messages.
      const text = cause instanceof Error ? cause.message : String(cause);
      const known = /NotReached/.test(text) ? t("errors.notReached") : /StalePrice/.test(text) ? t("states.stale")
        : /NothingToPay/.test(text) ? t("errors.nothingToPay") : /NoKols/.test(text) ? t("errors.noKols") : null;
      setError(known ?? handleTxError(cause, txMessages));
    }
    finally { lock.current = false; setBusy(null); }
  }

  const ageMin = deal ? ((BigInt(Math.floor(Date.now() / 1000)) - deal.updatedAt) / 60n).toString() : null;

  return <div className="w-full min-w-0 space-y-4 border-[3px] border-[#c4f004] bg-[#050505] p-4 font-sans text-[#e6f7a8] sm:p-6">
    <div className="flex flex-wrap items-center justify-between gap-3">
      <h2 className={`${display} text-3xl sm:text-4xl`}>{t("title")}</h2>
      <StatusBadge tone={riskTone}>{riskLabel}</StatusBadge>
    </div>
    {riskLevel === null ? <Alert tone="danger">{t("notices.riskMissing")}</Alert> : riskLevel === 0 || riskLevel >= 4 ? <Alert tone="warning">{t("notices.review")}</Alert> : null}
    <p className="max-w-2xl text-base leading-6">{t("description")}</p>

    <div className="flex flex-wrap items-center gap-5">
      {context.tokenImageUrl ? <img src={context.tokenImageUrl} alt={context.tokenSymbol ?? ""} className="h-28 w-28 border-[3px] border-[#c4f004] object-cover" /> : null}
      <div className="min-w-0">
        <span className={label}>{t("labels.marketCap")}</span>
        <span className={`${display} block text-6xl tabular-nums`}>{deal ? usd(deal.mc) : "—"}</span>
        <span className="block text-sm text-[#a3ab8c]">
          {deal ? `${t("labels.priceLive")} ${ageMin} ${t("labels.minAgo")}` : t("states.loading")}
        </span>
        {deal && !deal.fresh ? <span className="mt-1 block text-sm text-[#ff6b6b]">{t("states.stale")}</span> : null}
      </div>
    </div>

    <section aria-label={t("sections.milestones")} className="space-y-2">
      <h3 className={`${display} text-2xl`}>{t("sections.milestones")}</h3>
      <div className="grid pl-[3px] pt-[3px]">
        {deal?.usd.map((target, i) => {
          const isPaid = i < paidCount;
          const isReached = !isPaid && deal.mc >= target;
          const raw = (deal.mc * 100n) / (target === 0n ? 1n : target);
          const pct = (raw > 100n ? 100n : raw).toString();
          return <div key={i} className="grid grid-cols-[56px_minmax(0,1fr)_minmax(0,1fr)_minmax(0,1.2fr)]">
            <div className={`${cell} grid place-items-center !bg-[#c4f004] p-2`}><span className={`${display} text-2xl !text-black tabular-nums`}>{i + 1}</span></div>
            <div className={cell}><span className={label}>{t("labels.target")}</span><span className="text-lg font-bold tabular-nums">{usd(target)}</span></div>
            <div className={cell}><span className={label}>{t("labels.share")}</span><span className="text-lg font-bold tabular-nums">{(deal.share[i] ?? 0) / 100}%</span></div>
            <div className={`${cell} ${isPaid ? "!bg-[#ff2e93] !text-black" : ""}`}>
              <span className={isPaid ? "block text-sm text-black" : label}>{isPaid ? t("states.paid") : isReached ? t("states.reached") : t("states.locked")}</span>
              {!isPaid ? <div className="mt-2 h-2 bg-[#1b1f0a]"><div className="h-2 bg-[#c4f004]" style={{ width: `${pct}%` }} /></div> : <span className="text-lg font-bold">✓</span>}
            </div>
          </div>;
        }) ?? <p className="text-sm text-[#a3ab8c]">{loading ? t("states.loading") : t("errors.read")}</p>}
      </div>
      {deal && paidCount >= total && total > 0 ? <p className="text-sm text-[#a3ab8c]">{t("notices.afterLast")}</p> : null}
    </section>

    <div className="grid grid-cols-2 pl-[3px] pt-[3px] lg:grid-cols-4">
      <div className={cell}><span className={label}>{t("labels.vaultBalance")}</span><span className="text-xl font-bold tabular-nums">{deal ? formatTokenAmount(deal.available, 18) : "—"} tBNB</span></div>
      <div className={cell}><span className={label}>{t("labels.revenue")}</span><span className="text-xl font-bold tabular-nums">{deal ? formatTokenAmount(deal.revenue, 18) : "—"} tBNB</span></div>
      <div className={cell}><span className={label}>{t("labels.paidIn")}</span><span className="text-xl font-bold">{payoutLabel ?? (deal ? <AddressLink address={deal.payoutToken} explorerBaseUrl={context.explorerBaseUrl} /> : "—")}</span>
        {deal && deal.payoutUsd > 0n ? <span className="block text-sm text-[#a3ab8c] tabular-nums">{usd2(deal.payoutUsd)}</span> : null}</div>
      <div className={cell}><span className={label}>{t("labels.kols")}</span><span className="text-xl font-bold tabular-nums">{deal ? deal.kols.toString() : "—"}</span>
        {deal ? <span className="block text-sm text-[#a3ab8c] tabular-nums">{t("labels.slots")} {deal.slotsTaken.toString()}/{deal.slots}</span> : null}</div>
    </div>
    {deal && !payoutLabel ? <p className="text-sm text-[#a3ab8c]">{t("notices.unknownToken")}</p> : null}

    <section aria-label={t("sections.you")} className="space-y-3 border-[3px] border-[#c4f004] p-4">
      <h3 className={`${display} text-2xl`}>{t("sections.you")}</h3>
      <p className="text-base">
        {!context.userAddress ? t("states.connect")
          : wallet.isWrongNetwork ? t("states.wrongNetwork")
          : !me ? t("states.loading")
          : me.number > 0n ? `${t("labels.onList")}, ${me.confirmed ? t("labels.confirmed") : t("labels.notConfirmed")}${me.xHandle ? `, ${t("labels.postedOnX")} @${me.xHandle}` : ""}`
          : me.invited ? t("labels.invitedNotJoined") : t("labels.notKol")}
      </p>
      {me && me.number > 0n ? <div className="grid grid-cols-2 pl-[3px] pt-[3px] sm:grid-cols-3">
        <div className={cell}><span className={label}>{t("labels.earned")}</span><span className="text-xl font-bold tabular-nums">{formatTokenAmount(me.earnedToken, 18, 6)} {isBnb ? "" : unit}</span>
          {me.earnedBnb > 0n ? <span className="block text-sm tabular-nums">+ {formatTokenAmount(me.earnedBnb, 18, 6)} tBNB</span> : null}</div>
        <div className={cell}><span className={label}>{t("labels.earnedUsd")}</span><span className="text-xl font-bold tabular-nums">{usd2(me.earnedUsd)}</span></div>
        <div className={cell}><span className={label}>{t("labels.claimable")}</span><span className="text-xl font-bold tabular-nums">{formatTokenAmount(me.claimToken, 18, 6)} {isBnb ? "" : unit}</span>
          {me.claimBnb > 0n ? <span className="block text-sm tabular-nums">+ {formatTokenAmount(me.claimBnb, 18, 6)} tBNB</span> : null}</div>
      </div> : null}
      <div className="flex flex-wrap gap-3">
        <Button type="button" disabled={Boolean(claimBlock) || busy !== null} loading={busy === "claim"} onClick={() => void send("claim")}
          className="h-12 rounded-none border-[3px] border-[#c4f004] bg-[#ff2e93] px-6 font-['Impact',sans-serif] text-lg uppercase text-black hover:bg-[#c4f004]">
          {busy === "claim" ? t("actions.confirming") : t("actions.claim")}
        </Button>
        <Button type="button" variant="outline" disabled={Boolean(payBlock) || busy !== null} loading={busy === "pay"} onClick={() => void send("pay")}
          className="h-12 rounded-none border-[3px] border-[#c4f004] bg-[#050505] px-6 font-['Impact',sans-serif] text-lg uppercase text-[#c4f004] hover:bg-[#c4f004] hover:text-black">
          {busy === "pay" ? t("actions.confirming") : t("actions.pay")}
        </Button>
      </div>
      {claimBlock && context.userAddress ? <p className="text-sm text-[#a3ab8c]">{claimBlock}</p> : null}
      {payBlock && payBlock !== claimBlock ? <p className="text-sm text-[#a3ab8c]">{t("labels.payHint")} {payBlock}</p> : null}
      <p className="text-sm text-[#a3ab8c]">{t("notices.payAnyone")}</p>
      {done ? <Alert tone="success">{done}</Alert> : null}
      {error ? <Alert tone="danger">{error}</Alert> : null}
    </section>

    <section aria-label={t("sections.lookup")} className="space-y-3">
      <h3 className={`${display} text-2xl`}>{t("sections.lookup")}</h3>
      <p className="text-sm text-[#a3ab8c]">{t("notices.lookup")}</p>
      <div className="flex flex-wrap gap-3">
        <Input value={query} onChange={e => setQuery(e.target.value)} onKeyDown={e => { if (e.key === "Enter") void lookup(); }}
          placeholder={t("labels.lookupPlaceholder")} aria-label={t("sections.lookup")}
          className="h-12 min-w-0 flex-1 rounded-none border-[3px] border-[#c4f004] bg-[#050505] font-mono text-sm text-[#e6f7a8]" />
        <Button type="button" variant="outline" disabled={looking || !validVault} loading={looking} onClick={() => void lookup()}
          className="h-12 rounded-none border-[3px] border-[#c4f004] bg-[#050505] px-6 font-['Impact',sans-serif] text-lg uppercase text-[#c4f004] hover:bg-[#c4f004] hover:text-black">
          {t("actions.check")}
        </Button>
      </div>
      {lookupError ? <p className="text-sm text-[#ff6b6b]">{lookupError}</p> : null}
      {found ? <div className={`border-[3px] border-[#c4f004] p-4 text-base ${found.confirmed ? "bg-[#ff2e93] text-black" : ""}`}>
        <AddressLink address={found.address} explorerBaseUrl={context.explorerBaseUrl} />
        <span className="block font-bold">
          {found.number > 0n
            ? `${t("labels.onList")}, ${found.invited ? t("labels.slotHolder") : t("labels.named")}, ${found.confirmed ? `✓ ${t("labels.confirmed")}` : t("labels.notConfirmed")}${found.xHandle ? `, ${t("labels.postedOnX")} @${found.xHandle}` : ""}`
            : found.invited ? t("labels.invitedOnly") : t("labels.notOnList")}
        </span>
        {found.number > 0n ? <span className="block text-sm">{usd2(found.earnedUsd)} {t("labels.earnedSoFar")}</span> : null}
      </div> : null}
    </section>

    <section aria-label={t("sections.rules")} className="space-y-2">
      <h3 className={`${display} text-2xl`}>{t("sections.rules")}</h3>
      <ul className="list-disc space-y-1 pl-5 text-sm leading-6">
        {RULES.map(k => <li key={k}>{t(k)}</li>)}
      </ul>
    </section>

    {deal ? <p className="text-sm text-[#a3ab8c]">
      {t("labels.tax")} {deal.buyTax / 100}% / {deal.sellTax / 100}%, {t("labels.payouts")} {deal.payouts.toString()}, {t("labels.creator")} <AddressLink address={deal.creator} explorerBaseUrl={context.explorerBaseUrl} />
    </p> : null}
    <p className="text-sm text-[#a3ab8c]">{t("notices.testnet")}</p>
  </div>;
}
