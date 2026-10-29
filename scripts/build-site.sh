#!/usr/bin/env bash
# Puts the website together in <folder>: the home page (the React app in web/, built here), the Help page
# and its assets (site/), plus the update feed. The feed isn't kept in the repo (each release adds to
# it), so unless one is given it's fetched with get-update-feed.sh (from the latest GitHub Release).
# Needs Node (22 or newer) for the home page; the app's links point at help/ and its anchors, so those
# stay where they were (ADR-0027, ADR-0036).
# <folder> has to be new, empty, or an earlier site from this script: it's emptied first, and a typo
# must never empty some other folder.
# Usage: scripts/build-site.sh <folder> [appcast.xml]
set -euo pipefail

OUT="${1:?usage: scripts/build-site.sh <folder> [appcast.xml]}"
APPCAST="${2:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MARKER=".pancakenotch-site" # hidden files aren't published (upload-pages-artifact skips them)

if [[ -d "$OUT" && -n "$(ls -A "$OUT")" && ! -f "$OUT/$MARKER" ]]; then
  echo "$OUT isn't empty and isn't a site this script made; pick a new or empty folder." >&2
  exit 1
fi

# The home page: build web/ (installing its packages first if they aren't there yet).
if [[ ! -d "$ROOT/web/node_modules" ]]; then
  (cd "$ROOT/web" && npm ci --no-audit --no-fund)
fi
(cd "$ROOT/web" && npm run build)

rm -rf "$OUT"
mkdir -p "$OUT"
touch "$OUT/$MARKER"
cp -R "$ROOT/site/." "$OUT/"   # Help and the files it uses
cp -R "$ROOT/web/dist/." "$OUT/"   # the home page and its files, added on top

if [[ -n "$APPCAST" ]]; then
  cp "$APPCAST" "$OUT/appcast.xml"
else
  "$ROOT/scripts/get-update-feed.sh" "$OUT/appcast.xml"
fi
echo "Site ready in $OUT"
