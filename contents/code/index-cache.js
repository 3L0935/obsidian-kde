// Persistent vault-index cache.
// Stored shape: { schemaVersion, vaultPath, notes:[note], colorGroupsMtime }
// where each cached note keeps the metadata fields (no content/body — those
// stay lazy-loaded by the live vault model) plus optional x,y position.

var SCHEMA_VERSION = 1;

function serializeIndex(opts) {
    var vaultPath = opts.vaultPath;
    var notes = opts.notes || [];
    var positions = opts.positions || {};
    var colorGroupsMtime = opts.colorGroupsMtime || 0;

    var out = [];
    for (var i = 0; i < notes.length; i++) {
        var n = notes[i];
        var pos = positions[n.path] || { x: 0, y: 0 };
        out.push({
            path: n.path,
            basename: n.basename,
            title: n.title,
            mtime: n.mtime,
            tags: n.tags || [],
            wikilinksRaw: n.wikilinksRaw || [],
            // outgoingLinks intentionally not persisted — recomputed via
            // resolveAllLinks() after hydrateFromCache.
            frontmatter: n.frontmatter || {},
            aliases: n.aliases || [],
            x: pos.x,
            y: pos.y,
        });
    }

    return {
        schemaVersion: SCHEMA_VERSION,
        vaultPath: vaultPath,
        colorGroupsMtime: colorGroupsMtime,
        notes: out,
    };
}

function hydrateIndex(blob) {
    if (!blob || typeof blob !== "object") return null;
    if (blob.schemaVersion !== SCHEMA_VERSION) return null;
    if (!blob.vaultPath || !Array.isArray(blob.notes)) return null;

    var notes = [];
    for (var i = 0; i < blob.notes.length; i++) {
        var n = blob.notes[i];
        if (!n || !n.path) continue;
        notes.push({
            path: n.path,
            basename: n.basename || n.path.split("/").pop().replace(/\.md$/, ""),
            title: n.title || n.path,
            mtime: n.mtime || 0,
            tags: Array.isArray(n.tags) ? n.tags : [],
            wikilinksRaw: Array.isArray(n.wikilinksRaw) ? n.wikilinksRaw : [],
            outgoingLinks: Array.isArray(n.outgoingLinks) ? n.outgoingLinks : [],
            frontmatter: n.frontmatter || {},
            aliases: Array.isArray(n.aliases) ? n.aliases : [],
            x: typeof n.x === "number" ? n.x : 0,
            y: typeof n.y === "number" ? n.y : 0,
        });
    }
    return {
        vaultPath: blob.vaultPath,
        colorGroupsMtime: blob.colorGroupsMtime || 0,
        notes: notes,
    };
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        SCHEMA_VERSION: SCHEMA_VERSION,
        serializeIndex: serializeIndex,
        hydrateIndex: hydrateIndex,
    };
}
