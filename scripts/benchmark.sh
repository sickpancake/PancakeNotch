#!/usr/bin/env bash
# Measures one or more app builds side by side and prints a Markdown table of medians:
# launch time, CPU used while starting, idle memory and CPU, memory with the notch open and with a
# full Shelf, and the download size. Runs alternate between the builds so they share the machine's
# conditions. Shows the notch on screen, so it runs in CI (benchmark.yml), not on a working Mac.
# Usage: scripts/benchmark.sh <runs> <label>=<path/to/PancakeNotch.app> [<label>=<app> ...]
# Settle times (seconds) can be changed with BENCH_IDLE, BENCH_CPU_WINDOW, BENCH_OPEN, BENCH_SHELF.
set -euo pipefail

RUNS="${1:?usage: benchmark.sh <runs> <label>=<app> ...}"
shift
IDLE="${BENCH_IDLE:-30}"
CPU_WINDOW="${BENCH_CPU_WINDOW:-30}"
OPEN="${BENCH_OPEN:-15}"
SHELF="${BENCH_SHELF:-20}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

WORK="$(mktemp -d)"
PID=""
trap 'stop_app; rm -rf "$WORK"' EXIT

stop_app() {
    [[ -n "$PID" ]] || return 0
    kill "$PID" 2>/dev/null || true
    for _ in $(seq 50); do kill -0 "$PID" 2>/dev/null || break; sleep 0.1; done
    kill -9 "$PID" 2>/dev/null || true
    PID=""
}

# The app and its Now Playing helper (a child process) count together (AGENTS.md rule 1).
family() { echo "$1"; pgrep -P "$1" || true; }

footprint_kib() {   # <pid>
    local bytes
    bytes="$(footprint --pid "$1" --format bytes --noCategories 2>/dev/null | awk '/phys_footprint:/ { print $2; exit }' || true)"
    echo $(( ${bytes:-0} / 1024 ))
}

cpu_ms() {   # <pid>: user + system CPU time so far, "[[h:]m:]s.cc" from ps
    ps -o time= -p "$1" 2>/dev/null | awk -F: '{ s = 0; for (i = 1; i <= NF; i++) s = s * 60 + $i; printf "%d\n", s * 1000 }' || echo 0
}

sum() { local total=0 value; for value in "$@"; do total=$(( total + value )); done; echo "$total"; }

family_footprint() { local p values=(); for p in $(family "$1"); do values+=("$(footprint_kib "$p")"); done; sum "${values[@]}"; }
family_cpu() { local p values=(); for p in $(family "$1"); do values+=("$(cpu_ms "$p")"); done; sum "${values[@]}"; }

record() { echo "$3" >> "$WORK/$1.$2"; }   # <label> <metric> <value>

launch() {   # <app> [env...]: starts the app, sets PID and LAUNCH_MS
    local app="$1" result
    shift
    result="$(env PANCAKENOTCH_SIMULATE_NOTCH=1 PANCAKENOTCH_SKIP_ONBOARDING=1 "$@" \
        "$WORK/launch-probe" "$app/Contents/MacOS/PancakeNotch")" || { echo "Launch failed: $result" >&2; exit 1; }
    PID="${result%% *}"
    LAUNCH_MS="${result##* }"
}

swiftc -O -o "$WORK/launch-probe" "$ROOT/scripts/bench/LaunchProbe.swift"

# Twenty 6000×4000 PNGs (camera-photo size), as in check-shelf-memory.sh.
mkdir -p "$WORK/seed"
sips -s format png -z 4000 6000 "$ROOT/Resources/AppIcon.icns" --out "$WORK/seed/photo-01.png" >/dev/null
for i in $(seq -w 2 20); do cp "$WORK/seed/photo-01.png" "$WORK/seed/photo-$i.png"; done

LABELS=()
for pair in "$@"; do
    label="${pair%%=*}"
    app="${pair#*=}"
    LABELS+=("$label")
    [[ -x "$app/Contents/MacOS/PancakeNotch" ]] || { echo "No app at $app"; exit 1; }
    record "$label" bundle "$(du -sk "$app" | awk '{ print $1 }')"
    record "$label" binary "$(( $(stat -f %z "$app/Contents/MacOS/PancakeNotch") / 1024 ))"
    ditto -c -k --norsrc --noextattr --keepParent "$app" "$WORK/$label.zip"
    record "$label" zip "$(( $(stat -f %z "$WORK/$label.zip") / 1024 ))"
done

for run in $(seq "$RUNS"); do
    for pair in "$@"; do
        label="${pair%%=*}"
        app="${pair#*=}"
        echo "Run $run/$RUNS: $label" >&2

        # Launch, then idle.
        launch "$app"
        record "$label" launch "$LAUNCH_MS"
        sleep 5
        record "$label" startup_cpu "$(family_cpu "$PID")"
        sleep $(( IDLE - 5 ))
        record "$label" idle "$(family_footprint "$PID")"
        record "$label" idle_app "$(footprint_kib "$PID")"
        before="$(family_cpu "$PID")"
        sleep "$CPU_WINDOW"
        record "$label" idle_cpu "$(( $(family_cpu "$PID") - before ))"
        stop_app

        # Notch pinned open (the Now Playing placeholder, as CI plays no music).
        launch "$app" PANCAKENOTCH_DEBUG_STATE=expanded
        sleep "$OPEN"
        record "$label" open "$(family_footprint "$PID")"
        stop_app

        # A full Shelf, open, so every thumbnail loads.
        rm -rf "$WORK/shelf" && mkdir -p "$WORK/shelf"
        launch "$app" PANCAKENOTCH_DEBUG_STATE=expanded PANCAKENOTCH_SHELF_DIR="$WORK/shelf" \
            PANCAKENOTCH_SHELF_SEED="$WORK/seed"
        sleep "$SHELF"
        record "$label" shelf "$(family_footprint "$PID")"
        stop_app
    done
done

median() { sort -n "$1" | awk '{ v[NR] = $1 } END { print (NR % 2) ? v[(NR + 1) / 2] : int((v[NR / 2] + v[NR / 2 + 1]) / 2) }'; }

METRICS=(launch startup_cpu idle idle_app idle_cpu open shelf binary bundle zip)
NAMES=("Launch to notch on screen (ms)" "CPU used in the first 5 s (ms)" "Idle memory, app + helper (KiB)"
    "Idle memory, app only (KiB)" "Idle CPU over ${CPU_WINDOW} s (ms)" "Notch open (KiB)"
    "Shelf open, 20 large images (KiB)" "App executable (KiB)" "App bundle (KiB)" "Zipped download (KiB)")

header="| Measurement (median of $RUNS) |"
rule="|---|"
for label in "${LABELS[@]}"; do header+=" $label |"; rule+="---:|"; done
(( ${#LABELS[@]} == 2 )) && { header+=" Change |"; rule+="---:|"; }
echo "$header"
echo "$rule"
for i in "${!METRICS[@]}"; do
    row="| ${NAMES[$i]} |"
    values=()
    for label in "${LABELS[@]}"; do
        value="$(median "$WORK/$label.${METRICS[$i]}")"
        values+=("$value")
        row+=" $value |"
    done
    if (( ${#LABELS[@]} == 2 )); then
        row+=" $(awk -v a="${values[0]}" -v b="${values[1]}" 'BEGIN { if (a == 0) print "n/a"; else printf "%+.0f%%\n", (b - a) * 100 / a }') |"
    fi
    echo "$row"
done
