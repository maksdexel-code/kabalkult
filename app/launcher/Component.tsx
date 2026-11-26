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

// ─── Mascot: inline SVG line art (Flap Launcher UIs may not load images or use timers) ───
function Mascot({ size, alt }: { size: string; alt: string }) {
  return (
    <svg viewBox="0 0 200 200" role="img" aria-label={alt} style={{ width: size, aspectRatio: "1 / 1", flexShrink: 0, display: "block" }}>
      <g fill="none" stroke={lime} strokeWidth={3} strokeLinejoin="round" strokeLinecap="round">
      {/* pointed hat with KK */}
      <path d="M100 22 L44 92 L100 104 L156 92 Z M100 90 L100 104" />
      <text x="100" y="84" textAnchor="middle" fontSize="30" fontWeight={900} fill={lime} stroke="none" fontFamily={display}>KK</text>
      {/* face */}
      <path d="M58 94 L60 142 L80 162 L120 162 L140 142 L142 94" />
      {/* angry eyes */}
      <path d="M68 110 L92 118 L72 124 Z M132 110 L108 118 L128 124 Z" fill={lime} stroke={lime} strokeWidth={2} strokeLinejoin="round" />
      {/* nose */}
      <path d="M94 120 L100 134 L106 120" />
      {/* grin with teeth */}
      <path d="M70 134 Q100 164 130 134 M74 138 Q100 152 126 138 M86 143 L86 150 M100 145 L100 153 M114 143 L114 150" />
      {/* neck and ground */}
      <path d="M88 162 L88 180 M112 162 L112 180 M56 182 L144 182" />
      {/* floating shards */}
      <path d="M30 70 l8 -4 l4 8 l-8 4 Z M160 54 l9 -2 l2 9 l-9 2 Z M24 128 l8 -6 l6 8 l-8 6 Z M166 122 l8 2 l-2 8 l-8 -2 Z M150 34 l5 0 l0 5 l-5 0 Z M44 150 l5 -2 l2 5 l-5 2 Z" strokeWidth={2} />
      </g>
    </svg>
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
// Flap's Portal liquidity floor on BSC testnet, measured 25 Nov 2026 (~1.07 tBNB). The create page gets no chain
// reads, so below this is only a warning: the Portal is the real check and may change its floor.
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
  const warnings: string[] = [];
  const name = form.name.trim(), symbol = form.symbol.trim();
  if (!name || !symbol) problems.push("errToken");
  const poolQuote = units(form.pool, 18);
  if (poolQuote === null || poolQuote === 0n) problems.push("errPool");
  else if (poolQuote < MIN_RAISE_WEI) warnings.push("warnPool");
  const buy = units(form.buyTax, 2), sell = units(form.sellTax, 2);
  if (buy === null || sell === null || buy > 1000n || sell > 1000n || (buy > sell ? buy : sell) < 100n) problems.push("errTax");
  const stock = STOCKS.find(s => s.key === form.payout);
  const payoutToken = form.payout === "bnb" ? zero : stock ? stock.address : form.customPayout.trim();
  if (!addressPattern.test(payoutToken)) problems.push("errPayout");
  if (form.payout === "custom") warnings.push("warnCustomToken");
  const usd = form.milestones.map(x => units(x.usd, 18));
  const share = form.milestones.map(x => units(x.share, 2));
  const rising = usd.every((u, i) => u !== null && u > 0n && (i === 0 || (usd[i - 1] ?? 0n) < u));
  const total = share.reduce<bigint>((a, s) => a + (s ?? 0n), 0n);
  warnings.push("warnFirstMilestone");
  if (form.milestones.length < 1 || form.milestones.length > 10 || !rising || share.some(s => s === null || s === 0n) || total !== 10_000n) {
    problems.push("errMilestones");
  }
  const kols = wallets(form.kols), invitees = wallets(form.invitees);
  const lower = kols.map(a => a.toLowerCase());
  const duplicate = lower.some((a, i) => lower.indexOf(a) !== i);
  if (kols.some(a => !addressPattern.test(a) || a.toLowerCase() === zero) || duplicate || kols.length > 100) problems.push("errKols");
  if (invitees.some(a => !addressPattern.test(a)) || invitees.length > 1000) problems.push("errInvitees");
  const slots = /^\d{1,5}$/.test(form.slots.trim()) ? Number(form.slots.trim()) : -1;
  if (slots < 0) problems.push("errSlots");
  if (kols.length === 0 && (invitees.length === 0 || slots === 0)) problems.push("errNobody");
  if (problems.length) return { problems, warnings, values: null };
  return {
    problems, warnings,
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

          {checked && draft.warnings.length > 0 && (
            <div role="note" style={{ border: rule, padding: 16, color: limeSoft }}>
              {draft.warnings.map(k => <p key={k} style={{ margin: "2px 0" }}>{m[k]}</p>)}
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

          <p style={{ margin: 0, color: muted, fontSize: 14 }}>{m.createRules}</p>
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
            <Button onClick={() => host?.redirect?.(`/${context.identity.chainId === 56 ? "bnb" : "bnb-testnet"}/${s.token}/taxinfo`)}>{m.openVault}</Button>
          )}
        </div>
        {kolNumber > 0 && !s.confirmed && <p style={{ margin: 0, color: muted, fontSize: 14 }}>{m.confirmHint}</p>}
        {kolNumber === 0 && s.invited && slotsLeft <= 0 && <p style={{ margin: 0, color: danger }}>{m.campaignFull}</p>}
        {note && <p role="status" style={{ margin: 0, color: muted }}>{note}</p>}
        <p style={{ margin: 0, color: muted, fontSize: 14 }}>{m.dealRules}</p>
        <p style={{ margin: 0, color: muted, fontSize: 14 }}>{m.disclaimer}</p>
      </div>
    </section>
  );
}

