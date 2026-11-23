#!/usr/bin/env bash
# Makes PancakeNotch.dmg, the disk image people install from: the signed app, a link to Applications,
# and a window that shows both with an arrow between them. It fills a copy of
# Resources/DMG/template.dmg (made by design/dmg/make-layout.sh), which already holds the layout,
# then signs the disk image with the same certificate as the app.
# sign-release.sh runs it after signing the app; it uses only hdiutil, ditto and codesign, so
# nothing else runs next to the keys (ADR-0005).
# Usage: scripts/make-dmg.sh <signed PancakeNotch.app> <out PancakeNotch.dmg> <identity>
set -euo pipefail

APP="${1:?usage: scripts/make-dmg.sh <PancakeNotch.app> <out.dmg> <identity>}"
DMG="${2:?usage: scripts/make-dmg.sh <PancakeNotch.app> <out.dmg> <identity>}"
IDENTITY="${3:?missing the signing identity}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="$ROOT/Resources/DMG/template.dmg"

fail() { echo "::error::Disk image: $1" >&2; exit 1; }
[[ -d "$APP" ]] || fail "no app at $APP."
[[ -f "$TEMPLATE" ]] || fail "no layout at $TEMPLATE."
[[ ! -e "$DMG" ]] || fail "$DMG already exists."
codesign --verify --strict --deep "$APP" || fail "the app's signature doesn't verify, so it isn't packed."

WORK="$(mktemp -d)"
cleanup() {
  [[ -d "$WORK/mount" ]] && hdiutil detach -quiet -force "$WORK/mount" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

hdiutil convert -quiet "$TEMPLATE" -format UDRW -o "$WORK/rw.dmg" || fail "hdiutil couldn't copy the layout."
# The layout is kept as small as it gets; room for the app first (the end shrinks it back).
hdiutil resize -quiet -size 1g "$WORK/rw.dmg" || fail "hdiutil couldn't make room for the app."
mkdir -p "$WORK/mount"
hdiutil attach -quiet -nobrowse -noautoopen -mountpoint "$WORK/mount" "$WORK/rw.dmg" || fail "hdiutil couldn't open it."
ditto "$APP" "$WORK/mount/PancakeNotch.app" || fail "the app didn't fit."
cp "$ROOT/Resources/AppIcon.icns" "$WORK/mount/.VolumeIcon.icns"
rm -rf "$WORK/mount/.fseventsd"
hdiutil detach -quiet "$WORK/mount" || fail "hdiutil couldn't close it."
rmdir "$WORK/mount"
hdiutil resize -quiet -sectors min "$WORK/rw.dmg" || fail "hdiutil couldn't shrink it."
hdiutil convert -quiet "$WORK/rw.dmg" -format ULFO -o "$DMG" || fail "hdiutil couldn't compress it."

codesign --sign "$IDENTITY" --timestamp=none "$DMG" || fail "signing failed."
codesign --verify --strict "$DMG" || fail "its signature doesn't verify."
echo "Made $DMG"
