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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/PancakeNotch" "$APP/Contents/MacOS/PancakeNotch"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature for now; the release workflow will use the project's self-signed identity (ADR-0005).
codesign --force --sign "${CODESIGN_IDENTITY:--}" --timestamp=none "$APP"

echo "Built $APP"
