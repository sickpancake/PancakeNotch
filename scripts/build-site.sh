#!/usr/bin/env bash
# Puts the website together in <folder>: the files in site/ plus the update feed. The feed lives only on
# the published site (each release adds to it), so it's fetched from there unless one is given.
# Usage: scripts/build-site.sh <folder> [appcast.xml]
set -euo pipefail

OUT="${1:?usage: scripts/build-site.sh <folder> [appcast.xml]}"
APPCAST="${2:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FEED_URL="https://sickpancake.github.io/PancakeNotch/appcast.xml"

rm -rf "$OUT"
mkdir -p "$OUT"
cp -R "$ROOT/site/." "$OUT/"

if [[ -n "$APPCAST" ]]; then
  cp "$APPCAST" "$OUT/appcast.xml"
else
  # 404 before the first release is fine; any other failure stops, so a deploy never drops the feed.
  status="$(curl -sS -o "$OUT/appcast.xml" -w '%{http_code}' "$FEED_URL" || echo 000)"
  case "$status" in
    200) ;;
    404) rm -f "$OUT/appcast.xml" ;;
    *) echo "Couldn't fetch the current update feed (HTTP $status)." >&2; exit 1 ;;
  esac
fi
echo "Site ready in $OUT"
