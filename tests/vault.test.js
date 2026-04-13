const path = require("path");
const fs = require("fs");
const { createVaultModel } = require("../contents/code/vault.js");

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
    const vm = createVaultModel({ fs: nodeFs() });
    vm.scan(FIXTURE);
    assertEqual(vm.noteCount(), 10);
  });

  it("skips non-markdown files", () => {
    const junk = path.join(FIXTURE, "junk.txt");
    fs.writeFileSync(junk, "nope");
    try {
      const vm = createVaultModel({ fs: nodeFs() });
      vm.scan(FIXTURE);
      assertEqual(vm.noteCount(), 10);
    } finally {
      fs.unlinkSync(junk);
    }
  });

  it("resolves [[wikilinks]] to existing notes by basename", () => {
    const vm = createVaultModel({ fs: nodeFs() });
    vm.scan(FIXTURE);
    const foo = vm.getNote("foo.md");
    assertTrue(foo !== null, "foo.md should exist");
    assertDeepEqual(foo.outgoingLinks.slice().sort(), ["bar.md", "baz.md"]);
  });

  it("resolves wikilinks in subfolders", () => {
    const vm = createVaultModel({ fs: nodeFs() });
    vm.scan(FIXTURE);
    const nested = vm.getNote("sub/nested.md");
    assertDeepEqual(nested.outgoingLinks, ["foo.md"]);
  });

  it("parses frontmatter aliases as title source", () => {
    const vm = createVaultModel({ fs: nodeFs() });
    vm.scan(FIXTURE);
    const foo = vm.getNote("foo.md");
    assertEqual(foo.title, "Foo Note");
  });

  it("falls back to basename as title", () => {
    const vm = createVaultModel({ fs: nodeFs() });
    vm.scan(FIXTURE);
    const baz = vm.getNote("baz.md");
    assertEqual(baz.title, "baz");
  });

  it("collects tags", () => {
    const vm = createVaultModel({ fs: nodeFs() });
    vm.scan(FIXTURE);
    const multi = vm.getNote("multi-tag.md");
    assertDeepEqual(multi.tags.slice().sort(), ["a", "b/c", "d"]);
  });

  it("builds edges list for the graph", () => {
    const vm = createVaultModel({ fs: nodeFs() });
    vm.scan(FIXTURE);
    // index→foo, index→bar, foo→bar, foo→baz, bar→foo, sub/nested→foo, sub/another→nested
    assertEqual(vm.getEdges().length, 7);
  });

  it("ignores wikilinks inside code blocks", () => {
    const vm = createVaultModel({ fs: nodeFs() });
    vm.scan(FIXTURE);
    const n = vm.getNote("code-only.md");
    assertDeepEqual(n.outgoingLinks, []);
  });
});
