#!/usr/bin/env bash
# Builds PancakeNotch.app into ./build using only Swift Package Manager (no Xcode needed).
# Usage: scripts/build-app.sh [debug|release]   (default: release)
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/PancakeNotch.app"

cd "$ROOT"
"$ROOT/scripts/swift.sh" build -c "$CONFIG" --arch arm64
BIN_DIR="$("$ROOT/scripts/swift.sh" build -c "$CONFIG" --arch arm64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/PancakeNotch" "$APP/Contents/MacOS/PancakeNotch"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Now Playing's helper (ADR-0012): the vendored mediaremote-adapter, run by /usr/bin/perl at runtime.
# The framework is built from source with clang; the script and its licence ship next to it.
"$ROOT/scripts/build-adapter.sh" "$APP/Contents/Frameworks" >/dev/null
cp "$ROOT/Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl" "$APP/Contents/Resources/mediaremote-adapter.pl"
cp "$ROOT/Vendor/mediaremote-adapter/LICENSE" "$APP/Contents/Resources/mediaremote-adapter-LICENSE.txt"

# Ad-hoc signature for now; the release workflow will use the project's self-signed identity (ADR-0005).
# The framework inside is signed first (build-adapter.sh), so the app's signature covers it.
codesign --force --sign "${CODESIGN_IDENTITY:--}" --timestamp=none "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
codesign --force --sign "${CODESIGN_IDENTITY:--}" --timestamp=none "$APP"

echo "Built $APP"
