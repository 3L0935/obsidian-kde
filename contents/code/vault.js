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
                if (typeof console !== "undefined") {
                    console.warn("[vault] parse failed:", abs, e && e.message);
                }
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

    // On-demand rescan driven by user interaction instead of a watcher.
    // Takes a list of {path, mtime} entries produced by the directory walk
    // (FolderListModel exposes fileModified for free) and compares each
    // entry's mtime against the cached note's mtime. This keeps rescanFiles
    // pure — no fs.statSync calls — which matters under QML where a real
    // single-file stat isn't cheap. Returns {added, changed, removed} lists
    // of relPaths so the caller can apply an incremental diff without
    // rebuilding the full graph.
    function rescanFiles(rp, entries) {
        rootPath = rp;
        var seen = new Set();
        var added = [];
        var changed = [];
        var removed = [];
        for (var entry of entries) {
            var abs = entry.path;
            var entryMtime = entry.mtime || 0;
            seen.add(abs);
            var rel = relativize(abs).split(fs.sep).join("/");
            var existing = notes.get(rel);
            if (!existing) {
                try {
                    addOrUpdateNote(abs);
                    added.push(rel);
                } catch (e) {
                    if (typeof console !== "undefined") {
                        console.warn("[vault] rescan parse failed:", abs, e && e.message);
                    }
                }
                continue;
            }
            if (entryMtime > existing.mtime + 1) {
                try {
                    addOrUpdateNote(abs);
                    changed.push(rel);
                } catch (e) {
                    if (typeof console !== "undefined") {
                        console.warn("[vault] rescan reload failed:", abs, e && e.message);
                    }
                }
            }
        }
        var toRemove = [];
        for (var mapEntry of notes) {
            if (!seen.has(mapEntry[1].absPath)) toRemove.push(mapEntry[1]);
        }
        for (var note of toRemove) {
            removed.push(note.path);
            removeNote(note.absPath);
        }
        return { added: added, changed: changed, removed: removed };
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

    // Dual-mode: pass a callback to use an async fs.writeFile (required under
    // QML — sync XHR PUT is broken on file:// in Qt 6.11). Without a callback
    // we fall back to fs.writeFileSync, which is what the Node tests inject.
    function saveNote(relPath, content, expectedMtimeMs, cb) {
        var note = notes.get(relPath);
        if (!note) {
            var r0 = { ok: false, conflict: false, mtime: 0 };
            if (cb) cb(null, r0);
            return r0;
        }
        var current = fs.statSync(note.absPath).mtimeMs;
        if (expectedMtimeMs && current > expectedMtimeMs + 1) {
            var rc = { ok: false, conflict: true, mtime: current };
            if (cb) cb(null, rc);
            return rc;
        }

        function finalize() {
            addOrUpdateNote(note.absPath);
            var updated = notes.get(relPath);
            return { ok: true, conflict: false, mtime: updated.mtime };
        }

        if (cb) {
            if (typeof fs.writeFile !== "function") {
                cb(new Error("fs.writeFile not implemented"));
                return;
            }
            fs.writeFile(note.absPath, content, function (err) {
                if (err) { cb(err); return; }
                cb(null, finalize());
            });
            return;
        }

        fs.writeFileSync(note.absPath, content);
        return finalize();
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
        rescanFiles: rescanFiles,
        removeNote: removeNote,
        saveNote: saveNote,
    };
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { createVaultModel: createVaultModel };
}
