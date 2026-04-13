# Obsidian KDE Widget

A Plasma 6 desktop widget that turns an Obsidian vault into an ambient force-directed
graph on your desktop, with inline markdown reading and editing. Multiple instances
can coexist: pin a note as a floating editable card, or leave a live graph drifting
in the background.

Zero C++, zero Python, zero daemons — pure QML + JavaScript.

## Features

- **Ambient graph view** — force-directed layout of the whole vault (Barnes-Hut,
  adaptive tick rate so it idles near-zero CPU once settled).
- **Pan / zoom / drag** — mouse wheel zooms around cursor, left-drag pans,
  grab any node to pin it, double-click to open.
- **Rendered + edit modes** — click a node to read the note, click Edit to tweak it.
  Debounced autosave with mtime-based conflict detection.
- **Obsidian color groups** — reads `.obsidian/graph.json` from the vault and
  colors nodes using your existing Obsidian groups (`path:`, `file:`, `tag:`,
  `#tag`, and `OR` combinations).
- **Wikilinks** — `[[note]]` and `[[note|alias]]` resolve by basename and are
  clickable in rendered mode.
- **Two modes per instance**:
  - `dynamic` — graph ↔ page, with an idle timer that falls back to the graph.
  - `pinned` — a single note, always in page view, editable. Great for scratchpads.
- **Configurable opacity** — independent sliders for graph view and page view
  so the graph can sit translucent on your wallpaper while notes stay readable.
- **Live filesystem sync** — vault changes on disk propagate to the widget via
  `FolderListModel`-based async walking (no inotify backend required).

## Screenshots

_TODO: add after first packaged release._

## Requirements

- KDE Plasma **6.0+**
- Qt **6.6+**
- An Obsidian vault (or any folder full of markdown files — Obsidian-specific
  features like color groups just degrade gracefully if absent).

## Install

```bash
# from a clone of this repo
./package.sh --install
```

Or manually:

```bash
./package.sh
kpackagetool6 -t Plasma/Applet -i obsidianwidget-0.2.0.plasmoid
# to update later:
kpackagetool6 -t Plasma/Applet -u obsidianwidget-0.2.0.plasmoid
```

Then add "Obsidian Vault" from your Plasma widget picker.

### Important: enable local file reads

Plasma 6 / Qt 6 disables `XMLHttpRequest` on `file://` URLs by default, which
breaks reading your markdown files. You need to export one environment variable
into `plasmashell` **before** it starts:

```bash
mkdir -p ~/.config/plasma-workspace/env
cat > ~/.config/plasma-workspace/env/obsidian-widget.sh <<'EOF'
export QML_XHR_ALLOW_FILE_READ=1
EOF
chmod +x ~/.config/plasma-workspace/env/obsidian-widget.sh
```

Log out and back in (or `kquitapp6 plasmashell && kstart plasmashell`).

Without this flag the widget renders an empty graph (it can walk the vault
but not read file contents).

## Configuration

Right-click the widget → *Configure Obsidian Vault…*

| Setting              | Default   | Description                                              |
|----------------------|-----------|----------------------------------------------------------|
| Vault path           | _(empty)_ | Absolute path to your vault root.                        |
| Mode                 | dynamic   | `dynamic` (graph ↔ page) or `pinned` (single note).      |
| Pinned note          | _(empty)_ | Relative path (`folder/note.md`), required in pinned mode.|
| Idle timeout         | 30 s      | Dynamic mode: time before page view falls back to graph. |
| Autosave debounce    | 500 ms    | Delay after last keystroke before writing the file.      |
| Show node labels     | on        | Render note titles next to nodes in the graph.           |
| Graph opacity        | 50 %      | Background opacity in graph view.                        |
| Page opacity         | 95 %      | Background opacity in page view.                         |

Multiple instances are fully independent — you can drop a `pinned` card for a
project TODO and a `dynamic` graph for navigating, side by side.

## Obsidian compatibility

What works:

- Standard markdown (headings, lists, code blocks, bold/italic, links)
- Frontmatter (YAML subset: scalars, `aliases`, `tags`, arrays)
- `[[wikilinks]]` and `[[wikilinks|alias]]`
- Inline `#tags`
- Color groups from `.obsidian/graph.json` (`path:`, `file:`, `tag:`, `#tag`,
  combined with `OR`)

What's out of scope (MVP):

- Embeds `![[note]]`, callouts, LaTeX, mermaid, dataview
- Obsidian plugins
- Ghost links (unresolved link creation), rename detection
- Multi-vault per instance
- Git integration

## Development

```bash
# run without installing
plasmoidviewer -a .

# same, with local file reads enabled (required)
QML_XHR_ALLOW_FILE_READ=1 plasmoidviewer -a .

# unit tests (pure JS, no QML)
node tests/run.js
```

### Layout

```
contents/
├── ui/                    # QML components
│   ├── main.qml           # PlasmoidItem, state machine, vault loader
│   ├── GraphView.qml      # Canvas rendering + pan/zoom/drag
│   ├── PageView.qml       # Rendered + edit modes, autosave
│   ├── configGeneral.qml  # Config page
│   └── components/        # FsHelper, FsListModel, SaveIndicator, ConflictBanner
├── code/                  # Pure-JS, unit-tested
│   ├── vault.js           # Scan, index, wikilink resolution, save with conflict
│   ├── markdown.js        # Frontmatter, wikilinks, tags, inline renderer
│   ├── graph-physics.js   # Force-directed Barnes-Hut simulation
│   └── qml-fs.js          # Qt/QML filesystem adapter (XHR-based read/write)
└── config/                # KConfig schema + config.qml
```

## License

MIT — see metadata.json.
