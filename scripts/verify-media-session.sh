#!/usr/bin/env bash
# Native callback replays, source mutants, and the bounded media-session model.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${TLA2TOOLS:?Set TLA2TOOLS to the TLC 1.7.4 tla2tools.jar path}"
JAVA="${JAVA:-java}"
EXPECTED=936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88
ACTUAL="$(shasum -a 256 "$TLA2TOOLS" | awk '{print $1}')"
[[ "$ACTUAL" == "$EXPECTED" ]] || { echo 'Expected the pinned TLC 1.7.4 jar.' >&2; exit 1; }
"$ROOT/scripts/test-adapter-stream.sh"
python3 "$ROOT/verification/media-session/check_source_mutations.py"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/pancakenotch-media-model.XXXXXX")"
trap 'rm -rf "$OUT"' EXIT
cp "$ROOT/verification/media-session/"*.tla "$ROOT/verification/media-session/"*.cfg "$OUT/"
cd "$OUT"
if ! "$JAVA" -XX:+UseParallelGC -cp "$TLA2TOOLS" tlc2.TLC -workers 1 \
     -config MediaSession.cfg -metadir current-states MediaSession > current.log 2>&1; then
  cat current.log >&2; exit 1
fi
cat current.log
for config in NoSessionGuard NoRequestGuard; do
  if "$JAVA" -XX:+UseParallelGC -cp "$TLA2TOOLS" tlc2.TLC -workers 1 \
       -config "$config.cfg" -metadir "$config-states" MediaSession > "$config.log" 2>&1; then
    echo "Broken model unexpectedly passed: $config" >&2; exit 1
  fi
  if [[ "$config" == NoSessionGuard ]]; then
    rg -q 'Invariant NoRetired(Metadata|Fields) is violated' "$config.log" || { cat "$config.log" >&2; exit 1; }
  else
    rg -q 'Invariant NoSupersededReply is violated' "$config.log" || { cat "$config.log" >&2; exit 1; }
  fi
  echo "Caught model mutation: $config"
done
echo 'Media-session verification passed. Interpret every model result with /statechart.'
