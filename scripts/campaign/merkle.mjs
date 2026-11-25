// Invite list -> Merkle root (for KK_CAMPAIGN_ROOT) + per-wallet proofs (for the UI's joinCampaign).
// Usage: node merkle.mjs invited.json tree.json
import { StandardMerkleTree } from "@openzeppelin/merkle-tree";
import { readFileSync, writeFileSync } from "node:fs";

const [inFile = "invited.json", outFile = "tree.json"] = process.argv.slice(2);
const wallets = JSON.parse(readFileSync(inFile, "utf8"));
const tree = StandardMerkleTree.of(wallets.map((a) => [a]), ["address"]);
const proofs = Object.fromEntries([...tree.entries()].map(([i, [a]]) => [a.toLowerCase(), tree.getProof(i)]));
writeFileSync(outFile, JSON.stringify({ root: tree.root, proofs }, null, 2));
console.log(tree.root);
