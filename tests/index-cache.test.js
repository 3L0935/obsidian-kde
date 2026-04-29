const path = require("path");
const fs = require("fs");
const { serializeIndex, hydrateIndex, SCHEMA_VERSION } = require("../contents/code/index-cache.js");
const { createVaultModel } = require("../contents/code/vault.js");
const markdownModule = require("../contents/code/markdown.js");

const FIXTURE = path.join(__dirname, "fixtures", "vault-small");

function nodeFs() {
    return {
        readFileSync: (p) => fs.readFileSync(p, "utf8"),
        writeFileSync: (p, c) => fs.writeFileSync(p, c, "utf8"),
        readdirSync: (p) => fs.readdirSync(p, { withFileTypes: true })
            .map((d) => ({ name: d.name, isDirectory: d.isDirectory(), isFile: d.isFile() })),
        statSync: (p) => ({ mtimeMs: fs.statSync(p).mtimeMs }),
        join: path.join,
        sep: path.sep,
    };
}

describe("index-cache", () => {
    it("serializeIndex emits a JSON-stringifiable shape", () => {
        const vm = createVaultModel({ fs: nodeFs(), markdown: markdownModule });
        vm.scan(FIXTURE);
        const positions = { "foo.md": { x: 12, y: -34 } };
        const blob = serializeIndex({
            vaultPath: FIXTURE,
            notes: vm.allNotes(),
            positions: positions,
            colorGroupsMtime: 1234,
        });
        const parsed = JSON.parse(JSON.stringify(blob));
        assertEqual(parsed.schemaVersion, SCHEMA_VERSION);
        assertEqual(parsed.vaultPath, FIXTURE);
        assertTrue(parsed.notes.length === vm.noteCount());
        const fooEntry = parsed.notes.find((n) => n.path === "foo.md");
        assertEqual(fooEntry.x, 12);
        assertEqual(fooEntry.y, -34);
    });

    it("hydrateIndex round-trips notes and positions", () => {
        const vm = createVaultModel({ fs: nodeFs(), markdown: markdownModule });
        vm.scan(FIXTURE);
        const blob = serializeIndex({
            vaultPath: FIXTURE,
            notes: vm.allNotes(),
            positions: {},
        });
        const out = hydrateIndex(blob);
        assertEqual(out.vaultPath, FIXTURE);
        assertEqual(out.notes.length, vm.noteCount());
        for (const n of out.notes) assertTrue(Array.isArray(n.outgoingLinks));
    });

    it("hydrateIndex returns null on schema-version mismatch", () => {
        const out = hydrateIndex({ schemaVersion: 999, notes: [] });
        assertEqual(out, null);
    });

    it("hydrateIndex returns null on missing required fields", () => {
        assertEqual(hydrateIndex({}), null);
        assertEqual(hydrateIndex({ schemaVersion: SCHEMA_VERSION }), null);
    });
});

describe("hydrate → rescan pipeline", () => {
    // Pin contract: after hydrate + rescan, loadNoteContent works for an
    // unchanged note (one rescan didn't re-parse). This guards against the
    // absPath-bug where hydrateFromCache forgot to set rootPath first.
    it("loadNoteContent works for hydrated notes that the rescan did not re-parse", () => {
        const vm1 = createVaultModel({ fs: nodeFs(), markdown: markdownModule });
        vm1.scan(FIXTURE);
        const blob = serializeIndex({
            vaultPath: FIXTURE,
            notes: vm1.allNotes(),
            positions: {},
        });

        const vm2 = createVaultModel({ fs: nodeFs(), markdown: markdownModule });
        const hydrated = hydrateIndex(blob);
        vm2.hydrateFromCache(FIXTURE, hydrated.notes);

        // Walk-style entries with mtimes matching the cache → rescan diffs to
        // "nothing changed" and doesn't touch any note.
        const entries = vm1.allNotes().map((n) => ({ path: n.absPath, mtime: n.mtime }));
        const diff = vm2.rescanFiles(FIXTURE, entries);
        assertEqual(diff.added.length, 0);
        assertEqual(diff.changed.length, 0);
        assertEqual(diff.removed.length, 0);

        // The critical assertion: loadNoteContent must work for a note the
        // rescan did NOT re-parse, proving absPath was set correctly at
        // hydrate time.
        const c = vm2.loadNoteContent("foo.md");
        assertTrue(c !== null && c.includes("Foo"), "loadNoteContent works after pure hydrate");
    });
});
