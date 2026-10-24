#!/bin/bash
# Runs the tests with a time limit. If they take longer, prints what each thread of the test process
# is doing (to find a hang) and fails, instead of waiting for CI's six-hour cutoff.
# Usage: ./scripts/test-ci.sh [limit-minutes]
set -uo pipefail
LIMIT_MINUTES="${1:-15}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
./scripts/swift.sh test &
tests=$!
for ((second = 0; second < LIMIT_MINUTES * 60; second += 5)); do
  if ! kill -0 "$tests" 2>/dev/null; then
    wait "$tests"
    exit $?
  fi
  sleep 5
done
echo "::error::Tests still running after $LIMIT_MINUTES minutes. Thread stacks of the test process:"
for pid in $(pgrep -f "PancakeNotchPackageTests|swiftpm-testing-helper"); do
  echo "=== $(ps -o command= -p "$pid" | cut -c1-120)"
  sample "$pid" 2 2>/dev/null | sed -n '/^Call graph:/,/^Total number in stack/p' | head -400
done
pkill -f "PancakeNotchPackageTests|swiftpm-testing-helper|swift-test"
exit 1
