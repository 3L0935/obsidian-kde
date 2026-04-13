// VaultModel: scan, index, resolve wikilinks, save with conflict detection.
// Works under both Node and QML JS import.
// Caller must inject { fs, markdown } where markdown provides
// parseFrontmatter, extractWikilinks, extractTags.

function createVaultModel(opts) {
    var fs = opts.fs;
    var markdown = opts.markdown;
    var notes = new Map();
    var byBasename = new Map();
    var listeners = { ready: [], noteAdded: [], noteChanged: [], noteRemoved: [] };
    var rootPath = null;

    function emit(name) {
        var args = Array.prototype.slice.call(arguments, 1);
        var list = listeners[name] || [];
        for (var fn of list) fn.apply(null, args);
    }

    function on(name, fn) {
        if (!listeners[name]) listeners[name] = [];
        listeners[name].push(fn);
    }

    function relativize(abs) {
        if (!rootPath) return abs;
        if (abs === rootPath) return "";
        var prefix = rootPath.endsWith(fs.sep) ? rootPath : rootPath + fs.sep;
        return abs.startsWith(prefix) ? abs.slice(prefix.length) : abs;
    }

    function walk(dir, out) {
        var entries = fs.readdirSync(dir);
        for (var e of entries) {
            var full = fs.join(dir, e.name);
            if (e.isDirectory) walk(full, out);
            else if (e.isFile && e.name.endsWith(".md")) out.push(full);
        }
    }

    function parseNoteFile(absPath) {
        var rel = relativize(absPath).split(fs.sep).join("/");
        var content = fs.readFileSync(absPath);
        var parsed = markdown.parseFrontmatter(content);
        var frontmatter = parsed.frontmatter;
        var body = parsed.body;
        var basename = rel.split("/").pop().replace(/\.md$/, "");
        var aliases = Array.isArray(frontmatter.aliases)
            ? frontmatter.aliases
            : (frontmatter.alias ? [frontmatter.alias] : []);
        var title = aliases[0] || frontmatter.title || basename;
        var wikilinks = markdown.extractWikilinks(body);
        var tags = markdown.extractTags(body).concat(
            Array.isArray(frontmatter.tags) ? frontmatter.tags : []
        );
        var mtime = fs.statSync(absPath).mtimeMs;
        return {
            path: rel,
            absPath: absPath,
            basename: basename,
            title: title,
            content: content,
            body: body,
            frontmatter: frontmatter,
            aliases: aliases,
            tags: tags,
            wikilinksRaw: wikilinks,
            outgoingLinks: [],
            mtime: mtime,
        };
    }

    function indexBasename(note) {
        var set = byBasename.get(note.basename) || new Set();
        set.add(note.path);
        byBasename.set(note.basename, set);
    }

    function unindexBasename(note) {
        var set = byBasename.get(note.basename);
        if (!set) return;
        set.delete(note.path);
        if (set.size === 0) byBasename.delete(note.basename);
    }

    function resolveLink(target) {
        var clean = target.replace(/\.md$/, "").trim();
        var set = byBasename.get(clean);
        if (set && set.size > 0) return Array.from(set)[0];
        var lower = clean.toLowerCase();
        for (var entry of byBasename) {
            if (entry[0].toLowerCase() === lower && entry[1].size > 0) {
                return Array.from(entry[1])[0];
            }
        }
        return null;
    }

    function resolveAllLinks() {
        for (var note of notes.values()) {
            var resolved = [];
            for (var raw of note.wikilinksRaw) {
                var r = resolveLink(raw);
                if (r && r !== note.path) resolved.push(r);
            }
            note.outgoingLinks = resolved;
        }
    }

    function scan(rp) {
        rootPath = rp;
        notes.clear();
        byBasename.clear();
        var files = [];
        walk(rp, files);
        for (var abs of files) {
            var note = parseNoteFile(abs);
            notes.set(note.path, note);
            indexBasename(note);
        }
        resolveAllLinks();
        emit("ready");
    }

    function scanFiles(rp, absPathList) {
        rootPath = rp;
        notes.clear();
        byBasename.clear();
        for (var abs of absPathList) {
            try {
                var note = parseNoteFile(abs);
                notes.set(note.path, note);
                indexBasename(note);
            } catch (e) {
                // skip unreadable files
            }
        }
        resolveAllLinks();
        emit("ready");
    }

    function noteCount() { return notes.size; }
    function getNote(relPath) { return notes.get(relPath) || null; }
    function allNotes() { return Array.from(notes.values()); }

    function getEdges() {
        var edges = [];
        for (var note of notes.values()) {
            for (var target of note.outgoingLinks) {
                edges.push({ source: note.path, target: target });
            }
        }
        return edges;
    }

    function addOrUpdateNote(absPath) {
        var rel = relativize(absPath).split(fs.sep).join("/");
        var existed = notes.get(rel);
        if (existed) unindexBasename(existed);
        var note = parseNoteFile(absPath);
        notes.set(note.path, note);
        indexBasename(note);
        resolveAllLinks();
        if (existed) emit("noteChanged", note, existed.outgoingLinks, note.outgoingLinks);
        else emit("noteAdded", note);
    }

    function removeNote(absPath) {
        var rel = relativize(absPath).split(fs.sep).join("/");
        var existed = notes.get(rel);
        if (!existed) return;
        unindexBasename(existed);
        notes.delete(rel);
        resolveAllLinks();
        emit("noteRemoved", rel);
    }

    function saveNote(relPath, content, expectedMtimeMs) {
        var note = notes.get(relPath);
        if (!note) return { ok: false, conflict: false, mtime: 0 };
        var current = fs.statSync(note.absPath).mtimeMs;
        if (expectedMtimeMs && current > expectedMtimeMs + 1) {
            return { ok: false, conflict: true, mtime: current };
        }
        fs.writeFileSync(note.absPath, content);
        addOrUpdateNote(note.absPath);
        var updated = notes.get(relPath);
        return { ok: true, conflict: false, mtime: updated.mtime };
    }

    return {
        scan: scan,
        scanFiles: scanFiles,
        on: on,
        noteCount: noteCount,
        getNote: getNote,
        allNotes: allNotes,
        getEdges: getEdges,
        addOrUpdateNote: addOrUpdateNote,
        removeNote: removeNote,
        saveNote: saveNote,
    };
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { createVaultModel: createVaultModel };
}
