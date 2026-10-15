#!/usr/bin/env bash
# Puts the website together in <folder>: the files in site/ plus the update feed. The feed isn't kept in
# the repo (each release adds to it), so unless one is given it's fetched: from the published site, or
# else from the latest GitHub Release, which carries the full feed too. That second source matters
# because GitHub Pages keeps only one deploy per commit: when the website deploy for a commit wins the
# race against its release, the feed would otherwise be missing until the next release.
# Usage: scripts/build-site.sh <folder> [appcast.xml]
set -euo pipefail

OUT="${1:?usage: scripts/build-site.sh <folder> [appcast.xml]}"
APPCAST="${2:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FEED_URL="https://sickpancake.github.io/PancakeNotch/appcast.xml"
RELEASE_FEED_URL="https://github.com/sickpancake/PancakeNotch/releases/latest/download/appcast.xml"

rm -rf "$OUT"
mkdir -p "$OUT"
cp -R "$ROOT/site/." "$OUT/"

if [[ -n "$APPCAST" ]]; then
  cp "$APPCAST" "$OUT/appcast.xml"
else
  # 404 from both before the first release is fine; any other failure stops, so a deploy never drops
  # the feed.
  fetch() {
    local status
    status="$(curl -sSL -o "$OUT/appcast.xml" -w '%{http_code}' "$1" || echo 000)"
    case "$status" in
      200) return 0 ;;
      404) rm -f "$OUT/appcast.xml"; return 1 ;;
      *) echo "Couldn't fetch the update feed from $1 (HTTP $status)." >&2; exit 1 ;;
    esac
  }
  fetch "$FEED_URL" || fetch "$RELEASE_FEED_URL" || true
fi
echo "Site ready in $OUT"
