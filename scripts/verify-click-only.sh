#!/usr/bin/env bash
# Check actual Swift tasks and the finite TLA+ model. All model output stays outside the repo.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${TLA2TOOLS:?Set TLA2TOOLS to the TLC 1.7.4 tla2tools.jar path}"
JAVA="${JAVA:-java}"
EXPECTED=936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88
ACTUAL="$(shasum -a 256 "$TLA2TOOLS" | awk '{print $1}')"
[[ "$ACTUAL" == "$EXPECTED" ]] || { echo 'Expected the pinned TLC 1.7.4 jar.' >&2; exit 1; }
./scripts/swift.sh test --filter 'NotchClickOnlyTests|PreferencesTests'
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pancakenotch-click-only.XXXXXX")"
cp verification/click-only/ClickOnly.tla verification/click-only/ClickOnly.cfg "$CHECK_DIR/"
echo "TLC scratch folder: $CHECK_DIR"
cd "$CHECK_DIR"
"$JAVA" -XX:+UseParallelGC -cp "$TLA2TOOLS" tlc2.TLC -workers 1 \
    -config ClickOnly.cfg -metadir states ClickOnly
