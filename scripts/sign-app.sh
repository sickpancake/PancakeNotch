#!/usr/bin/env bash
# Signs PancakeNotch.app from the inside out (no --deep): Sparkle's helpers, the frameworks, the helper
# tools, then the app. build-app.sh uses it (ad hoc unless CODESIGN_IDENTITY is set) and so does
# sign-release.sh (the project's self-signed certificate), so both sign the same parts.
# Everything gets the hardened runtime, so other programs can't slip code into PancakeNotch and use its
# permissions (ADR-0005, 2026-10-28). Only the app has entitlements (Resources/PancakeNotch.entitlements);
# check-release.sh checks both.
# Usage: scripts/sign-app.sh <PancakeNotch.app> <identity>   ("-" signs ad hoc)
set -euo pipefail

APP="${1:?usage: scripts/sign-app.sh <PancakeNotch.app> <identity>}"
IDENTITY="${2:?missing the signing identity (- for ad hoc)}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
sign() { codesign --force --sign "$IDENTITY" --timestamp=none --options runtime "$@"; }
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$SPARKLE/Autoupdate"
sign "$SPARKLE/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
sign "$APP/Contents/MacOS/pancakenotch-hook"
sign "$APP/Contents/MacOS/pancakenotch-convert"
sign --entitlements "$ROOT/Resources/PancakeNotch.entitlements" "$APP"
