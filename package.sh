#!/usr/bin/env bash
# Package the plasmoid into a .plasmoid zip for distribution / install.
# Usage: ./package.sh          → produces obsidianwidget-<version>.plasmoid
#        ./package.sh --install → package + kpackagetool6 -u (upgrade) in place

set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(grep -oP '"Version"\s*:\s*"\K[^"]+' metadata.json)
OUT="obsidianwidget-${VERSION}.plasmoid"

rm -f "$OUT"
if command -v zip >/dev/null; then
    zip -qr "$OUT" metadata.json contents/ -x '*~' '*/.DS_Store'
elif command -v 7z >/dev/null; then
    7z a -tzip -bd -bso0 "$OUT" metadata.json contents/ -xr'!*~' -xr'!.DS_Store' >/dev/null
elif command -v bsdtar >/dev/null; then
    bsdtar --format zip -cf "$OUT" metadata.json contents/
else
    echo "need zip, 7z, or bsdtar" >&2
    exit 1
fi

echo "built $OUT ($(du -h "$OUT" | cut -f1))"

if [[ "${1:-}" == "--install" ]]; then
    if kpackagetool6 -t Plasma/Applet -l 2>/dev/null | grep -q '^org.kde.plasma.obsidianwidget$'; then
        kpackagetool6 -t Plasma/Applet -u "$OUT"
    else
        kpackagetool6 -t Plasma/Applet -i "$OUT"
    fi

    # Qt 6 disables file:// XHR by default. The widget reads/writes markdown
    # via XHR, so plasmashell needs these flags in its env. We drop a file
    # into plasma-workspace/env which is sourced at every Plasma login.
    ENV_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/plasma-workspace/env/obsidian-widget.sh"
    if [[ ! -f "$ENV_FILE" ]]; then
        mkdir -p "$(dirname "$ENV_FILE")"
        cat > "$ENV_FILE" <<'EOF'
#!/bin/sh
export QML_XHR_ALLOW_FILE_READ=1
export QML_XHR_ALLOW_FILE_WRITE=1
EOF
        chmod +x "$ENV_FILE"
        echo "wrote $ENV_FILE (QML_XHR_ALLOW_FILE_READ/WRITE)"
        NEEDS_RELOGIN=1
    fi

    echo "installed."
    if [[ "${NEEDS_RELOGIN:-0}" == "1" ]]; then
        echo "First-time setup: log out and back in so plasmashell picks up the"
        echo "new env vars, or run:"
        echo "  systemctl --user set-environment QML_XHR_ALLOW_FILE_READ=1 QML_XHR_ALLOW_FILE_WRITE=1"
        echo "  kquitapp6 plasmashell && kstart plasmashell"
    else
        echo "Restart plasmashell to see changes:  kquitapp6 plasmashell && kstart plasmashell"
    fi
fi
