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
    echo "installed. Restart plasmashell to see changes:  kquitapp6 plasmashell && kstart plasmashell"
fi
