// VaultModel: scan, index, resolve wikilinks, save with conflict detection.
// FS is injected so this file is testable under Node.

(function (root, factory) {
  if (typeof module === "object" && module.exports) {
    module.exports = factory(require("./markdown.js"));
  } else {
    root.Vault = factory(root.Markdown);
  }
})(typeof self !== "undefined" ? self : this, function (Markdown) {

  function createVaultModel(opts) {
    const fs = opts.fs;
    const notes = new Map();
    const byBasename = new Map();
    const listeners = { ready: [], noteAdded: [], noteChanged: [], noteRemoved: [] };
    let rootPath = null;

    function emit(name) {
      const args = Array.prototype.slice.call(arguments, 1);
      for (const fn of listeners[name] || []) fn.apply(null, args);
    }

    function on(name, fn) {
      (listeners[name] = listeners[name] || []).push(fn);
    }

    function relativize(abs) {
      if (!rootPath) return abs;
      if (abs === rootPath) return "";
      const prefix = rootPath.endsWith(fs.sep) ? rootPath : rootPath + fs.sep;
      return abs.startsWith(prefix) ? abs.slice(prefix.length) : abs;
    }

    function walk(dir, out) {
      const entries = fs.readdirSync(dir);
      for (const e of entries) {
        const full = fs.join(dir, e.name);
        if (e.isDirectory) walk(full, out);
        else if (e.isFile && e.name.endsWith(".md")) out.push(full);
      }
    }

    function parseNoteFile(absPath) {
      const rel = relativize(absPath).split(fs.sep).join("/");
      const content = fs.readFileSync(absPath);
      const parsed = Markdown.parseFrontmatter(content);
      const frontmatter = parsed.frontmatter;
      const body = parsed.body;
      const basename = rel.split("/").pop().replace(/\.md$/, "");
      const aliases = Array.isArray(frontmatter.aliases)
        ? frontmatter.aliases
        : (frontmatter.alias ? [frontmatter.alias] : []);
      const title = aliases[0] || frontmatter.title || basename;
      const wikilinks = Markdown.extractWikilinks(body);
      const tags = Markdown.extractTags(body).concat(
        Array.isArray(frontmatter.tags) ? frontmatter.tags : []
      );
      const mtime = fs.statSync(absPath).mtimeMs;
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
      const set = byBasename.get(note.basename) || new Set();
      set.add(note.path);
      byBasename.set(note.basename, set);
    }

    function unindexBasename(note) {
      const set = byBasename.get(note.basename);
      if (!set) return;
      set.delete(note.path);
      if (set.size === 0) byBasename.delete(note.basename);
    }

    function resolveLink(target) {
      const clean = target.replace(/\.md$/, "").trim();
      const set = byBasename.get(clean);
      if (set && set.size > 0) return Array.from(set)[0];
      const lower = clean.toLowerCase();
      for (const entry of byBasename) {
        if (entry[0].toLowerCase() === lower && entry[1].size > 0) {
          return Array.from(entry[1])[0];
        }
      }
      return null;
    }

    function resolveAllLinks() {
      for (const note of notes.values()) {
        const resolved = [];
        for (const raw of note.wikilinksRaw) {
          const r = resolveLink(raw);
          if (r && r !== note.path) resolved.push(r);
        }
        note.outgoingLinks = resolved;
      }
    }

    function scan(rp) {
      rootPath = rp;
      notes.clear();
      byBasename.clear();
      const files = [];
      walk(rp, files);
      for (const abs of files) {
        const note = parseNoteFile(abs);
        notes.set(note.path, note);
        indexBasename(note);
      }
      resolveAllLinks();
      emit("ready");
    }

    function noteCount() { return notes.size; }
    function getNote(relPath) { return notes.get(relPath) || null; }
    function allNotes() { return Array.from(notes.values()); }

    function getEdges() {
      const edges = [];
      for (const note of notes.values()) {
        for (const target of note.outgoingLinks) {
          edges.push({ source: note.path, target: target });
        }
      }
      return edges;
    }

    function addOrUpdateNote(absPath) {
      const rel = relativize(absPath).split(fs.sep).join("/");
      const existed = notes.get(rel);
      if (existed) unindexBasename(existed);
      const note = parseNoteFile(absPath);
      notes.set(note.path, note);
      indexBasename(note);
      resolveAllLinks();
      if (existed) emit("noteChanged", note, existed.outgoingLinks, note.outgoingLinks);
      else emit("noteAdded", note);
    }

    function removeNote(absPath) {
      const rel = relativize(absPath).split(fs.sep).join("/");
      const existed = notes.get(rel);
      if (!existed) return;
      unindexBasename(existed);
      notes.delete(rel);
      resolveAllLinks();
      emit("noteRemoved", rel);
    }

    function saveNote(relPath, content, expectedMtimeMs) {
      const note = notes.get(relPath);
      if (!note) return { ok: false, conflict: false, mtime: 0 };
      const current = fs.statSync(note.absPath).mtimeMs;
      if (expectedMtimeMs && current > expectedMtimeMs + 1) {
        return { ok: false, conflict: true, mtime: current };
      }
      fs.writeFileSync(note.absPath, content);
      addOrUpdateNote(note.absPath);
      const updated = notes.get(relPath);
      return { ok: true, conflict: false, mtime: updated.mtime };
    }

    return {
      scan: scan,
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

  return { createVaultModel: createVaultModel };
});
