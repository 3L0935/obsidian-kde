# Obsidian KDE Widget

A Plasma 6 desktop widget that turns an Obsidian vault into an ambient force-directed
graph on your desktop, with inline markdown reading and editing. Multiple instances
can coexist: pin a note as a floating editable card, or leave a live graph drifting
in the background.

Zero C++, zero Python, zero daemons — pure QML + JavaScript.

## Features

- **Ambient graph view** — force-directed layout of the whole vault
  (Barnes-Hut quadtree, adaptive tick rate so it idles near-zero CPU).
- **Tunable physics** — 6 live sliders (repel force, link length, link
  force, center gravity, damping, max speed) with floaty defaults
  calibrated for a calm "on the moon" feel. Reset button to restore
  defaults in one click.
- **Pan / zoom / drag** — mouse wheel zooms around cursor, left-drag pans,
  grab any node to drag it around (the physics follow).
- **Click to select, button to open** — single click highlights a node,
  a *Open: &lt;title&gt;* button appears, `Enter` / `Space` also activates.
  Double-click is left to plasmashell for widget move/resize.
- **Rendered + edit modes** — click a node to read the note, click *Edit*
  to tweak it. Choose between **autosave** (debounced, silent) or **manual
  save** (explicit Save button that only appears while dirty — no flashing).
- **Obsidian color groups** — reads `.obsidian/graph.json` from the vault
  and colors nodes using your existing Obsidian groups (`path:`, `file:`,
  `tag:`, `#tag`, and `OR` combinations).
- **Wikilinks** — `[[note]]` and `[[note|alias]]` resolve by basename and
  are clickable in rendered mode.
- **Two modes per instance**:
  - `dynamic` — graph ↔ page, with an idle timer that falls back to the graph.
  - `pinned` — a single note, always in page view, editable. Great for
    scratchpads. The config page has a *Browse…* picker so you don't have
    to type the path.
- **Configurable opacity** — independent sliders for graph view and page view
  so the graph can sit translucent on your wallpaper while notes stay readable.
- **Live filesystem sync** — vault changes on disk propagate via
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
kpackagetool6 -t Plasma/Applet -i obsidianwidget-0.3.0.plasmoid
# to update later:
kpackagetool6 -t Plasma/Applet -u obsidianwidget-0.3.0.plasmoid
```

Then add "Obsidian Vault" from your Plasma widget picker.

### Required: allow local file reads and writes

Plasma 6 / Qt 6 disable `XMLHttpRequest` on `file://` URLs by default. The
widget uses XHR to read your markdown files and to write edits back, so
**both** flags below are required — without `READ` the graph loads empty
(vault walks but no content parses); without `WRITE` editing a note looks
fine on screen but nothing is saved to disk.

`package.sh --install` creates the env file for you. If you install the
`.plasmoid` directly with `kpackagetool6`, set it up manually:

```bash
mkdir -p ~/.config/plasma-workspace/env
cat > ~/.config/plasma-workspace/env/obsidian-widget.sh <<'EOF'
export QML_XHR_ALLOW_FILE_READ=1
export QML_XHR_ALLOW_FILE_WRITE=1
EOF
chmod +x ~/.config/plasma-workspace/env/obsidian-widget.sh
```

The file is sourced on login by `plasma-workspace`, so the vars end up in
`plasmashell`'s environment. You need to **log out and back in** for this to
take effect, or restart `plasmashell` in place after exporting the vars into
the user systemd environment:

```bash
systemctl --user set-environment QML_XHR_ALLOW_FILE_READ=1 QML_XHR_ALLOW_FILE_WRITE=1
kquitapp6 plasmashell && kstart plasmashell
```

Diagnosis tip: if the widget stays on "Loading vault…", check
`journalctl --user -n 200 | grep obsidian` — you'll see
`XMLHttpRequest: Using GET on a local file is disabled by default` and
`parse failed: … Invalid state` for every note when the flags are missing.

## Configuration

Right-click the widget → *Configure Obsidian Vault…*

### General

| Setting            | Default   | Description                                              |
|--------------------|-----------|----------------------------------------------------------|
| Vault path         | _(empty)_ | Absolute path to your vault root.                        |
| Mode               | dynamic   | `dynamic` (graph ↔ page) or `pinned` (single note).      |
| Pinned note        | _(empty)_ | Relative or absolute path to a note inside the vault. Use *Browse…* to pick one.|
| Idle timeout       | 30 s      | Dynamic mode: time before page view falls back to graph. |
| Autosave           | on        | When on, types-and-saves after *Autosave debounce*. When off, a Save button appears while the note is dirty.|
| Autosave debounce  | 500 ms    | Delay after last keystroke before writing the file.      |
| Show node labels   | on        | Render note titles next to nodes in the graph.           |
| Graph opacity      | 50 %      | Background opacity in graph view.                        |
| Page opacity       | 95 %      | Background opacity in page view.                         |

### Graph physics

All live (changes apply without reset), with a *Reset physics to defaults* button:

| Setting        | Default | Range        | What it does                          |
|----------------|---------|--------------|----------------------------------------|
| Repel force    | 400     | 0 – 2000     | How strongly nodes push each other.    |
| Link length    | 150     | 20 – 600     | Ideal edge length.                     |
| Link force     | 0.0025  | 0 – 0.02     | How aggressively edges pull to length. |
| Center gravity | 0.0010  | 0 – 0.01     | Pull toward the origin.                |
| Damping        | 0.850   | 0.7 – 0.99   | Velocity retention per tick.           |
| Max speed      | 1.5     | 0.5 – 15     | Per-tick velocity cap. Keeps motion floaty. |

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

# same, with local file I/O enabled (required — see "Required: allow local file reads and writes")
QML_XHR_ALLOW_FILE_READ=1 QML_XHR_ALLOW_FILE_WRITE=1 plasmoidviewer -a .

# unit tests (pure JS, no QML)
node tests/run.js
```

### Layout

```
contents/
├── ui/                    # QML components
│   ├── main.qml           # PlasmoidItem, state machine, vault loader
│   ├── GraphView.qml      # Canvas rendering, pan/zoom/drag, click-select
│   ├── PageView.qml       # Rendered + edit modes, autosave / manual save
│   ├── configGeneral.qml  # Config page (general + physics sliders)
│   └── components/        # FsHelper (walk + mtime cache), FsListModel, SaveIndicator
├── code/                  # Pure-JS, unit-tested
│   ├── vault.js           # Scan, index, wikilink resolution, dual-mode saveNote
│   ├── markdown.js        # Frontmatter, wikilinks, tags, inline renderer
│   ├── graph-physics.js   # Force-directed Barnes-Hut, live-reconfigurable
│   └── qml-fs.js          # Qt/QML filesystem adapter (sync XHR read, async PUT)
└── config/                # KConfig schema + config.qml
```

### Writing notes works via async XHR PUT

Qt 6.11's **synchronous** `XMLHttpRequest.send()` with `PUT` on `file://`
opens the target file but silently drops the body (0-byte output — verified
with a standalone `qml6` repro). Only the **async** path actually writes, so
`qml-fs.js:writeFile` uses `xhr.open(..., true)` and `vault.js:saveNote`
exposes a callback-based variant the QML side uses; Node tests keep the
synchronous `writeFileSync` path.

## License

MIT — see metadata.json.
