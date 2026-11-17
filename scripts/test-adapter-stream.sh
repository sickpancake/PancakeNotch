#!/usr/bin/env bash
# Exercise the production stream with fake MediaRemote callbacks; no real player or app is launched.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Vendor/mediaremote-adapter/src"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
clang -fobjc-arc -Wno-deprecated-declarations -mmacosx-version-min=15.0 \
  -I "$SRC" -I "$ROOT/Vendor/mediaremote-adapter/include" \
  -framework Foundation -framework AppKit -framework UniformTypeIdentifiers -framework ImageIO \
  "$ROOT/Tests/AdapterStreamTests/ClosedSessionTests.m" \
  "$SRC/adapter/keys.m" "$SRC/adapter/env.m" "$SRC/adapter/now_playing.m" \
  "$SRC/private/MediaRemote.m" "$SRC/utility/helpers.m" "$SRC/utility/Debounce.m" \
  -o "$OUT/closed-session-tests"
MEDIAREMOTEADAPTER_OPTION_no_diff=1 "$OUT/closed-session-tests"
