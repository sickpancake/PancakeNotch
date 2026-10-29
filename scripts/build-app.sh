#!/usr/bin/env bash
# Builds PancakeNotch.app into ./build using only Swift Package Manager (no Xcode needed).
# Usage: scripts/build-app.sh [debug|release]   (default: release)
#
# Optional environment (for trying updates locally; releases set these in sign-release.sh):
#   PANCAKENOTCH_VERSION   version shown to people, e.g. 0.1.0 (CFBundleShortVersionString; default: newest CHANGELOG.md version)
#   PANCAKENOTCH_BUILD     a number that grows with every release (CFBundleVersion; Sparkle compares it)
#   SPARKLE_PUBLIC_ED_KEY  the update-signing public key; without it the app can't update itself
#   CODESIGN_IDENTITY      a signing certificate's name; without it the app is signed ad hoc
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/PancakeNotch.app"
IDENTITY="${CODESIGN_IDENTITY:--}"

cd "$ROOT"
"$ROOT/scripts/swift.sh" build -c "$CONFIG" --arch arm64
BIN_DIR="$("$ROOT/scripts/swift.sh" build -c "$CONFIG" --arch arm64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/PancakeNotch" "$APP/Contents/MacOS/PancakeNotch"
# Agents' hook helper (ADR-0037): a small C program the AI tools run after Connect, which copies it
# to Application Support so the tools' settings don't depend on where the app is.
cp "$BIN_DIR/pancakenotch-hook" "$APP/Contents/MacOS/pancakenotch-hook"
# The Shelf's conversion helper (ADR-0038): started for one conversion at a time, so the media
# frameworks never load into the app.
cp "$BIN_DIR/pancakenotch-convert" "$APP/Contents/MacOS/pancakenotch-convert"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

PLIST="$APP/Contents/Info.plist"
# Local builds show the newest CHANGELOG version, so the About line isn't stuck on Info.plist's 0.0.1.
PANCAKENOTCH_VERSION="${PANCAKENOTCH_VERSION:-$(sed -nE 's/^## ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' "$ROOT/CHANGELOG.md" | head -1)}"
if [[ -n "${PANCAKENOTCH_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $PANCAKENOTCH_VERSION" "$PLIST"
fi
if [[ -n "${PANCAKENOTCH_BUILD:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $PANCAKENOTCH_BUILD" "$PLIST"
fi
if [[ -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_ED_KEY" "$PLIST"
fi

# Now Playing's helper (ADR-0012): the vendored mediaremote-adapter, run by /usr/bin/perl at runtime.
# The framework is built from source with clang; the script and its licence ship next to it.
"$ROOT/scripts/build-adapter.sh" "$APP/Contents/Frameworks" >/dev/null
cp "$ROOT/Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl" "$APP/Contents/Resources/mediaremote-adapter.pl"
cp "$ROOT/Vendor/mediaremote-adapter/LICENSE" "$APP/Contents/Resources/mediaremote-adapter-LICENSE.txt"

# Automatic updates (ADR-0005): Sparkle's framework, found next to the app through the Frameworks rpath.
# The app isn't sandboxed, so Sparkle's XPC services aren't needed (they're for sandboxed apps).
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/PancakeNotch"

# A smaller download: Apple Silicon code only (ADR-0021), English only (ADR-0022), no header files,
# and no debug symbols or build-machine paths in the release app (the debug build keeps its symbols).
SPARKLE_DIR="$APP/Contents/Frameworks/Sparkle.framework"
for BINARY in "$SPARKLE_DIR/Versions/B/Sparkle" "$SPARKLE_DIR/Versions/B/Autoupdate" \
    "$SPARKLE_DIR/Versions/B/Updater.app/Contents/MacOS/Updater"; do
  if lipo "$BINARY" -verify_arch x86_64 2>/dev/null; then lipo "$BINARY" -thin arm64 -output "$BINARY"; fi
done
find "$SPARKLE_DIR/Versions/B" -name '*.lproj' ! -name 'Base.lproj' ! -name 'en.lproj' -prune -exec rm -rf {} +
rm -rf "$SPARKLE_DIR/Versions/B/Headers" "$SPARKLE_DIR/Versions/B/PrivateHeaders" "$SPARKLE_DIR/Versions/B/Modules" \
  "$SPARKLE_DIR/Headers" "$SPARKLE_DIR/PrivateHeaders" "$SPARKLE_DIR/Modules"
if [[ "$CONFIG" == "release" ]]; then
  strip -S -x "$APP/Contents/MacOS/PancakeNotch" 2>/dev/null
  strip -S -x "$APP/Contents/MacOS/pancakenotch-hook" 2>/dev/null
  strip -S -x "$APP/Contents/MacOS/pancakenotch-convert" 2>/dev/null
  # Toolchain paths baked in at link time (they don't exist on people's Macs; Swift lives in /usr/lib/swift).
  for BINARY in "$APP/Contents/MacOS/PancakeNotch" "$APP/Contents/MacOS/pancakenotch-convert"; do
    otool -l "$BINARY" | awk '/LC_RPATH/ { getline; getline; print $2 }' | while read -r RPATH; do
      case "$RPATH" in /usr/lib/*|@*) ;; *) install_name_tool -delete_rpath "$RPATH" "$BINARY" ;; esac
    done
  done
fi
SPARKLE_LICENSE="$(find "$ROOT/.build/checkouts/Sparkle" "$ROOT/.build/artifacts" -maxdepth 3 -name LICENSE -path '*parkle*' 2>/dev/null | head -1)"
if [[ -n "$SPARKLE_LICENSE" ]]; then
  cp "$SPARKLE_LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE.txt"
fi

# Signed from the inside out. Ad hoc unless CODESIGN_IDENTITY names a certificate; releases are signed
# later, in their own step, by sign-release.sh.
"$ROOT/scripts/sign-app.sh" "$APP" "$IDENTITY"

echo "Built $APP"
