const md = require("../contents/code/markdown.js");

describe("extractWikilinks", () => {
  it("extracts simple wikilinks", () => {
    assertDeepEqual(md.extractWikilinks("Hello [[foo]] and [[bar]]"), ["foo", "bar"]);
  });

  it("extracts wikilinks with aliases as the target only", () => {
    assertDeepEqual(md.extractWikilinks("See [[foo|the foo note]]"), ["foo"]);
  });

  it("ignores wikilinks inside fenced code blocks", () => {
    const input = "before\n```\n[[not-a-link]]\n```\nafter [[real]]";
    assertDeepEqual(md.extractWikilinks(input), ["real"]);
  });

  it("ignores wikilinks inside inline code", () => {
    assertDeepEqual(md.extractWikilinks("Use `[[syntax]]` to link, e.g. [[target]]"), ["target"]);
  });

  it("returns empty array when none", () => {
    assertDeepEqual(md.extractWikilinks("plain text"), []);
  });
});

describe("extractTags", () => {
  it("extracts simple tags", () => {
    assertDeepEqual(md.extractTags("Hello #foo and #bar/nested"), ["foo", "bar/nested"]);
  });

  it("ignores tags in code blocks", () => {
    assertDeepEqual(md.extractTags("```\n#not\n```\n#yes"), ["yes"]);
  });

  it("ignores headings and numeric tags", () => {
    assertDeepEqual(md.extractTags("# heading\n#123 not-a-tag\n#real"), ["real"]);
  });
});

describe("parseFrontmatter", () => {
  it("returns empty object when no frontmatter", () => {
    const r = md.parseFrontmatter("# Title\nbody");
    assertDeepEqual(r.frontmatter, {});
    assertEqual(r.body, "# Title\nbody");
  });

  it("parses simple key: value pairs", () => {
    const input = "---\ntitle: My Note\ntags: [a, b]\n---\n# Body";
    const r = md.parseFrontmatter(input);
    assertEqual(r.frontmatter.title, "My Note");
    assertDeepEqual(r.frontmatter.tags, ["a", "b"]);
    assertEqual(r.body, "# Body");
  });

  it("parses aliases list", () => {
    const input = "---\naliases:\n  - Foo\n  - Bar\n---\n";
    const r = md.parseFrontmatter(input);
    assertDeepEqual(r.frontmatter.aliases, ["Foo", "Bar"]);
  });

  it("does not treat --- in body as frontmatter end", () => {
    const input = "---\ntitle: t\n---\n\nbody text\n\n---\n\nmore";
    const r = md.parseFrontmatter(input);
    assertEqual(r.frontmatter.title, "t");
    assertTrue(r.body.includes("more"), "body should include content after second ---");
  });
});
