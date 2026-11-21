#!/usr/bin/env bash
# Builds the vendored mediaremote-adapter (ADR-0012) into MediaRemoteAdapter.framework with clang,
# like its CMakeLists.txt does but without CMake (Command Line Tools only), arm64 only (ADR-0021).
# Usage: scripts/build-adapter.sh <output-folder>   → <output-folder>/MediaRemoteAdapter.framework
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Vendor/mediaremote-adapter"
OUT="${1:?output folder}"
NAME=MediaRemoteAdapter
FRAMEWORK="$OUT/$NAME.framework"
VERSION_DIR="$FRAMEWORK/Versions/A"

rm -rf "$FRAMEWORK"
mkdir -p "$VERSION_DIR/Resources"

SOURCES=()
for file in "$SRC"/src/adapter/*.m "$SRC"/src/private/*.m "$SRC"/src/utility/*.m; do
    SOURCES+=("$file")
done

# The macOS 26 SDK if the Command Line Tools ship one next to 27 (see swift.sh); otherwise the default.
SDK_FLAGS=()
CLT=/Library/Developer/CommandLineTools
if [[ -z "${SDKROOT:-}" && "$(xcode-select -p 2>/dev/null)" == "$CLT" ]]; then
    SDK="$(ls -d "$CLT"/SDKs/MacOSX26.*.sdk 2>/dev/null | sort -V | tail -1 || true)"
    [[ -n "$SDK" ]] && SDK_FLAGS=(-isysroot "$SDK")
fi

# `${A[@]+"${A[@]}"}`: macOS's bash 3.2 calls an empty array "unbound" under `set -u`.
clang -arch arm64 -mmacosx-version-min=15.0 ${SDK_FLAGS[@]+"${SDK_FLAGS[@]}"} \
    -fobjc-arc -fvisibility=default -O2 -w \
    -dynamiclib -install_name "@rpath/$NAME.framework/Versions/A/$NAME" \
    -I "$SRC/include" -I "$SRC/src" \
    -framework Foundation -framework AppKit -framework UniformTypeIdentifiers -framework ImageIO \
    "${SOURCES[@]}" -o "$VERSION_DIR/$NAME"

cat > "$VERSION_DIR/Resources/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>$NAME</string>
	<key>CFBundleIdentifier</key>
	<string>com.vandenbe.$NAME</string>
	<key>CFBundleName</key>
	<string>$NAME</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>0.7.7</string>
	<key>CFBundleVersion</key>
	<string>0.7.7</string>
</dict>
</plist>
PLIST

ln -s A "$FRAMEWORK/Versions/Current"
ln -s "Versions/Current/$NAME" "$FRAMEWORK/$NAME"
ln -s Versions/Current/Resources "$FRAMEWORK/Resources"
codesign --force --sign - --timestamp=none "$FRAMEWORK"
echo "Built $FRAMEWORK"
