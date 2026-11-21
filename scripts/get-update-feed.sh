#!/usr/bin/env bash
# Downloads the current update feed (appcast.xml) into <file>. The latest GitHub Release is the source:
# every release uploads the whole feed there. The website's copy is only a fallback, because GitHub
# Pages keeps one deploy per commit: when a website update and a release deploy the same commit, the
# site can keep the older feed, and copying the site's feed forward would hide the newest release
# (0.2.0 was missing from the site this way).
# Before the first release both are missing (404): then <file> isn't made and this still succeeds.
# Any other failure stops, so nothing goes on with a feed that lost its releases.
# Usage: scripts/get-update-feed.sh <file>
set -euo pipefail

OUT="${1:?usage: scripts/get-update-feed.sh <file>}"
RELEASE_FEED_URL="https://github.com/sickpancake/PancakeNotch/releases/latest/download/appcast.xml"
SITE_FEED_URL="https://sickpancake.github.io/PancakeNotch/appcast.xml"

fetch() {
  local status
  status="$(curl -sSL --proto '=https' -o "$OUT" -w '%{http_code}' "$1" || echo 000)"
  case "$status" in
    200) return 0 ;;
    404) rm -f "$OUT"; return 1 ;;
    *) rm -f "$OUT"; echo "Couldn't fetch the update feed from $1 (HTTP $status)." >&2; exit 1 ;;
  esac
}
fetch "$RELEASE_FEED_URL" || fetch "$SITE_FEED_URL" || true
