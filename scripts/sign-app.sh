#!/usr/bin/env bash
# Signs PancakeNotch.app from the inside out (no --deep): Sparkle's helpers, the frameworks, the helper
# tools, then the app. build-app.sh uses it (ad hoc unless CODESIGN_IDENTITY is set) and so does
# sign-release.sh (the project's self-signed certificate), so both sign the same parts.
# Usage: scripts/sign-app.sh <PancakeNotch.app> <identity>   ("-" signs ad hoc)
set -euo pipefail

APP="${1:?usage: scripts/sign-app.sh <PancakeNotch.app> <identity>}"
IDENTITY="${2:?missing the signing identity (- for ad hoc)}"

sign() { codesign --force --sign "$IDENTITY" --timestamp=none "$@"; }
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$SPARKLE/Autoupdate"
sign "$SPARKLE/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
sign "$APP/Contents/MacOS/pancakenotch-hook"
sign "$APP/Contents/MacOS/pancakenotch-convert"
sign "$APP"
