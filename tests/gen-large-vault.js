// node tests/gen-large-vault.js <out-dir> <count>
// Generates <count> markdown files with frontmatter, body, ~3 random
// outgoing wikilinks each, and 0-3 tags drawn from a fixed pool.
// Topology: ~85% files in flat root, ~15% in 5 subfolders, mimicking real vaults.

const fs = require("fs");
const path = require("path");

function rand(n) { return Math.floor(Math.random() * n); }

function pickN(arr, n) {
  const out = [];
  const used = new Set();
  while (out.length < n && used.size < arr.length) {
    const i = rand(arr.length);
    if (used.has(i)) continue;
    used.add(i);
    out.push(arr[i]);
  }
  return out;
}

function main() {
  const [, , outDir, countStr] = process.argv;
  if (!outDir || !countStr) {
    console.error("usage: node tests/gen-large-vault.js <out-dir> <count>");
    process.exit(2);
  }
  const count = parseInt(countStr, 10);
  fs.mkdirSync(outDir, { recursive: true });
  const sub = ["projects", "daily", "people", "ideas", "ref"];
  for (const s of sub) fs.mkdirSync(path.join(outDir, s), { recursive: true });

  const tagPool = ["a","b","c","d","wip","done","todo","ref","idea","meta","ops","ux","perf","arch"];
  // Build the basename list FIRST (no file writes yet) so links can target
  // basenames that don't exist on disk yet — wikilinks resolve by basename
  // string match, the file order doesn't matter for the eventual graph.
  const basenames = [];
  for (let i = 0; i < count; i++) {
    const inSub = i % 7 === 0;
    const base = "note-" + i.toString(36);
    basenames.push({
      base: base,
      dir: inSub ? path.join(outDir, sub[i % sub.length]) : outDir,
    });
  }
  for (let i = 0; i < count; i++) {
    const me = basenames[i];
    const outLinks = pickN(basenames, 3 + rand(3))
      .filter((b) => b.base !== me.base)
      .map((b) => "[[" + b.base + "]]");
    const tags = pickN(tagPool, rand(4)).map((t) => "#" + t).join(" ");
    const fm = "---\ntitle: Note " + i + "\naliases:\n  - alt-" + i + "\n---\n";
    const body =
      "# Note " + i + "\n\n" +
      "Lorem ipsum dolor sit amet, consectetur adipiscing elit. " +
      "Pretty representative paragraph body.\n\n" +
      "Links: " + outLinks.join(" ") + "\n\n" +
      "Tags inline: " + tags + "\n";
    fs.writeFileSync(path.join(me.dir, me.base + ".md"), fm + body);
  }
  console.log("generated " + count + " notes in " + outDir);
}

main();
