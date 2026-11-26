"use client";
// Local test bench for the KabalKult Launcher UI: stands in for Flap's launcher host (MetaMask + viem, BSC Testnet).
// ?launcher=0x… opens the deal page; no parameter opens the create page. Dev tool only, not part of the Flap package.
import { useCallback, useEffect, useMemo, useState } from "react";
import {
  createPublicClient, createWalletClient, custom, http, encodeAbiParameters, encodeFunctionData, getContractAddress,
  keccak256, concat, parseAbi, toHex, type Address, type Hex,
} from "viem";
import { bscTestnet } from "viem/chains";
import { LauncherConfig, Launcher } from "@/examples/kabalkult-launcher/Component";
import i18n from "@/examples/kabalkult-launcher/i18n.json";
import manifest from "@/examples/kabalkult-launcher/manifest.json";

const PORTAL = "0x000042108465206185A077Edc3F3fd2b49060000" as Address;
const TOKEN_IMPL = "0x7777c57ff7dc441c1715b2e36fa581c48B782222" as Address;
const FACTORY = manifest.factoryAddress as Address;
const portalAbi = parseAbi([
  "function SALT_LOCK_FEE() view returns (uint256)",
  "function newLauncher(address launcherFactory, bytes data) payable returns (address)",
]);
const created = parseAbi(["event KabalKultLauncherCreated(address indexed launcher, address indexed creator, bytes32 launchSalt)"]);
const pub = createPublicClient({ chain: bscTestnet, transport: http("https://bsc-testnet-dataseed.bnbchain.org") });
type Eth = { request(a: { method: string; params?: unknown[] }): Promise<unknown>; on?(e: string, f: () => void): void };
const eth = () => (globalThis as unknown as { ethereum?: Eth }).ethereum;

// Same as Flap's ForkBase: the token is an OZ clone of TOKEN_IMPL created by the Portal, address must end in 7777.
function findSalt(): Hex {
  const init = concat(["0x3d602d80600a3d3981f3363d3d373d3d3d363d73", TOKEN_IMPL, "0x5af43d82803e903d91602b57fd5bf3"]);
  const hash = keccak256(init);
  const seed = keccak256(toHex(`${Date.now()}-${Math.random()}`));
  for (let i = 0; ; i++) {
    const salt = keccak256(concat([seed, toHex(i, { size: 32 })]));
    const a = getContractAddress({ opcode: "CREATE2", from: PORTAL, salt, bytecodeHash: hash });
    if (a.toLowerCase().endsWith("7777")) return salt;
  }
}

export default function Page() {
  const [account, setAccount] = useState<string | null>(null);
  const [chainId, setChainId] = useState<number | null>(null);
  const [snapshot, setSnapshot] = useState<Record<string, unknown> | null>(null);
  const [locale, setLocale] = useState<"en" | "zh" | "ko">("en");
  const [launcher, setLauncher] = useState<string | null>(null);

  useEffect(() => {
    const q = new globalThis.URLSearchParams(globalThis.location.search);
    setLauncher(q.get("launcher"));
    if (q.get("lang") === "zh" || q.get("lang") === "ko") setLocale(q.get("lang") as "zh" | "ko");
    const e = eth();
    if (!e) return;
    const sync = async () => {
      const [a] = (await e.request({ method: "eth_accounts" })) as string[];
      setAccount(a ?? null);
      setChainId(Number(await e.request({ method: "eth_chainId" })));
    };
    void sync();
    e.on?.("accountsChanged", sync);
    e.on?.("chainChanged", sync);
  }, []);

  const read = useCallback(async () => {
    if (!launcher) return;
    const entries = Object.entries(manifest.reads) as [string, { functionName: string; returns: string; account?: boolean }][];
    const out: Record<string, unknown> = {};
    await Promise.all(entries.map(async ([key, r]) => {
      if (r.account && !account) { out[key] = null; return; }
      const abi = parseAbi([`function ${r.functionName}(${r.account ? "address" : ""}) view returns (${r.returns})`]);
      try {
        const v = await pub.readContract({ address: launcher as Address, abi, functionName: r.functionName, args: r.account ? [account] : [] } as never);
        out[key] = typeof v === "bigint" ? v.toString() : typeof v === "string" ? v.toLowerCase() : v;
      } catch { out[key] = null; }
    }));
    setSnapshot(out);
  }, [launcher, account]);
  useEffect(() => { void read(); }, [read]);

  const host = useMemo(() => {
    const e = eth();
    const wallet = e ? {
      account, chainId,
      connect: () => { void e.request({ method: "eth_requestAccounts" }).then(a => setAccount((a as string[])[0] ?? null)); },
      switchChain: async () => { await e.request({ method: "wallet_switchEthereumChain", params: [{ chainId: "0x61" }] }); },
    } : undefined;
    const send = async (to: Address, data: Hex, valueWei?: string) => {
      const wc = createWalletClient({ chain: bscTestnet, transport: custom(e!) });
      const hash = await wc.sendTransaction({ account: account as Address, to, data, value: BigInt(valueWei ?? "0") });
      const r = await pub.waitForTransactionReceipt({ hash });
      return { r, hash };
    };
    return {
      wallet,
      quote: async () => (await pub.readContract({ address: PORTAL, abi: portalAbi, functionName: "SALT_LOCK_FEE" })).toString(),
      findSalt: async () => findSalt(),
      encode: (p: readonly { name: string; type: string }[], v: readonly unknown[]) => encodeAbiParameters(p as never, v as never),
      submit: async (input: { kind: "create"; configuration: string; valueWei: string } | { kind: "action"; action: string; valueWei?: string }) => {
        if (input.kind === "create") {
          const data = encodeFunctionData({ abi: portalAbi, functionName: "newLauncher", args: [FACTORY, input.configuration as Hex] });
          const { r, hash } = await send(PORTAL, data, input.valueWei);
          const log = r.logs.find(l => l.address.toLowerCase() === FACTORY.toLowerCase());
          const launcherAddress = log?.topics[1] ? (`0x${log.topics[1].slice(26)}`) : undefined;
          return { status: r.status === "success" ? "success" as const : "reverted" as const, hash, launcherAddress };
        }
        const data = encodeFunctionData({ abi: parseAbi([`function ${input.action}()`]), functionName: input.action as never });
        const { r, hash } = await send(launcher as Address, data, input.valueWei);
        return { status: r.status === "success" ? "success" as const : "reverted" as const, hash };
      },
      checkReceipt: async (hash: string) => {
        const r = await pub.getTransactionReceipt({ hash: hash as Hex });
        return { status: r.status === "success" ? "success" as const : "reverted" as const, hash };
      },
      refresh: () => { void read(); },
      redirect: (path: string) => { globalThis.open(`https://flap.sh${path}`, "_blank", "noopener"); return true; },
      openLauncher: (a: string) => { globalThis.location.search = `?launcher=${a}`; },
    };
  }, [account, chainId, launcher, read]);
  void created;

  const identity = { chainId: 97, factoryAddress: FACTORY };
  const messages = (i18n as Record<string, Record<string, string>>)[locale];
  return (
    <main style={{ background: "#000", minHeight: "100vh", padding: 16 }}>
      {launcher
        ? <Launcher context={{ identity, locale, launcherAddress: launcher, snapshot: snapshot as never }} messages={messages} host={host as never} />
        : <LauncherConfig context={{ identity, locale }} messages={messages} host={host as never} />}
    </main>
  );
}
