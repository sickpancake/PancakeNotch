#!/usr/bin/env bash
# Prints where an idle app's memory goes: footprint by category, the largest memory regions and
# the largest heap allocations. For finding what to slim down next (benchmark.yml runs it).
# Shows the notch on screen, so it runs in CI, not on a working Mac.
# Usage: scripts/diagnose-memory.sh [path/to/PancakeNotch.app] [settle-seconds]
set -euo pipefail

APP="${1:-build/PancakeNotch.app}"
SETTLE="${2:-30}"

PANCAKENOTCH_SIMULATE_NOTCH=1 PANCAKENOTCH_SKIP_ONBOARDING=1 "$APP/Contents/MacOS/PancakeNotch" >/dev/null 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT
sleep "$SETTLE"

echo "== Footprint by category (app)"
footprint --pid "$PID" 2>&1 | sed -n '1,40p'
for CHILD in $(pgrep -P "$PID" || true); do
    echo "== Footprint by category (helper $CHILD)"
    footprint --pid "$CHILD" 2>&1 | sed -n '1,25p'
done
echo "== Memory regions (app)"
vmmap --summary "$PID" 2>/dev/null | sed -n '/REGION TYPE/,/TOTAL/p' || true
echo "== Largest heap allocations by class (app)"
heap "$PID" 2>/dev/null | sed -n '/COUNT .*BYTES .*AVG/,$p' | head -45 || echo "(heap unavailable)"
