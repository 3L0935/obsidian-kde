// Pure JS, importable under Node (for tests) and QML.
// Under QML: import "../code/markdown.js" as Markdown

(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.Markdown = factory();
})(typeof self !== "undefined" ? self : this, function () {

  function stripCode(text) {
    let out = text.replace(/```[\s\S]*?```/g, "");
    out = out.replace(/`[^`\n]*`/g, "");
    return out;
  }

  function extractWikilinks(text) {
    const stripped = stripCode(text);
    const re = /\[\[([^\]|\n]+)(?:\|[^\]\n]*)?\]\]/g;
    const out = [];
    for (const m of stripped.matchAll(re)) out.push(m[1].trim());
    return out;
  }

  function extractTags(text) {
    const stripped = stripCode(text);
    const re = /(?:^|\s)#([a-zA-Z][a-zA-Z0-9_/-]*)/g;
    const out = [];
    for (const m of stripped.matchAll(re)) out.push(m[1]);
    return out;
  }

  function parseFrontmatter(text) {
    if (!text.startsWith("---\n") && !text.startsWith("---\r\n")) {
      return { frontmatter: {}, body: text };
    }
    const lines = text.split(/\r?\n/);
    let end = -1;
    for (let i = 1; i < lines.length; i++) {
      if (lines[i] === "---") { end = i; break; }
    }
    if (end === -1) return { frontmatter: {}, body: text };
    const fmLines = lines.slice(1, end);
    const body = lines.slice(end + 1).join("\n").replace(/^\n/, "");
    return { frontmatter: parseMiniYaml(fmLines), body };
  }

  function parseMiniYaml(lines) {
    const out = {};
    let i = 0;
    while (i < lines.length) {
      const line = lines[i];
      if (!line.trim()) { i++; continue; }
      const m = line.match(/^([A-Za-z_][A-Za-z0-9_-]*):\s*(.*)$/);
      if (!m) { i++; continue; }
      const key = m[1];
      const rest = m[2];
      if (rest === "") {
        const items = [];
        i++;
        while (i < lines.length && /^\s+-\s+/.test(lines[i])) {
          items.push(lines[i].replace(/^\s+-\s+/, "").trim());
          i++;
        }
        out[key] = items;
        continue;
      }
      if (rest.startsWith("[") && rest.endsWith("]")) {
        const inner = rest.slice(1, -1);
        out[key] = inner.split(",").map((s) => s.trim()).filter(Boolean);
      } else {
        out[key] = rest.replace(/^['"]|['"]$/g, "");
      }
      i++;
    }
    return out;
  }

  return { extractWikilinks, extractTags, parseFrontmatter, stripCode };
});
