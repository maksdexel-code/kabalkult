import { useEffect, useRef, useState, type CSSProperties, type ReactNode } from "react";

// KabalKult Launcher UI for Flap Pool Launch (launcher-config-preview/v1).
// LauncherConfig = the create page (hero + deal form); Launcher = the deal page (status, Confirm, Join, Launch).

type Messages = Record<string, string>;
type Identity = Readonly<{ chainId: number; factoryAddress: string }>;
type Wallet = Readonly<{
  account: string | null;
  chainId: number | null;
  pendingHash?: string | null;
  connect(): void;
  switchChain(): Promise<void>;
}>;
type Action = "launch" | "confirm" | "joinCampaign";
type Submission = { status: "success" | "pending" | "reverted" | "unverified"; hash: string; launcherAddress?: string };
type AbiParameter = { name: string; type: string; components?: readonly AbiParameter[] };
type Host = Readonly<{
  wallet?: Wallet;
  quote?(): Promise<string | null>;
  encode?(parameters: readonly AbiParameter[], values: readonly unknown[]): string;
  findSalt?(): Promise<string>;
  submit?(input: { kind: "create"; configuration: string; valueWei: string }
    | { kind: "action"; action: Action; valueWei?: string }): Promise<Submission>;
  checkReceipt?(hash: string): Promise<Submission>;
  refresh?(): void;
  redirect?(path: string): boolean;
  openLauncher?(address: string): void;
}>;
type Snapshot = Readonly<{
  launched?: boolean | null;
  token?: string | null;
  creator?: string | null;
  poolQuote?: string | null;
  vault?: string | null;
  kolCount?: string | null;
  campaignSlots?: string | null;
  campaignSlotsTaken?: string | null;
  buyTaxBps?: string | null;
  sellTaxBps?: string | null;
  payoutToken?: string | null;
  milestoneCount?: string | null;
  kolNumber?: string | null;
  confirmed?: boolean | null;
  invited?: boolean | null;
}>;
type ConfigProps = { context: Readonly<{ identity: Identity; locale: string }>; messages: Messages; host?: Host };
type DetailProps = {
  context: Readonly<{ identity: Identity; locale: string; launcherAddress: string | null; snapshot: Snapshot | null }>;
  messages: Messages;
  host?: Host;
};

// ─── Look: black stock, acid-lime ink and 3px rules (the mascot's colour), magenta only as a fill ───
const black = "#050505";
const panel = "#0d0d0b";
const lime = "#c4f004";
const limeSoft = "#e6f7a8";
const muted = "#a3ab8c";
const magenta = "#ff2e93";
const danger = "#ff6b6b";
const rule = `3px solid ${lime}`;
const hair = `1px solid #3a4210`;
const display = 'Impact, Haettenschweiler, "Arial Narrow Bold", "Franklin Gothic Heavy", sans-serif';
const body = 'ui-sans-serif, system-ui, -apple-system, "Segoe UI", "PingFang SC", sans-serif';

const shell: CSSProperties = {
  background: black, color: limeSoft, fontFamily: body, fontSize: 16, lineHeight: 1.5,
  border: rule, borderRadius: 0, overflow: "hidden", colorScheme: "dark", accentColor: magenta,
  maxWidth: 1180, marginInline: "auto",
};
const pad = "clamp(16px, 4vw, 40px)";
const head = (size: string): CSSProperties => ({
  fontFamily: display, textTransform: "uppercase", fontWeight: 400, letterSpacing: "0.01em",
  lineHeight: 0.95, color: lime, margin: 0, fontSize: size, overflowWrap: "break-word", minWidth: 0,
});
const label: CSSProperties = { fontSize: 14, color: muted, display: "block", marginBottom: 6 };
const input: CSSProperties = {
  width: "100%", boxSizing: "border-box", minHeight: 48, padding: "10px 12px", background: panel,
  color: limeSoft, border: rule, borderRadius: 0, fontSize: 16, fontFamily: body,
};
const nums: CSSProperties = { fontVariantNumeric: "tabular-nums" };

function Button({ children, onClick, primary, disabled, wide }: {
  children: ReactNode; onClick?(): void; primary?: boolean; disabled?: boolean; wide?: boolean;
}) {
  const [hover, setHover] = useState(false);
  const fill = primary ? (hover ? lime : magenta) : (hover ? lime : black);
  return (
    <button type="button" onClick={onClick} disabled={disabled}
      onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}
      onFocus={() => setHover(true)} onBlur={() => setHover(false)}
      style={{
        minHeight: 52, padding: "0 26px", border: rule, borderRadius: 0, cursor: disabled ? "not-allowed" : "pointer",
        background: disabled ? panel : fill, color: disabled ? muted : (primary || hover ? black : lime),
        fontFamily: display, textTransform: "uppercase", fontSize: 22, letterSpacing: "0.02em",
        width: wide ? "100%" : undefined, outline: hover ? `3px solid ${magenta}` : "none", outlineOffset: 3,
      }}>
      {children}
    </button>
  );
}

function Cell({ children, ink, style }: { children: ReactNode; ink?: boolean; style?: CSSProperties }) {
  return <div style={{ border: rule, margin: "-3px 0 0 -3px", padding: 18, background: ink ? lime : black, color: ink ? black : limeSoft, minWidth: 0, ...style }}>{children}</div>;
}

// ─── Mascot: almost still; now and then a glitch (magenta ghost + skew) or a wink ───
const reducedMotion = () => typeof window !== "undefined" && !!window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;

function Mascot({ size, alt }: { size: string; alt: string }) {
  const [mood, setMood] = useState<"still" | "glitch" | "wink">("still");
  useEffect(() => {
    if (reducedMotion()) return;
    let timer: ReturnType<typeof setTimeout>;
    const next = () => {
      timer = setTimeout(() => {
        setMood(Math.random() < 0.6 ? "glitch" : "wink");
        timer = setTimeout(() => { setMood("still"); next(); }, 180);
      }, 2600 + Math.random() * 5200);
    };
    next();
    return () => clearTimeout(timer);
  }, []);
  const glitch = mood === "glitch";
  return (
    <div style={{ position: "relative", width: size, aspectRatio: "1 / 1", flexShrink: 0 }}>
      <img src={MASCOT} alt="" aria-hidden="true" style={{
        position: "absolute", inset: 0, width: "100%", height: "100%", opacity: glitch ? 0.9 : 0,
        transform: "translate(7px, -3px)", filter: "hue-rotate(250deg) saturate(3)", mixBlendMode: "screen",
      }} />
      <img src={MASCOT} alt={alt} style={{
        position: "relative", width: "100%", height: "100%", display: "block", mixBlendMode: "lighten",
        transform: glitch ? "skewX(-4deg) translateX(-3px)" : "none",
      }} />
      {mood === "wink" && (
        <div aria-hidden="true" style={{
          position: "absolute", left: "53.5%", top: "51.5%", width: "12%", height: "5.5%",
          background: black, borderBottom: `3px solid ${lime}`, transform: "rotate(-6deg)",
        }} />
      )}
    </div>
  );
}

// ─── Helpers ───
const addressPattern = /^0x[0-9a-fA-F]{40}$/;
const zero = "0x0000000000000000000000000000000000000000";
const STOCKS: ReadonlyArray<{ key: string; label: string; address: string }> = [
  { key: "nvda", label: "mNVDAb", address: "0x687809daD911091f8FdEEf50E392734674CA7AaA" },
  { key: "tsla", label: "mTSLAb", address: "0x14c502a6920A81A58C14CC554C810Af1389eFa57" },
  { key: "aapl", label: "mAAPLb", address: "0x90A95459ED7CaeEa5f1FB427Cf5502B4651E9B38" },
];
const payoutName = (address: string | null | undefined, m: Messages) => {
  if (!address || address.toLowerCase() === zero) return "BNB";
  return STOCKS.find(s => s.address.toLowerCase() === address.toLowerCase())?.label ?? short(address) ?? m.unknown;
};
const short = (a: string | null | undefined) => (a && addressPattern.test(a) ? `${a.slice(0, 6)}…${a.slice(-4)}` : null);
const isHash = (v: unknown): v is string => typeof v === "string" && /^0x[0-9a-fA-F]{64}$/.test(v);

/** Decimal string → integer with `decimals` places, or null if malformed. */
function units(value: string, decimals: number): bigint | null {
  const v = value.trim();
  if (!/^\d+(\.\d+)?$/.test(v)) return null;
  const [whole, frac = ""] = v.split(".");
  if (frac.length > decimals) return null;
  return BigInt(whole) * 10n ** BigInt(decimals) + BigInt(frac.padEnd(decimals, "0") || "0");
}
const fromUnits = (value: string | null | undefined, decimals: number, digits = 4) => {
  if (!value || !/^\d+$/.test(value)) return "—";
  const n = Number(BigInt(value)) / 10 ** decimals;
  return n.toLocaleString("en-US", { maximumFractionDigits: digits });
};
// Flap's Portal liquidity floor on BSC testnet, measured 25 Nov 2026 (~1.07 tBNB).
// shortcut: fixed here because the create page gets no chain reads; the Portal stays the real check.
const MIN_RAISE_WEI = 1_070_000_000_000_000_000n;
const wallets = (text: string) => text.split(/[\s,;]+/).map(s => s.trim()).filter(Boolean);

const configParameters: readonly AbiParameter[] = [{
  name: "c", type: "tuple", components: [
    { name: "name", type: "string" }, { name: "symbol", type: "string" }, { name: "meta", type: "string" },
    { name: "salt", type: "bytes32" }, { name: "poolQuote", type: "uint256" },
    { name: "namedKols", type: "address[]" }, { name: "invitees", type: "address[]" },
    { name: "campaignSlots", type: "uint32" }, { name: "milestoneUsd", type: "uint256[]" },
    { name: "milestoneShareBps", type: "uint16[]" }, { name: "buyTaxBps", type: "uint16" },
    { name: "sellTaxBps", type: "uint16" }, { name: "payoutToken", type: "address" },
  ],
}];

type Milestone = { usd: string; share: string };
type Form = {
  name: string; symbol: string; meta: string; pool: string; buyTax: string; sellTax: string;
  payout: string; customPayout: string; milestones: Milestone[]; kols: string; invitees: string; slots: string;
};
const initialForm: Form = {
  name: "", symbol: "", meta: "", pool: "1.1", buyTax: "5", sellTax: "5", payout: "nvda", customPayout: "",
  milestones: [{ usd: "730", share: "10" }, { usd: "850", share: "20" }, { usd: "975", share: "30" }, { usd: "1100", share: "40" }],
  kols: "", invitees: "", slots: "50",
};

/** Validates the draft; returns encoded-ready values or a list of message keys for what is wrong. */
function review(form: Form) {
  const problems: string[] = [];
  const name = form.name.trim(), symbol = form.symbol.trim();
  if (!name || !symbol) problems.push("errToken");
  const poolQuote = units(form.pool, 18);
  if (poolQuote === null || poolQuote < MIN_RAISE_WEI) problems.push("errPool");
  const buy = units(form.buyTax, 2), sell = units(form.sellTax, 2);
  if (buy === null || sell === null || buy > 1000n || sell > 1000n || (buy > sell ? buy : sell) < 100n) problems.push("errTax");
  const stock = STOCKS.find(s => s.key === form.payout);
  const payoutToken = form.payout === "bnb" ? zero : stock ? stock.address : form.customPayout.trim();
  if (!addressPattern.test(payoutToken)) problems.push("errPayout");
  const usd = form.milestones.map(x => units(x.usd, 18));
  const share = form.milestones.map(x => units(x.share, 2));
  const rising = usd.every((u, i) => u !== null && u > 0n && (i === 0 || (usd[i - 1] ?? 0n) < u));
  const total = share.reduce<bigint>((a, s) => a + (s ?? 0n), 0n);
  if (form.milestones.length < 1 || form.milestones.length > 10 || !rising || share.some(s => s === null || s === 0n) || total !== 10_000n) {
    problems.push("errMilestones");
  }
  const kols = wallets(form.kols), invitees = wallets(form.invitees);
  if (kols.some(a => !addressPattern.test(a)) || kols.length > 100) problems.push("errKols");
  if (invitees.some(a => !addressPattern.test(a)) || invitees.length > 1000) problems.push("errInvitees");
  const slots = /^\d{1,5}$/.test(form.slots.trim()) ? Number(form.slots.trim()) : -1;
  if (slots < 0) problems.push("errSlots");
  if (kols.length === 0 && (invitees.length === 0 || slots === 0)) problems.push("errNobody");
  if (problems.length) return { problems, values: null };
  return {
    problems,
    values: {
      name, symbol, meta: form.meta.trim(), poolQuote: poolQuote as bigint, namedKols: kols, invitees,
      campaignSlots: slots, milestoneUsd: usd as bigint[], milestoneShareBps: share.map(s => Number(s)),
      buyTaxBps: Number(buy), sellTaxBps: Number(sell), payoutToken,
    },
  };
}

// ─── LauncherConfig: the create page ───
export function LauncherConfig({ context, messages: m, host }: ConfigProps) {
  const [form, setForm] = useState<Form>(initialForm);
  const [open, setOpen] = useState(false);
  const [checked, setChecked] = useState(false);
  const [fee, setFee] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [receipt, setReceipt] = useState<Submission | null>(null);
  const lock = useRef(false);
  const account = host?.wallet?.account ?? null;
  const wrongChain = !!account && host?.wallet?.chainId !== context.identity.chainId;
  const canTransact = !!host?.wallet && !!host?.quote && !!host?.findSalt && !!host?.encode && !!host?.submit;
  const draft = review(form);
  const created = receipt?.status === "success" && receipt.launcherAddress && addressPattern.test(receipt.launcherAddress)
    ? receipt.launcherAddress : null;

  const set = (patch: Partial<Form>) => { setForm(f => ({ ...f, ...patch })); setChecked(false); setError(null); };
  const setMilestone = (i: number, patch: Partial<Milestone>) =>
    set({ milestones: form.milestones.map((x, j) => (j === i ? { ...x, ...patch } : x)) });

  async function showReview() {
    setChecked(true);
    if (!draft.values || lock.current) return;
    lock.current = true; setBusy(true); setError(null);
    try {
      const q = canTransact ? await host?.quote?.() : null;
      setFee(q != null && /^\d+$/.test(q) ? q : null);
      if (canTransact && (q == null || !/^\d+$/.test(q))) setError(m.feeUnavailable);
    } catch { setError(m.feeUnavailable); } finally { lock.current = false; setBusy(false); }
  }

  async function create() {
    if (!draft.values || !canTransact || lock.current || created) return;
    if (!account) { host?.wallet?.connect(); return; }
    lock.current = true; setBusy(true); setError(null);
    try {
      if (wrongChain) { await host?.wallet?.switchChain(); return; }
      const q = await host?.quote?.();
      if (q == null || !/^\d+$/.test(q)) { setError(m.feeUnavailable); return; }
      const salt = await host?.findSalt?.();
      if (!isHash(salt)) { setError(m.prepareError); return; }
      const configuration = host?.encode?.(configParameters, [{ ...draft.values, salt }]);
      if (!configuration) { setError(m.prepareError); return; }
      const result = await host?.submit?.({ kind: "create", configuration, valueWei: q });
      if (result) setReceipt(result);
    } catch { setError(m.submitError); } finally { lock.current = false; setBusy(false); }
  }

  async function recheck() {
    if (!receipt || !isHash(receipt.hash) || lock.current) return;
    lock.current = true; setBusy(true);
    try { const r = await host?.checkReceipt?.(receipt.hash); if (r) setReceipt(r); }
    catch { setError(m.receiptError); } finally { lock.current = false; setBusy(false); }
  }

  const shareTotal = form.milestones.reduce((a, x) => a + (Number(x.share) || 0), 0);

  return (
    <section style={shell} aria-label={m.createTitle}>
      {/* Screen 1: the mascot, the promise, one action, and proof beside it */}
      <div style={{ display: "flex", flexWrap: "wrap", alignItems: "center", gap: "clamp(16px, 3vw, 40px)", padding: pad }}>
        <Mascot size="clamp(180px, 30vw, 340px)" alt={m.mascotAlt} />
        <div style={{ flex: "1 1 320px", minWidth: 0, display: "grid", gap: 18 }}>
          <h1 style={head("clamp(44px, 7vw, 92px)")}>{m.heroTitle}</h1>
          <p style={{ margin: 0, fontSize: 19, maxWidth: 560 }}>{m.heroLine}</p>
          <div><Button primary onClick={() => setOpen(true)}>{m.cta}</Button></div>
        </div>
        <div style={{ flex: "1 1 240px", minWidth: 0, display: "grid" }}>
          <Cell ink><p style={{ ...head("28px"), color: black }}>{m.proofTitle}</p></Cell>
          <Cell><p style={{ margin: 0 }}><span style={{ ...head("40px"), ...nums }}>4/4</span> {m.proofMilestones}</p></Cell>
          <Cell><p style={{ margin: 0 }}><span style={{ ...head("40px"), ...nums }}>$4.93</span> {m.proofKols}</p></Cell>
          <Cell><p style={{ margin: 0, color: muted, fontSize: 14 }}>{m.proofNote}</p></Cell>
        </div>
      </div>

      {open && (
        <div style={{ borderTop: rule, padding: pad, display: "grid", gap: 28 }}>
          <h2 style={head("clamp(32px, 4vw, 48px)")}>{m.formTitle}</h2>

          <fieldset disabled={busy || !!created} style={{ border: 0, padding: 0, margin: 0, display: "grid", gap: 28, minWidth: 0 }}>
            <Group title={m.tokenSection}>
              <Field label={m.name}><input style={input} value={form.name} maxLength={32} onChange={e => set({ name: e.target.value })} placeholder="KabalKult" /></Field>
              <Field label={m.symbol}><input style={input} value={form.symbol} maxLength={12} onChange={e => set({ symbol: e.target.value.toUpperCase() })} placeholder="KKULT" /></Field>
              <Field label={m.meta}><input style={input} value={form.meta} onChange={e => set({ meta: e.target.value })} placeholder="bafkrei…" /></Field>
              <Field label={m.pool}><input style={{ ...input, ...nums }} inputMode="decimal" value={form.pool} onChange={e => set({ pool: e.target.value })} />
                <span style={{ display: "block", marginTop: 6, fontSize: 14, color: muted }}>{m.poolHint}</span></Field>
            </Group>

            <Group title={m.taxSection}>
              <Field label={m.buyTax}><input style={{ ...input, ...nums }} inputMode="decimal" value={form.buyTax} onChange={e => set({ buyTax: e.target.value })} /></Field>
              <Field label={m.sellTax}><input style={{ ...input, ...nums }} inputMode="decimal" value={form.sellTax} onChange={e => set({ sellTax: e.target.value })} /></Field>
              <p style={{ margin: 0, color: muted, fontSize: 14, gridColumn: "1 / -1" }}>{m.taxHint}</p>
            </Group>

            <div style={{ display: "grid", gap: 12 }}>
              <h3 style={head("26px")}>{m.payoutSection}</h3>
              <div role="radiogroup" aria-label={m.payoutSection} style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(min(100%, 150px), 1fr))", paddingLeft: 3, paddingTop: 3 }}>
                {[...STOCKS.map(s => ({ key: s.key, label: s.label })), { key: "bnb", label: "BNB" }, { key: "custom", label: m.customToken }].map(o => {
                  const on = form.payout === o.key;
                  return (
                    <button key={o.key} type="button" role="radio" aria-checked={on} onClick={() => set({ payout: o.key })} style={{
                      border: rule, margin: "-3px 0 0 -3px", minHeight: 64, background: on ? magenta : black, color: on ? black : lime,
                      fontFamily: display, fontSize: 24, cursor: "pointer", borderRadius: 0,
                    }}>{o.label}</button>
                  );
                })}
              </div>
              {form.payout === "custom" && (
                <Field label={m.customTokenLabel}><input style={input} value={form.customPayout} onChange={e => set({ customPayout: e.target.value })} placeholder="0x…" /></Field>
              )}
              <p style={{ margin: 0, color: muted, fontSize: 14 }}>{m.payoutHint}</p>
            </div>

            <div style={{ display: "grid", gap: 12 }}>
              <h3 style={head("26px")}>{m.milestoneSection}</h3>
              <p style={{ margin: 0, color: muted, fontSize: 14 }}>{m.milestoneHint}</p>
              <div style={{ display: "grid", paddingLeft: 3, paddingTop: 3 }}>
                {form.milestones.map((x, i) => (
                  <div key={i} style={{ display: "grid", gridTemplateColumns: "56px minmax(0,1fr) minmax(0,1fr) 56px", alignItems: "stretch" }}>
                    <Cell ink style={{ padding: 8, display: "grid", placeItems: "center" }}><span style={{ ...head("28px"), color: black, ...nums }}>{i + 1}</span></Cell>
                    <Cell style={{ padding: 8 }}>
                      <label style={{ ...label, marginBottom: 2 }}>{m.milestoneUsd}
                        <input style={{ ...input, border: 0, minHeight: 40, ...nums }} inputMode="decimal" value={x.usd} onChange={e => setMilestone(i, { usd: e.target.value })} /></label>
                    </Cell>
                    <Cell style={{ padding: 8 }}>
                      <label style={{ ...label, marginBottom: 2 }}>{m.milestoneShare}
                        <input style={{ ...input, border: 0, minHeight: 40, ...nums }} inputMode="decimal" value={x.share} onChange={e => setMilestone(i, { share: e.target.value })} /></label>
                    </Cell>
                    <Cell style={{ padding: 0 }}>
                      <button type="button" aria-label={m.removeMilestone} disabled={form.milestones.length === 1}
                        onClick={() => set({ milestones: form.milestones.filter((_, j) => j !== i) })}
                        style={{ width: "100%", height: "100%", minHeight: 56, background: black, color: lime, border: 0, fontSize: 24, cursor: "pointer" }}>×</button>
                    </Cell>
                  </div>
                ))}
              </div>
              <div style={{ display: "flex", gap: 16, alignItems: "center", flexWrap: "wrap" }}>
                <Button disabled={form.milestones.length >= 10} onClick={() => set({ milestones: [...form.milestones, { usd: "", share: "" }] })}>{m.addMilestone}</Button>
                <span style={{ ...nums, color: shareTotal === 100 ? lime : danger }}>{m.shareTotal} {shareTotal}%</span>
              </div>
            </div>

            <Group title={m.kolSection}>
              <Field label={m.kols} wide><textarea style={{ ...input, minHeight: 96 }} value={form.kols} onChange={e => set({ kols: e.target.value })} placeholder="0x…, 0x…" /></Field>
              <Field label={m.invitees} wide><textarea style={{ ...input, minHeight: 96 }} value={form.invitees} onChange={e => set({ invitees: e.target.value })} placeholder="0x…, 0x…" /></Field>
              <Field label={m.slots}><input style={{ ...input, ...nums }} inputMode="numeric" value={form.slots} onChange={e => set({ slots: e.target.value })} /></Field>
              <p style={{ margin: 0, color: muted, fontSize: 14, gridColumn: "1 / -1" }}>{m.kolHint}</p>
            </Group>
          </fieldset>

          {checked && draft.problems.length > 0 && (
            <div role="alert" style={{ border: `3px solid ${danger}`, padding: 16, color: danger }}>
              {draft.problems.map(k => <p key={k} style={{ margin: "2px 0" }}>{m[k]}</p>)}
            </div>
          )}

          {checked && draft.values && (
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(min(100%, 220px), 1fr))", paddingLeft: 3, paddingTop: 3 }}>
              <Cell><span style={label}>{m.reviewToken}</span>{draft.values.name} ({draft.values.symbol})</Cell>
              <Cell><span style={label}>{m.reviewTax}</span><span style={nums}>{form.buyTax}% / {form.sellTax}%</span></Cell>
              <Cell><span style={label}>{m.reviewPayout}</span>{payoutName(draft.values.payoutToken, m)}</Cell>
              <Cell><span style={label}>{m.reviewMilestones}</span><span style={nums}>{form.milestones.map(x => `$${x.usd} → ${x.share}%`).join(", ")}</span></Cell>
              <Cell><span style={label}>{m.reviewKols}</span><span style={nums}>{draft.values.namedKols.length} {m.named}, {draft.values.invitees.length} {m.invited}, {draft.values.campaignSlots} {m.slotsWord}</span></Cell>
              <Cell><span style={label}>{m.reviewCost}</span><span style={nums}>{m.toCreate} {fee ? `${fromUnits(fee, 18, 4)} BNB` : m.feeOnConnect}<br />{m.atLaunch} {form.pool} BNB</span></Cell>
            </div>
          )}

          {error && <p role="alert" style={{ margin: 0, color: danger }}>{error}</p>}

          <div style={{ display: "flex", gap: 16, flexWrap: "wrap", alignItems: "center" }}>
            {!checked || !draft.values ? (
              <Button primary onClick={showReview} disabled={busy}>{m.reviewButton}</Button>
            ) : created ? (
              <Button primary onClick={() => host?.openLauncher?.(created)}>{m.openDeal}</Button>
            ) : receipt && receipt.status !== "success" ? (
              <Button onClick={recheck} disabled={busy}>{m.recheck}</Button>
            ) : (
              <Button primary onClick={create} disabled={busy || !canTransact}>
                {!account ? m.connect : wrongChain ? m.switchChain : busy ? m.working : m.createButton}
              </Button>
            )}
            {!canTransact && <span style={{ color: muted, fontSize: 14 }}>{m.previewOnly}</span>}
            {receipt && <span style={{ color: receipt.status === "success" ? lime : danger, fontSize: 14 }}>{m[`status_${receipt.status}`]}</span>}
          </div>
        </div>
      )}
    </section>
  );
}

function Group({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div style={{ display: "grid", gap: 12 }}>
      <h3 style={head("26px")}>{title}</h3>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(min(100%, 230px), 1fr))", gap: 16 }}>{children}</div>
    </div>
  );
}

function Field({ label: text, children, wide }: { label: string; children: ReactNode; wide?: boolean }) {
  return <label style={{ display: "block", minWidth: 0, gridColumn: wide ? "1 / -1" : undefined }}><span style={label}>{text}</span>{children}</label>;
}

// ─── Launcher: the deal page ───
export function Launcher({ context, messages: m, host }: DetailProps) {
  const s = context.snapshot;
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<string | null>(null);
  const lock = useRef(false);
  const account = host?.wallet?.account?.toLowerCase() ?? null;
  const wrongChain = !!account && host?.wallet?.chainId !== context.identity.chainId;
  const isCreator = !!account && !!s?.creator && s.creator.toLowerCase() === account;
  const kolNumber = s?.kolNumber && /^\d+$/.test(s.kolNumber) ? Number(s.kolNumber) : 0;
  const slotsLeft = Number(s?.campaignSlots ?? 0) - Number(s?.campaignSlotsTaken ?? 0);

  async function act(action: Action, valueWei?: string) {
    if (lock.current || !host?.submit) return;
    if (!account) { host.wallet?.connect(); return; }
    lock.current = true; setBusy(true); setNote(null);
    try {
      if (wrongChain) { await host.wallet?.switchChain(); return; }
      const r = await host.submit({ kind: "action", action, valueWei });
      setNote(m[`status_${r.status}`] ?? r.status);
      host.refresh?.();
    } catch { setNote(m.submitError); } finally { lock.current = false; setBusy(false); }
  }

  if (!context.launcherAddress || !s) {
    return <section style={{ ...shell, padding: pad }}><p style={{ margin: 0 }}>{m.loading}</p></section>;
  }

  const role = isCreator ? m.roleCreator
    : kolNumber > 0 ? `${m.roleKol} #${kolNumber}, ${s.confirmed ? m.confirmedBadge : m.notConfirmed}`
    : s.invited ? m.roleInvited : account ? m.roleGuest : m.roleDisconnected;

  return (
    <section style={shell} aria-label={m.detailTitle}>
      <div style={{ display: "flex", flexWrap: "wrap", gap: "clamp(16px, 3vw, 32px)", alignItems: "center", padding: pad, borderBottom: rule }}>
        <Mascot size="clamp(120px, 16vw, 180px)" alt={m.mascotAlt} />
        <div style={{ flex: "1 1 300px", minWidth: 0, display: "grid", gap: 10 }}>
          <h1 style={head("clamp(36px, 5vw, 64px)")}>{s.launched ? m.liveTitle : m.preTitle}</h1>
          <p style={{ margin: 0 }}>{s.launched ? m.liveLine : m.preLine}</p>
          <p style={{ margin: 0, color: magenta, fontWeight: 700 }}>{role}</p>
        </div>
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(min(100%, 300px), 1fr))", padding: `0 ${pad}`, paddingTop: 3, paddingLeft: `calc(${pad} + 3px)`, marginTop: pad }}>
        <Cell><span style={label}>{m.statTax}</span><span style={{ ...head("34px"), ...nums }}>{fromUnits(s.buyTaxBps, 2, 2)}% / {fromUnits(s.sellTaxBps, 2, 2)}%</span></Cell>
        <Cell><span style={label}>{m.statPayout}</span><span style={{ ...head("34px"), textTransform: "none" }}>{payoutName(s.payoutToken, m)}</span></Cell>
        <Cell><span style={label}>{m.statMilestones}</span><span style={{ ...head("34px"), ...nums }}>{s.milestoneCount ?? "—"}</span></Cell>
        <Cell><span style={label}>{m.statKols}</span><span style={{ ...head("34px"), ...nums }}>{s.kolCount ?? "—"}</span></Cell>
        <Cell><span style={label}>{m.statSlots}</span><span style={{ ...head("34px"), ...nums }}>{s.campaignSlotsTaken ?? "—"}/{s.campaignSlots ?? "—"}</span></Cell>
        <Cell><span style={label}>{m.statPool}</span><span style={{ ...head("34px"), ...nums }}>{fromUnits(s.poolQuote, 18, 3)} BNB</span></Cell>
      </div>

      <div style={{ padding: pad, display: "grid", gap: 14 }}>
        <div style={{ display: "flex", gap: 16, flexWrap: "wrap" }}>
          {isCreator && !s.launched && (
            <Button primary disabled={busy} onClick={() => act("launch", s.poolQuote ?? undefined)}>{m.launchButton} {fromUnits(s.poolQuote, 18, 3)} BNB</Button>
          )}
          {kolNumber > 0 && !s.confirmed && <Button primary disabled={busy} onClick={() => act("confirm")}>{m.confirmButton}</Button>}
          {kolNumber === 0 && s.invited && slotsLeft > 0 && <Button primary disabled={busy} onClick={() => act("joinCampaign")}>{m.joinButton}</Button>}
          {!account && <Button primary onClick={() => host?.wallet?.connect()}>{m.connect}</Button>}
          {s.launched && s.token && addressPattern.test(s.token) && (
            <Button onClick={() => host?.redirect?.(`/bnb-testnet/${s.token}/taxinfo`)}>{m.openVault}</Button>
          )}
        </div>
        {kolNumber === 0 && s.invited && slotsLeft <= 0 && <p style={{ margin: 0, color: danger }}>{m.campaignFull}</p>}
        {note && <p role="status" style={{ margin: 0, color: muted }}>{note}</p>}
        <p style={{ margin: 0, color: muted, fontSize: 14 }}>{m.disclaimer}</p>
      </div>
    </section>
  );
}

const MASCOT = "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAASABIAAD/4QCaRXhpZgAATU0AKgAAAAgAAgExAAIAAAAHAAAAJodpAAQAAAABAAAALgAAAABQaWNhc2EAAAAFkAAABwAAAAQwMjIwoAEAAwAAAAEAAQAAoAIABAAAAAEAAAFooAMABAAAAAEAAAFopCAAAgAAACEAAABwAAAAADA5Njk5ZjAzM2M1ZDNiNGYwMDAwMDAwMDAwMDAwMDAwAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAAABDUHYzZjwCyBOmACZjs+EJ+/8AAEQgBaAFoAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/bAEMAAgICAgICBAICBAYEBAQGCAYGBgYICggICAgICgwKCgoKCgoMDAwMDAwMDA4ODg4ODhAQEBAQEhISEhISEhISEv/bAEMBAwMDBQQFCAQECBMNCw0TExMTExMTExMTExMTExMTExMTExMTExMTExMTExMTExMTExMTExMTExMTExMTExMTE//dAAQAF//aAAwDAQACEQMRAD8A/AOiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooASloooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigD//0PwDooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKODRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQB/9H8A6KKPagAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKTNLQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFAH/0vwDooooAKKKKACijpRjNABR70Y70UAFFFFABRRRQAUUYzRQAUUUUAFFFFABRRRQAUqkhgRxSV9i/sd/s13Px28eLqfiRTb+FNGIn1K5c7EZV+YQhjjlsfMf4VyT2rgzPMaOXYeeMxLtGK+b7Jd23ol1YpOyudV8Of2ctXj+EUvxjNos0t5bynSo7qM+VHtG2aaXjDEdLZcHe3ODjFfFN1o8tjYpeXx8ppwGhjP3mXP3yOy+mevbiv6GPip8Sfhv4P8AAsniTX7eO68GzTadbR2sKBJIkmMgiu1U4ZfLEQMSjGVXPU1+WX7ZPwE1vwXq9v8AFzS5o9U0DxDh1vrYloTIRlW9EEq/Mqg4UhlXgAV8dwvxRUxs3HMI8jqN8l+tvs/4kt++6M4PufDdFFFfoBqFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFGaKKAP/T/AOiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooATPpS0UUAHWiiux8HeEL3xZqcdnAr7XcRrsUszyMcJEgHV3PAH4nionOMIuc3ZITdj0n9nv4CeKPj947tvCmiAw2xbdc3JGVijH3j7nHQetfqd+1F8T/AIcfsrfDCy+APgWBJbry0kNqDgSHr5l3jkozAMU/5aEYOEznoNX1zwf/AME+v2fLeFY4bjxrrMW2KJfm/e9ctznyoc8n+Nvrx+G/irxV4g8beIbvxV4pupL7UL6QyzTSHLMx/kB0AHAHAr83yynW4oxyzbEaYSk37KP88tvaPy6RIXvas/WQ+GdW+NP7GcmtazfsCYoL2+unTeyjTxfSNgZX7xKrxwM1e/YG8ReEfip8Etf/AGe/iXOL2zZ2MVvNjMEcoG1o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La3XGOn3YxXmtJS9nHsFj06T4zfFOSFbca5dRomNqxt5YGOn3AKp3Pxa+KN5EYLrxHqUiHqpupcflurz6il7KH8qCxuXPibxJeuZLzULmVj1LzOx/U1lteXbv5jzOW9Sxz+dV6KtRS2QzUh1zW7chre8nQjoVkYfyNb1v8RfiDagC213UI9vTbcyjH/j3vXG0VMqcZfEkwPVrT46/GmwaNrTxZqyGI5TF5N8p68fNXSp+1J+0UkLQf8ACZ6qyNnIe4Zs7uv3s14JRWMsFQl8VOL+SFY99f8Aal/aCmTyrjxVezJ83yylJB83XhlI5rNsP2i/jTpl0t9p+uyQTISyukUKsCTknIj65FeKUULBUEnFU42fkgsj3TUv2lvjnrGpjWtU8RTz3QGPNZIi2P8AvivIdd1zVvE2r3Gv69O11eXTl5ZXxuZj3OMCsmitKVCnS/hxS9FYdkFFFFagFFFJzQAtFFFABRRRQAUUUUAFFFFABRRRQB//0/wDooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAozmiigAooooAKKKKACiiigAooooAKKKSgBaKKKACiiigAozRRQAUUUUAFFFFABRRRQAUUUUAFFFFAH//1PwDooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooox3oAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKAE7UtFFABRRRQAUUUUAf/1fwDoopR1oAMUlO9abQAUUUUAFFFFABiinHoKbQAYopw6Gm0ALg0mMU/vSN1oAbRSjrR3oAMYpKc1NoAMZoxinL1obrQA3GKKc3WkHQ0AGM0YNKtKOpoAbjtSU/+KmUAFFFKOtABikp46mmnrQAlGM0U5etACYNJjvT+9J/DQAmM0lOWkPWgBKKKKADHejHenfw0fw0ANoxRTh0NADaKKKACiiigD//Z";
