#!/bin/bash
set -euo pipefail
base=2bd2e2ed1105789c504ba58db19bc7c1db9eead5
here=verification/optimization-probes
work=$(mktemp -d)
trap 'git worktree remove "$work/base" 2>/dev/null || true; rm -rf "$work"' EXIT
git worktree add --detach "$work/base" "$base"
swiftc -O -swift-version 6 -parse-as-library "$work/base"/Sources/Stats/*.swift "$here/batch.swift" -lsqlite3 -o "$work/base-batch"
swiftc -O -swift-version 6 -parse-as-library Sources/Stats/*.swift "$here/batch.swift" -lsqlite3 -o "$work/candidate-batch"
python3 - "$work" <<'PY'
import statistics, subprocess, sys
from pathlib import Path
work = Path(sys.argv[1])
for width in (16, 256):
    runs = {"base": [], "candidate": []}
    for i in range(9):
        order = tuple(runs)
        for mode in order if i % 2 == 0 else reversed(order):
            runs[mode].append(float(subprocess.check_output([work / f"{mode}-batch", str(width)])))
    base, candidate = [statistics.median(data) for data in runs.values()]
    print(f"SQLite, 80 batches of {width}: {base:.2f} -> {candidate:.2f} ms")
PY
{
    echo 'import AppKit'
    echo 'import Darwin'
    echo '@MainActor enum ShelfThumbnails {'
    echo '    static let pointSize = CGSize(width: 56, height: 56)'
    sed -n '/    static func smallIcon(forFile/,/^    }/p' "$work/base/Sources/ModuleShelf/ShelfThumbnails.swift"
    echo '}'
    sed -n '/^\/\/\/ One file icon per mounted tile/,$p' Sources/ModuleShelf/ShelfWidget.swift
} > "$work/ShelfIconCode.swift"
swiftc -O -swift-version 6 -parse-as-library Sources/ModuleShelf/ShelfItem.swift "$work/ShelfIconCode.swift" "$here/shelf.swift" -o "$work/shelf"
"$work/shelf"
