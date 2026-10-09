#!/usr/bin/env bash
# Launches the app, waits for it to settle, and fails if its idle memory footprint exceeds the budget.
# Usage: scripts/check-memory.sh [path/to/PancakeNotch.app] [settle-seconds] [limit-MiB]
set -euo pipefail

APP="${1:-build/PancakeNotch.app}"
SETTLE="${2:-30}"
LIMIT_MIB="${3:-50}"   # ADR-0006: < 50 MB idle

PANCAKENOTCH_SIMULATE_NOTCH=1 "$APP/Contents/MacOS/PancakeNotch" &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT

sleep "$SETTLE"
kill -0 "$PID" 2>/dev/null || { echo "App exited early"; exit 1; }

BYTES="$(footprint --pid "$PID" --format bytes --noCategories | awk '/phys_footprint:/ { print $2; exit }')"
[[ -n "$BYTES" ]] || { echo "Could not read footprint"; footprint --pid "$PID" --noCategories; exit 1; }

MIB=$(( BYTES / 1024 / 1024 ))
echo "Idle footprint: ${MIB} MiB (limit ${LIMIT_MIB} MiB)"
(( MIB < LIMIT_MIB )) || { echo "Memory budget exceeded"; exit 1; }
