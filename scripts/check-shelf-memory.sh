#!/usr/bin/env bash
# Peak-memory check for the Shelf (ADR-0006): fills a throwaway Shelf with 20 large images, pins the
# notch open so every thumbnail loads, and fails if the footprint reaches the limit.
# Shows the open notch on screen, so it runs in CI, not on a working Mac.
# Usage: scripts/check-shelf-memory.sh [path/to/PancakeNotch.app] [settle-seconds] [limit-MiB]
set -euo pipefail

APP="${1:-build/PancakeNotch.app}"
SETTLE="${2:-20}"
LIMIT_MIB="${3:-100}"   # ADR-0006: < 100 MB peak
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

WORK="$(mktemp -d)"
trap 'kill "${PID:-}" 2>/dev/null || true; rm -rf "$WORK"' EXIT
mkdir -p "$WORK/seed" "$WORK/shelf"

# Twenty 6000×4000 PNGs (~24 MP each, the size of a camera photo), made from the app icon.
sips -s format png -z 4000 6000 "$ROOT/Resources/AppIcon.icns" --out "$WORK/seed/photo-01.png" >/dev/null
for i in $(seq -w 2 20); do cp "$WORK/seed/photo-01.png" "$WORK/seed/photo-$i.png"; done

PANCAKENOTCH_SIMULATE_NOTCH=1 \
PANCAKENOTCH_DEBUG_STATE=expanded \
PANCAKENOTCH_SHELF_DIR="$WORK/shelf" \
PANCAKENOTCH_SHELF_SEED="$WORK/seed" \
"$APP/Contents/MacOS/PancakeNotch" &
PID=$!

sleep "$SETTLE"
kill -0 "$PID" 2>/dev/null || { echo "App exited early"; exit 1; }

BYTES="$(footprint --pid "$PID" --format bytes --noCategories | awk '/phys_footprint:/ { print $2; exit }')"
[[ -n "$BYTES" ]] || { echo "Could not read footprint"; footprint --pid "$PID" --noCategories; exit 1; }

MIB=$(( BYTES / 1024 / 1024 ))
echo "Shelf peak footprint (20 large images, notch open): ${MIB} MiB (limit ${LIMIT_MIB} MiB)"
(( MIB < LIMIT_MIB )) || { echo "Memory budget exceeded"; exit 1; }
