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

  function escapeHtml(s) {
    return s
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function renderInline(text) {
    // Must escape first, then apply markdown — but markdown uses special
    // chars like * and [ which don't need escaping. HTML chars do.
    let out = escapeHtml(text);
    // Inline code: `code`
    out = out.replace(/`([^`\n]+)`/g, function (_, c) { return "<code>" + c + "</code>"; });
    // Bold: **text**
    out = out.replace(/\*\*([^*\n]+)\*\*/g, "<strong>$1</strong>");
    // Italic: *text*
    out = out.replace(/\*([^*\n]+)\*/g, "<em>$1</em>");
    // Links: [text](url)
    out = out.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g,
      function (_, label, url) { return "<a href=\"" + url + "\">" + label + "</a>"; });
    return out;
  }

  function renderHtml(text) {
    // Split into blocks on blank lines, but also handle fenced code specially.
    const lines = text.split(/\r?\n/);
    const out = [];
    let i = 0;

    while (i < lines.length) {
      const line = lines[i];

      // Fenced code block
      if (/^```/.test(line)) {
        const buf = [];
        i++;
        while (i < lines.length && !/^```/.test(lines[i])) {
          buf.push(escapeHtml(lines[i]));
          i++;
        }
        i++; // skip closing fence
        out.push("<pre><code>" + buf.join("\n") + "</code></pre>");
        continue;
      }

      // Heading
      const hm = line.match(/^(#{1,6})\s+(.*)$/);
      if (hm) {
        const level = hm[1].length;
        out.push("<h" + level + ">" + renderInline(hm[2]) + "</h" + level + ">");
        i++;
        continue;
      }

      // Bullet list
      if (/^[-*]\s+/.test(line)) {
        const items = [];
        while (i < lines.length && /^[-*]\s+/.test(lines[i])) {
          items.push("<li>" + renderInline(lines[i].replace(/^[-*]\s+/, "")) + "</li>");
          i++;
        }
        out.push("<ul>" + items.join("") + "</ul>");
        continue;
      }

      // Numbered list
      if (/^\d+\.\s+/.test(line)) {
        const items = [];
        while (i < lines.length && /^\d+\.\s+/.test(lines[i])) {
          items.push("<li>" + renderInline(lines[i].replace(/^\d+\.\s+/, "")) + "</li>");
          i++;
        }
        out.push("<ol>" + items.join("") + "</ol>");
        continue;
      }

      // Blank line
      if (!line.trim()) {
        i++;
        continue;
      }

      // Paragraph: gather consecutive non-blank, non-block lines
      const buf = [];
      while (
        i < lines.length &&
        lines[i].trim() &&
        !/^```/.test(lines[i]) &&
        !/^#{1,6}\s+/.test(lines[i]) &&
        !/^[-*]\s+/.test(lines[i]) &&
        !/^\d+\.\s+/.test(lines[i])
      ) {
        buf.push(lines[i]);
        i++;
      }
      out.push("<p>" + renderInline(buf.join(" ")) + "</p>");
    }

    return out.join("\n");
  }

  return { extractWikilinks, extractTags, parseFrontmatter, stripCode, renderHtml };
});
