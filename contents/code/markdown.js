// Pure JS, works under both Node (for tests) and QML JS import.
// QML: import "../code/markdown.js" as MD  → call MD.extractWikilinks(...)
// Node: const md = require("../contents/code/markdown.js")

function stripCode(text) {
    var out = text.replace(/```[\s\S]*?```/g, "");
    out = out.replace(/`[^`\n]*`/g, "");
    return out;
}

function extractWikilinks(text) {
    var stripped = stripCode(text);
    var out = [];
    stripped.replace(/\[\[([^\]|\n]+)(?:\|[^\]\n]*)?\]\]/g, function (_, target) {
        out.push(target.trim());
        return "";
    });
    return out;
}

function extractTags(text) {
    var stripped = stripCode(text);
    var out = [];
    stripped.replace(/(?:^|\s)#([a-zA-Z][a-zA-Z0-9_/-]*)/g, function (_, tag) {
        out.push(tag);
        return "";
    });
    return out;
}

function parseFrontmatter(text) {
    if (!text.startsWith("---\n") && !text.startsWith("---\r\n")) {
        return { frontmatter: {}, body: text };
    }
    var lines = text.split(/\r?\n/);
    var end = -1;
    for (var i = 1; i < lines.length; i++) {
        if (lines[i] === "---") { end = i; break; }
    }
    if (end === -1) return { frontmatter: {}, body: text };
    var fmLines = lines.slice(1, end);
    var body = lines.slice(end + 1).join("\n").replace(/^\n/, "");
    return { frontmatter: parseMiniYaml(fmLines), body: body };
}

function parseMiniYaml(lines) {
    var out = {};
    var i = 0;
    while (i < lines.length) {
        var line = lines[i];
        if (!line.trim()) { i++; continue; }
        var m = line.match(/^([A-Za-z_][A-Za-z0-9_-]*):\s*(.*)$/);
        if (!m) { i++; continue; }
        var key = m[1];
        var rest = m[2];
        if (rest === "") {
            var items = [];
            i++;
            while (i < lines.length && /^\s+-\s+/.test(lines[i])) {
                items.push(lines[i].replace(/^\s+-\s+/, "").trim());
                i++;
            }
            out[key] = items;
            continue;
        }
        if (rest.startsWith("[") && rest.endsWith("]")) {
            var inner = rest.slice(1, -1);
            out[key] = inner.split(",").map(function (s) { return s.trim(); }).filter(Boolean);
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
    var out = escapeHtml(text);
    out = out.replace(/`([^`\n]+)`/g, function (_, c) { return "<code>" + c + "</code>"; });
    out = out.replace(/\*\*([^*\n]+)\*\*/g, "<strong>$1</strong>");
    out = out.replace(/\*([^*\n]+)\*/g, "<em>$1</em>");
    out = out.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g,
        function (_, label, url) { return "<a href=\"" + url + "\">" + label + "</a>"; });
    return out;
}

function splitTableRow(line) {
    var s = line.trim().replace(/^\|/, "").replace(/\|$/, "");
    return s.split("|").map(function (c) { return c.trim(); });
}

function renderHtml(text) {
    var lines = text.split(/\r?\n/);
    var out = [];
    var i = 0;

    while (i < lines.length) {
        var line = lines[i];

        if (/^```/.test(line)) {
            var buf = [];
            i++;
            while (i < lines.length && !/^```/.test(lines[i])) {
                buf.push(escapeHtml(lines[i]));
                i++;
            }
            i++;
            out.push("<pre><code>" + buf.join("\n") + "</code></pre>");
            continue;
        }

        var hm = line.match(/^(#{1,6})\s+(.*)$/);
        if (hm) {
            var level = hm[1].length;
            out.push("<h" + level + ">" + renderInline(hm[2]) + "</h" + level + ">");
            i++;
            continue;
        }

        if (/^[-*]\s+/.test(line)) {
            var items = [];
            while (i < lines.length && /^[-*]\s+/.test(lines[i])) {
                items.push("<li>" + renderInline(lines[i].replace(/^[-*]\s+/, "")) + "</li>");
                i++;
            }
            out.push("<ul>" + items.join("") + "</ul>");
            continue;
        }

        if (/^\d+\.\s+/.test(line)) {
            var oitems = [];
            while (i < lines.length && /^\d+\.\s+/.test(lines[i])) {
                oitems.push("<li>" + renderInline(lines[i].replace(/^\d+\.\s+/, "")) + "</li>");
                i++;
            }
            out.push("<ol>" + oitems.join("") + "</ol>");
            continue;
        }

        if (/^\s*\|.*\|\s*$/.test(line) &&
            i + 1 < lines.length &&
            /^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)+\|?\s*$/.test(lines[i + 1])) {
            var header = splitTableRow(line);
            i += 2;
            var rows = [];
            while (i < lines.length && /^\s*\|.*\|\s*$/.test(lines[i])) {
                rows.push(splitTableRow(lines[i]));
                i++;
            }
            var thead = "<tr>" + header.map(function (c) {
                return "<th>" + renderInline(c) + "</th>";
            }).join("") + "</tr>";
            var tbody = rows.map(function (r) {
                return "<tr>" + r.map(function (c) {
                    return "<td>" + renderInline(c) + "</td>";
                }).join("") + "</tr>";
            }).join("");
            out.push("<table border=\"1\" cellpadding=\"4\" cellspacing=\"0\">" + thead + tbody + "</table>");
            continue;
        }

        if (/^\s*(-{3,}|\*{3,}|_{3,})\s*$/.test(line)) {
            out.push("<hr/>");
            i++;
            continue;
        }

        if (!line.trim()) {
            var blanks = 0;
            while (i < lines.length && !lines[i].trim()) { blanks++; i++; }
            for (var b = 1; b < blanks; b++) out.push("<br/>");
            continue;
        }

        var pbuf = [];
        while (
            i < lines.length &&
            lines[i].trim() &&
            !/^```/.test(lines[i]) &&
            !/^#{1,6}\s+/.test(lines[i]) &&
            !/^[-*]\s+/.test(lines[i]) &&
            !/^\d+\.\s+/.test(lines[i])
        ) {
            pbuf.push(lines[i]);
            i++;
        }
        out.push("<p>" + renderInline(pbuf.join(" ")) + "</p>");
    }

    return out.join("\n");
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        stripCode: stripCode,
        extractWikilinks: extractWikilinks,
        extractTags: extractTags,
        parseFrontmatter: parseFrontmatter,
        renderHtml: renderHtml,
    };
}
