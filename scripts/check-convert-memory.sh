#!/usr/bin/env bash
# Peak-memory check for Convert (ADR-0006, ADR-0038): runs the conversion helper over generated files
# near the "Too big" limits. Fails if a conversion uses more than the helper's budget, or more than
# the estimate the format row used to offer it (the row only stays honest while estimates run high).
# Runs off screen. Usage: scripts/check-convert-memory.sh [path/to/pancakenotch-convert]
set -euo pipefail

HELPER="${1:-build/PancakeNotch.app/Contents/MacOS/pancakenotch-convert}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Making test files…"
xcrun swiftc -O "$ROOT/scripts/convert-fixtures.swift" -o "$WORK/fixtures"
"$WORK/fixtures" "$WORK/in"
IN="$WORK/in"
FAILED=0
CHECKED=0

# check <format> <quality> <file>…
check() {
    local format="$1" quality="$2"; shift 2
    local out; out="$(mktemp -d "$WORK/out.XXXX")"
    local request
    request="$(python3 -c 'import json, sys; print(json.dumps({"sources": sys.argv[4:], "format": sys.argv[1], "quality": sys.argv[2], "outputFolder": sys.argv[3], "pageName": "Page"}))' "$format" "$quality" "$out" "$@")"
    local label="$format/$quality $(cd "$IN" && for f in "$@"; do basename "$f"; done | paste -sd+ -)"
    local estimate budget
    read -r estimate budget < <("$HELPER" estimate "$request" | python3 -c 'import json, sys; e = json.load(sys.stdin); print(e.get("peak") or "-", e["budget"])')
    if [[ "$estimate" != "-" ]] && python3 -c "import sys; sys.exit(0 if $estimate > $budget else 1)"; then
        printf '  %-48s Too big (estimate %.0f MiB): not offered\n' "$label" "$estimate"
        return
    fi
    /usr/bin/time -l "$HELPER" convert "$request" > "$out.log" 2> "$out.time" || true
    local result; result="$(tail -1 "$out.log")"
    local peak; peak="$(awk '/peak memory footprint/ { printf "%.1f", $1 / 1048576 }' "$out.time")"
    CHECKED=$((CHECKED + 1))
    local status="ok"
    if ! python3 -c 'import json, sys; m = json.loads(sys.argv[1]); sys.exit(0 if m.get("outputs") and not m.get("errors") else 1)' "$result" 2>/dev/null; then
        status="FAILED to convert: $result"
    elif python3 -c "import sys; sys.exit(0 if $peak > $budget else 1)"; then
        status="OVER BUDGET"
    elif [[ "$estimate" != "-" ]] && python3 -c "import sys; sys.exit(0 if $peak > $estimate + 1 else 1)"; then
        status="OVER ESTIMATE"
    fi
    printf '  %-48s %6.1f MiB (estimate %s) %s\n' "$label" "$peak" "$estimate" "$status"
    [[ "$status" == "ok" ]] || FAILED=$((FAILED + 1))
}

echo "Pictures"
for q in best balanced smaller; do
    for mp in 3 6 12 24 48; do
        check jpeg "$q" "$IN/photo$mp.heic"
        check png "$q" "$IN/photo$mp.jpg"
        check png "$q" "$IN/photo$mp.heic"
        check heic "$q" "$IN/photo$mp.jpg"
        check pdf "$q" "$IN/photo$mp.jpg"
        check pdf "$q" "$IN/photo$mp.heic"
    done
    check jpeg "$q" "$IN/photo6.png"; check heic "$q" "$IN/photo6.png"; check pdf "$q" "$IN/photo6.png"
    check jpeg "$q" "$IN/photo6.tiff"; check png "$q" "$IN/photo6.tiff"
    check jpeg "$q" "$IN/clear2.png"; check jpeg "$q" "$IN/clear4.png"; check pdf "$q" "$IN/clear4.png"
    check png "$q" "$IN/print4.jpg"; check pdf "$q" "$IN/print4.jpg"
    check tiff "$q" "$IN/photo3.heic"; check tiff "$q" "$IN/photo6.jpg"
done

echo "Combine"
for q in best balanced smaller; do
    check combinedPDF "$q" "$IN/photo24.jpg" "$IN/photo12.jpg" "$IN/turned12.jpg"
    check combinedPDF "$q" "$IN/photo48.heic" "$IN/photo24.jpg"
    check combinedPDF "$q" "$IN/photo12.heic" "$IN/photo3.png"
    check combinedPDF "$q" "$IN/text200.pdf" "$IN/photo6.pdf" "$IN/photo3.jpg"
    check combinedPDF "$q" "$IN/scan.pdf" "$IN/text200.pdf"
done

echo "PDF pages and text"
for q in best balanced smaller; do
    for f in text200.pdf photo6.pdf scan.pdf; do
        check pagePNG "$q" "$IN/$f"
        check pageJPEG "$q" "$IN/$f"
    done
done
check text balanced "$IN/text200.pdf"

echo "Audio and video"
for f in stereo10min.wav speech.aiff; do
    check m4a balanced "$IN/$f"; check appleLossless balanced "$IN/$f"
done
check aiff balanced "$IN/stereo10min.wav"; check wav balanced "$IN/speech.aiff"
check mp4 balanced "$IN/clip1080sound.mov"
check audioOnly balanced "$IN/clip1080sound.mov"
for q in best balanced smaller; do check gif "$q" "$IN/clip1080.mov"; done

echo "Documents"
check pdf balanced "$IN/long.txt"; check rtf balanced "$IN/long.txt"
check pdf balanced "$IN/long.rtf"; check text balanced "$IN/long.docx"

echo "$CHECKED conversions measured, $FAILED failed."
(( FAILED == 0 )) || { echo "Convert memory check failed"; exit 1; }
