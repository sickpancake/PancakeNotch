#!/usr/bin/env bash
# Builds PancakeNotch.app into ./build using only Swift Package Manager (no Xcode needed).
# Usage: scripts/build-app.sh [debug|release]   (default: release)
#
# Optional environment (the release workflow sets these):
#   PANCAKENOTCH_VERSION   version shown to people, e.g. 0.1.0 (CFBundleShortVersionString)
#   PANCAKENOTCH_BUILD     a number that grows with every release (CFBundleVersion; Sparkle compares it)
#   SPARKLE_PUBLIC_ED_KEY  the update-signing public key; without it the app can't update itself
#   CODESIGN_IDENTITY      the signing certificate's name; without it the app is signed ad hoc
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
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

PLIST="$APP/Contents/Info.plist"
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
SPARKLE_LICENSE="$(find "$ROOT/.build/checkouts/Sparkle" "$ROOT/.build/artifacts" -maxdepth 3 -name LICENSE -path '*parkle*' 2>/dev/null | head -1)"
if [[ -n "$SPARKLE_LICENSE" ]]; then
  cp "$SPARKLE_LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE.txt"
fi

# Signed from the inside out (no --deep): Sparkle's helpers, the frameworks, then the app.
# Ad hoc unless CODESIGN_IDENTITY names the project's self-signed certificate (the release workflow).
sign() { codesign --force --sign "$IDENTITY" --timestamp=none "$@"; }
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$SPARKLE/Autoupdate"
sign "$SPARKLE/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
sign "$APP"

echo "Built $APP"
