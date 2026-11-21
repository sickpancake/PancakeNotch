#!/bin/zsh
# Builds PancakeNotch (debug) and renders its UI off-screen, with no window and no permissions:
#   <out>/notch.png        every notch state on one tall sheet
#   <out>/notch-<n>.png    the same sheet cut into pieces small enough to look at
#   <out>/app/app-*.png    every app window page (only with --app)
# Usage: snapshot.sh <out-folder> [--app]
set -euo pipefail
setopt null_glob
out=${1:?usage: snapshot.sh <out-folder> [--app]}
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
mkdir -p "$out"
out=$(cd "$out" && pwd)
cd "$root"
./scripts/swift.sh build 2>&1 | grep -E "error:|Build complete" || { echo "build failed"; exit 1; }
PANCAKENOTCH_SNAPSHOT="$out/notch.png" .build/debug/PancakeNotch
height=$(sips -g pixelHeight "$out/notch.png" | awk '/pixelHeight/ {print $2}')
width=$(sips -g pixelWidth "$out/notch.png" | awk '/pixelWidth/ {print $2}')
piece=1800
rm -f "$out"/notch-*.png
n=0
for (( y = 0; y < height; y += piece )); do
  h=$(( height - y < piece ? height - y : piece ))
  sips -c "$h" "$width" --cropOffset "$y" 0 "$out/notch.png" --out "$out/notch-$n.png" >/dev/null
  n=$(( n + 1 ))
done
echo "notch: $out/notch.png ($n pieces: notch-0.png … notch-$(( n - 1 )).png)"
if [[ "${2:-}" == "--app" ]]; then
  PANCAKENOTCH_SNAPSHOT_SETTINGS="$out/app" .build/debug/PancakeNotch
  echo "app window: $(ls "$out/app" | wc -l | tr -d ' ') pages in $out/app"
fi
