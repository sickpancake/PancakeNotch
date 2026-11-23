#!/usr/bin/env bash
# Rebuilds Resources/DMG/template.dmg, the empty disk image scripts/make-dmg.sh puts the app into
# (only when the design changes; releases never run this). It holds:
#   .background.tiff  render-background.swift at 1x and 2x
#   .DS_Store         Finder's window settings: size, no toolbar, icon size, where the two icons sit,
#                     and the background, made with dmgbuild (pinned below)
#   Applications      a link to /Applications
#   .VolumeIcon.icns  the app icon, as the disk's icon
# Finder finds the background through a link to this very volume, so releases fill a copy of this
# disk image rather than making a new one (a new volume would show a blank window).
# Usage: design/dmg/make-layout.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/Resources/DMG/template.dmg"
WORK="$(mktemp -d)"
cleanup() {
  [[ -d "$WORK/mount" ]] && hdiutil detach -quiet "$WORK/mount" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

swiftc -parse-as-library -o "$WORK/render" "$ROOT/design/dmg/render-background.swift"
"$WORK/render" "$WORK/background.png" 1
"$WORK/render" "$WORK/background@2x.png" 2
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$WORK/background.tiff" >/dev/null 2>&1

python3 -m venv "$WORK/venv"
"$WORK/venv/bin/pip" install --quiet --disable-pip-version-check dmgbuild==1.6.5 ds-store==1.3.1 mac-alias==2.2.2

mkdir -p "$WORK/PancakeNotch.app/Contents"
cat > "$WORK/settings.py" <<PY
files = ["$WORK/PancakeNotch.app"]
symlinks = {"Applications": "/Applications"}
background = "$WORK/background.tiff"
window_rect = ((200, 120), (600, 380))
icon_size = 128
text_size = 13
icon_locations = {"PancakeNotch.app": (160, 180), "Applications": (440, 180)}
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = "icon-view"
show_icon_preview = False
icon = "$ROOT/Resources/AppIcon.icns"
format = "UDRW"
filesystem = "HFS+"
size = "256M"
PY
"$WORK/venv/bin/dmgbuild" -s "$WORK/settings.py" PancakeNotch "$WORK/layout.dmg" >/dev/null

# The placeholder app only gave dmgbuild a name to place; releases copy the real one in.
mkdir -p "$WORK/mount"
hdiutil attach -quiet -nobrowse -noautoopen -mountpoint "$WORK/mount" "$WORK/layout.dmg"
rm -rf "$WORK/mount/PancakeNotch.app" "$WORK/mount/.fseventsd" "$WORK/mount/.Trashes"
hdiutil detach -quiet "$WORK/mount"
rmdir "$WORK/mount"
rm -f "$OUT"
hdiutil convert -quiet "$WORK/layout.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUT"
echo "Wrote $OUT"
