#!/usr/bin/env bash
# CI only: shows the notch. Imports 30,000 made-up messages across three accounts, then checks idle
# and open-view memory, including the Now Playing helper. Never connects a real AI tool.
set -euo pipefail
APP="${1:-build/PancakeNotch.app}"
# A build without the testing switches would use the real statistics file and agents socket.
grep -aq PANCAKENOTCH_STATS_FILE "$APP/Contents/MacOS/PancakeNotch" \
  || { echo "$APP has no testing switches: build it with PANCAKENOTCH_INTERNAL_TESTING=1 scripts/build-app.sh" >&2; exit 1; }
WORK="$(mktemp -d)"
trap 'kill "${PID:-}" 2>/dev/null || true; rm -rf "$WORK"' EXIT

python3 - "$WORK" <<'PY'
import datetime, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
now = datetime.datetime.now(datetime.timezone.utc)
stamp = now.isoformat().replace('+00:00', 'Z')
for name in ['.claude', '.claude-work']:
    folder = root / name
    logs = folder / 'projects' / 'example'
    logs.mkdir(parents=True)
    (folder / '.claude.json').write_text(json.dumps({'oauthAccount': {'emailAddress': name[1:] + '@example.com', 'organizationType': 'claude_pro'}}))
    with (logs / 'session.jsonl').open('w') as f:
        for i in range(10000):
            message = {'type': 'assistant', 'timestamp': stamp, 'message': {'id': f'm{i}', 'model': 'claude-sonnet-4-6', 'usage': {'input_tokens': 100, 'output_tokens': 25}, 'content': 'x' * 1024}}
            f.write(json.dumps(message, separators=(',', ':')) + '\n')
folder = root / '.codex'
logs = folder / 'sessions' / now.strftime('%Y/%m/%d')
logs.mkdir(parents=True)
(folder / 'auth.json').write_text('{"auth_mode":"apikey"}')
with (logs / 'rollout-fixture.jsonl').open('w') as f:
    def event(kind, payload):
        f.write(json.dumps({'timestamp': stamp, 'type': kind, 'payload': payload}, separators=(',', ':')) + '\n')
    event('session_meta', {'id': 'fixture', 'source': 'cli'})
    event('turn_context', {'model': 'gpt-5.4'})
    event('event_msg', {'type': 'task_started'})
    for i in range(1, 10001):
        event('event_msg', {'type': 'token_count', 'info': {'total_token_usage': {'input_tokens': i * 100, 'output_tokens': i * 25, 'total_tokens': i * 125}}})
    event('event_msg', {'type': 'task_complete'})
PY

read_bytes() {
    local total child value
    total="$(footprint --pid "$PID" --format bytes --noCategories | awk '/phys_footprint:/ { print $2; exit }')"
    [[ -n "$total" ]] || { echo "Could not read footprint" >&2; return 1; }
    for child in $(pgrep -P "$PID" || true); do
        value="$(footprint --pid "$child" --format bytes --noCategories 2>/dev/null | awk '/phys_footprint:/ { print $2; exit }' || true)"
        total=$((total + ${value:-0}))
    done
    echo "$total"
}

for state in closed expanded; do
    PANCAKENOTCH_SIMULATE_NOTCH=1 PANCAKENOTCH_SKIP_ONBOARDING=1 \
    PANCAKENOTCH_DEBUG_STATE="$state" PANCAKENOTCH_STATS_FILE="$WORK/statistics.sqlite" \
    PANCAKENOTCH_AGENTS_SOCKET="$WORK/agents.sock" \
    "$APP/Contents/MacOS/PancakeNotch" -agents.enabled YES -aiUsage.enabled YES \
        -aiUsage.addedFolders "(\"$WORK/.claude\",\"$WORK/.claude-work\",\"$WORK/.codex\")" \
        -modules.order '("aiUsage","agents","nowPlaying","shelf")' &
    PID=$!
    peak=0
    for sample in $(seq 1 30); do
        sleep 1
        kill -0 "$PID" 2>/dev/null || { echo "App exited early"; exit 1; }
        bytes="$(read_bytes)"
        (( bytes > peak )) && peak=$bytes
        (( bytes < 100 * 1024 * 1024 )) || { echo "AI $state exceeded 100 MiB: $bytes bytes"; exit 1; }
    done
    echo "AI $state: sampled peak $((peak / 1024 / 1024)) MiB; settled $((bytes / 1024 / 1024)) MiB (app + helper)"
    if [[ "$state" == closed ]]; then
        (( bytes < 50 * 1024 * 1024 )) || { echo "AI idle budget exceeded"; exit 1; }
    fi
    kill "$PID"
    wait "$PID" || true
    PID=""
    # Prove that the modules were enabled and the entire import finished, rather than measuring an empty view.
    python3 - "$WORK/statistics.sqlite" <<'PY'
import sqlite3, sys
with sqlite3.connect(sys.argv[1]) as db:
    rows = db.execute('SELECT COUNT(*), COUNT(DISTINCT account) FROM ai_usage').fetchone()
    assert rows == (30000, 3), f'Incomplete import: {rows}'
PY
done
