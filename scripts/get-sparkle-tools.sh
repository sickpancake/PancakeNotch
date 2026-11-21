#!/usr/bin/env bash
# Downloads Sparkle's command-line tools (sign_update, …) for the same Sparkle version the app uses,
# checks the download against a pinned checksum, and unpacks them into <folder>/bin.
# Usage: scripts/get-sparkle-tools.sh <folder>
set -euo pipefail

OUT="${1:?usage: scripts/get-sparkle-tools.sh <folder>}"
VERSION="2.10.0" # keep in step with Package.swift
SHA256="c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"

mkdir -p "$OUT"
ARCHIVE="$OUT/Sparkle-$VERSION.tar.xz"
curl -fsSL -o "$ARCHIVE" "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz"
echo "$SHA256  $ARCHIVE" | shasum -a 256 -c - >/dev/null
tar -xf "$ARCHIVE" -C "$OUT" bin
echo "$OUT/bin"
