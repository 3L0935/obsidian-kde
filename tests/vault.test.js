const path = require("path");
const fs = require("fs");
const { createVaultModel } = require("../contents/code/vault.js");
const markdownModule = require("../contents/code/markdown.js");

const FIXTURE = path.join(__dirname, "fixtures", "vault-small");

function nodeFs() {
  return {
    readFileSync: (p) => fs.readFileSync(p, "utf8"),
    writeFileSync: (p, content) => fs.writeFileSync(p, content, "utf8"),
    readdirSync: (p) => fs.readdirSync(p, { withFileTypes: true }).map((d) => ({
      name: d.name, isDirectory: d.isDirectory(), isFile: d.isFile(),
    })),
    statSync: (p) => ({ mtimeMs: fs.statSync(p).mtimeMs }),
    join: path.join,
    sep: path.sep,
  };
}

describe("VaultModel.scan", () => {
  it("indexes all .md files", () => {
    const vm = createVaultModel({ fs: nodeFs(), markdown: markdownModule });
    vm.scan(FIXTURE);
    assertEqual(vm.noteCount(), 10);
  });

  it("skips non-markdown files", () => {
    const junk = path.join(FIXTURE, "junk.txt");
    fs.writeFileSync(junk, "nope");
    try {
      const vm = createVaultModel({ fs: nodeFs(), markdown: markdownModule });
      vm.scan(FIXTURE);
      assertEqual(vm.noteCount(), 10);
    } finally {
      fs.unlinkSync(junk);
    }
  });

  it("resolves [[wikilinks]] to existing notes by basename", () => {
    const vm = createVaultModel({ fs: nodeFs(), markdown: markdownModule });
    vm.scan(FIXTURE);
    const foo = vm.getNote("foo.md");
    assertTrue(foo !== null, "foo.md should exist");
    assertDeepEqual(foo.outgoingLinks.slice().sort(), ["bar.md", "baz.md"]);
  });

  it("resolves wikilinks in subfolders", () => {
    const vm = createVaultModel({ fs: nodeFs(), markdown: markdownModule });
    vm.scan(FIXTURE);
    const nested = vm.getNote("sub/nested.md");
    assertDeepEqual(nested.outgoingLinks, ["foo.md"]);
  });

  it("parses frontmatter aliases as title source", () => {
    const vm = createVaultModel({ fs: nodeFs(), markdown: markdownModule });
    vm.scan(FIXTURE);
    const foo = vm.getNote("foo.md");
    assertEqual(foo.title, "Foo Note");
  });

  it("falls back to basename as title", () => {
    const vm = createVaultModel({ fs: nodeFs(), markdown: markdownModule });
    vm.scan(FIXTURE);
    const baz = vm.getNote("baz.md");
    assertEqual(baz.title, "baz");
  });

  it("collects tags", () => {
    const vm = createVaultModel({ fs: nodeFs(), markdown: markdownModule });
    vm.scan(FIXTURE);
    const multi = vm.getNote("multi-tag.md");
    assertDeepEqual(multi.tags.slice().sort(), ["a", "b/c", "d"]);
  });

  it("builds edges list for the graph", () => {
    const vm = createVaultModel({ fs: nodeFs(), markdown: markdownModule });
    vm.scan(FIXTURE);
    // index→foo, index→bar, foo→bar, foo→baz, bar→foo, sub/nested→foo, sub/another→nested
    assertEqual(vm.getEdges().length, 7);
  });

  it("ignores wikilinks inside code blocks", () => {
    const vm = createVaultModel({ fs: nodeFs(), markdown: markdownModule });
    vm.scan(FIXTURE);
    const n = vm.getNote("code-only.md");
    assertDeepEqual(n.outgoingLinks, []);
  });

  it("does not store note content in the live index", () => {
    const vm = createVaultModel({ fs: nodeFs(), markdown: markdownModule });
    vm.scan(FIXTURE);
    const foo = vm.getNote("foo.md");
    assertTrue(foo.content === undefined, "content must not be cached");
    assertTrue(foo.body === undefined, "body must not be cached");
    // Metadata still extracted at scan time
    assertTrue(Array.isArray(foo.wikilinksRaw));
    assertTrue(Array.isArray(foo.tags));
    assertTrue(typeof foo.title === "string");
  });

  it("loadNoteContent reads on demand and returns the file text", () => {
    const vm = createVaultModel({ fs: nodeFs(), markdown: markdownModule });
    vm.scan(FIXTURE);
    const content = vm.loadNoteContent("foo.md");
    assertTrue(content.includes("Foo"), "loaded on demand");
  });

  it("loadNoteContent returns null for unknown paths", () => {
    const vm = createVaultModel({ fs: nodeFs(), markdown: markdownModule });
    vm.scan(FIXTURE);
    assertEqual(vm.loadNoteContent("does-not-exist.md"), null);
  });
});

describe("VaultModel.saveNote", () => {
  function setupTempVault() {
    const tmp = path.join(__dirname, "_tmp_vault_" + Date.now());
    fs.mkdirSync(tmp);
    fs.writeFileSync(path.join(tmp, "a.md"), "# A\nLinks to [[b]]");
    fs.writeFileSync(path.join(tmp, "b.md"), "# B");
    return tmp;
  }

  function cleanup(tmp) {
    for (const f of fs.readdirSync(tmp)) fs.unlinkSync(path.join(tmp, f));
    fs.rmdirSync(tmp);
  }

  it("writes content and updates mtime", () => {
    const tmp = setupTempVault();
    try {
      const vm = createVaultModel({ fs: nodeFs(), markdown: markdownModule });
      vm.scan(tmp);
      const before = vm.getNote("a.md");
      const busyUntil = Date.now() + 20;
      while (Date.now() < busyUntil) { /* spin */ }
      const result = vm.saveNote("a.md", "# A modified", before.mtime);
      assertTrue(result.ok, "save should succeed");
      assertTrue(!result.conflict, "no conflict expected");
      assertTrue(vm.loadNoteContent("a.md").includes("A modified"), "content updated via loadNoteContent");
    } finally { cleanup(tmp); }
  });

  it("reports conflict when file changed externally", () => {
    const tmp = setupTempVault();
    try {
      const vm = createVaultModel({ fs: nodeFs(), markdown: markdownModule });
      vm.scan(tmp);
      const before = vm.getNote("a.md");
      const busyUntil = Date.now() + 20;
      while (Date.now() < busyUntil) { /* spin */ }
      fs.writeFileSync(path.join(tmp, "a.md"), "# externally changed");
      const result = vm.saveNote("a.md", "# from widget", before.mtime);
      assertTrue(result.conflict, "should detect conflict");
    } finally { cleanup(tmp); }
  });
});

describe("VaultModel.rescanFiles", () => {
  function setupTempVault() {
    const tmp = path.join(__dirname, "_tmp_rescan_" + Date.now() + "_" + Math.floor(Math.random() * 1e6));
    fs.mkdirSync(tmp);
    fs.writeFileSync(path.join(tmp, "a.md"), "# A\nLinks to [[b]]");
    fs.writeFileSync(path.join(tmp, "b.md"), "# B");
    return tmp;
  }
  function cleanup(tmp) {
    for (const f of fs.readdirSync(tmp)) fs.unlinkSync(path.join(tmp, f));
    fs.rmdirSync(tmp);
  }
  // Mirrors what FsHelper.walkVault produces under QML: list of
  // {path, mtime} entries, mtime sourced from the directory walk so
  // rescanFiles never needs to stat individual files.
  function walkEntries(tmp) {
    return fs.readdirSync(tmp)
      .filter(f => f.endsWith(".md"))
      .map(f => {
        const abs = path.join(tmp, f);
        return { path: abs, mtime: fs.statSync(abs).mtimeMs };
      });
  }

  it("detects newly added files", () => {
    const tmp = setupTempVault();
    try {
      const vm = createVaultModel({ fs: nodeFs(), markdown: markdownModule });
      vm.scan(tmp);
      fs.writeFileSync(path.join(tmp, "c.md"), "# C");
      const diff = vm.rescanFiles(tmp, walkEntries(tmp));
      assertDeepEqual(diff.added, ["c.md"]);
      assertEqual(diff.changed.length, 0);
      assertEqual(diff.removed.length, 0);
      assertTrue(vm.getNote("c.md") !== null, "new note indexed");
    } finally { cleanup(tmp); }
  });

  it("detects externally modified files via walk mtime", () => {
    const tmp = setupTempVault();
    try {
      const vm = createVaultModel({ fs: nodeFs(), markdown: markdownModule });
      vm.scan(tmp);
      const busyUntil = Date.now() + 20;
      while (Date.now() < busyUntil) { /* spin */ }
      fs.writeFileSync(path.join(tmp, "b.md"), "# B updated");
      const diff = vm.rescanFiles(tmp, walkEntries(tmp));
      assertDeepEqual(diff.changed, ["b.md"]);
      assertTrue(vm.loadNoteContent("b.md").includes("updated"), "content reloaded via loadNoteContent");
    } finally { cleanup(tmp); }
  });

  it("ignores a file whose walk mtime is stale (no redundant reload)", () => {
    const tmp = setupTempVault();
    try {
      const vm = createVaultModel({ fs: nodeFs(), markdown: markdownModule });
      vm.scan(tmp);
      const before = vm.getNote("b.md").mtime;
      // Feed an entry with an older mtime than the cache — should be a no-op.
      const diff = vm.rescanFiles(tmp, [
        { path: path.join(tmp, "a.md"), mtime: before },
        { path: path.join(tmp, "b.md"), mtime: before - 1000 },
      ]);
      assertEqual(diff.changed.length, 0, "stale walk mtime should not trigger reload");
    } finally { cleanup(tmp); }
  });

  it("detects removed files", () => {
    const tmp = setupTempVault();
    try {
      const vm = createVaultModel({ fs: nodeFs(), markdown: markdownModule });
      vm.scan(tmp);
      fs.unlinkSync(path.join(tmp, "b.md"));
      const diff = vm.rescanFiles(tmp, walkEntries(tmp));
      assertDeepEqual(diff.removed, ["b.md"]);
      assertTrue(vm.getNote("b.md") === null, "removed note dropped");
    } finally { cleanup(tmp); }
  });

  it("re-resolves wikilinks after a new target appears", () => {
    const tmp = path.join(__dirname, "_tmp_rescan2_" + Date.now());
    fs.mkdirSync(tmp);
    fs.writeFileSync(path.join(tmp, "a.md"), "# A\nLinks to [[c]]");
    try {
      const vm = createVaultModel({ fs: nodeFs(), markdown: markdownModule });
      vm.scan(tmp);
      assertEqual(vm.getNote("a.md").outgoingLinks.length, 0);
      fs.writeFileSync(path.join(tmp, "c.md"), "# C");
      vm.rescanFiles(tmp, walkEntries(tmp));
      assertDeepEqual(vm.getNote("a.md").outgoingLinks, ["c.md"]);
    } finally { cleanup(tmp); }
  });

  it("is a no-op when nothing changed", () => {
    const tmp = setupTempVault();
    try {
      const vm = createVaultModel({ fs: nodeFs(), markdown: markdownModule });
      vm.scan(tmp);
      const diff = vm.rescanFiles(tmp, walkEntries(tmp));
      assertEqual(diff.added.length, 0);
      assertEqual(diff.changed.length, 0);
      assertEqual(diff.removed.length, 0);
    } finally { cleanup(tmp); }
  });
});
