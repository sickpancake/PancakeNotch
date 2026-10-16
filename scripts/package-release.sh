#!/usr/bin/env bash
# Builds, checks and packages one release into build/release/: PancakeNotch.zip, appcast.xml (the
# update feed with this release added) and notes.md (its release notes from CHANGELOG.md).
# The release workflow runs it with the real keys; CI runs it with throwaway keys to test it.
#
# Environment:
#   PANCAKENOTCH_VERSION      e.g. 0.1.0                       (required)
#   PANCAKENOTCH_BUILD        a number that grows every release (required)
#   CODESIGN_IDENTITY         the signing certificate (SHA-1 or name)        (required)
#   SPARKLE_PUBLIC_ED_KEY     the update key's public half                   (required)
#   SPARKLE_PRIVATE_KEY_FILE  a file holding the update key's private half   (required)
#   SPARKLE_BIN               folder with Sparkle's sign_update              (required)
#   DOWNLOAD_URL              where PancakeNotch.zip will be downloaded from (required)
#   EXISTING_APPCAST          the current feed, to keep older releases       (optional)
set -euo pipefail

: "${PANCAKENOTCH_VERSION:?}" "${PANCAKENOTCH_BUILD:?}" "${CODESIGN_IDENTITY:?}" "${SPARKLE_PUBLIC_ED_KEY:?}"
: "${SPARKLE_PRIVATE_KEY_FILE:?}" "${SPARKLE_BIN:?}" "${DOWNLOAD_URL:?}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/PancakeNotch.app"
OUT="$ROOT/build/release"
cd "$ROOT"

if ! [[ "$PANCAKENOTCH_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must look like 1.2.3, got '$PANCAKENOTCH_VERSION'." >&2
  exit 1
fi

export PANCAKENOTCH_VERSION PANCAKENOTCH_BUILD CODESIGN_IDENTITY SPARKLE_PUBLIC_ED_KEY
"$ROOT/scripts/build-app.sh" release

# The bundle is signed with the project certificate, carries the version and can update itself.
codesign --verify --strict --deep "$APP"
PLIST="$APP/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")" == "$PANCAKENOTCH_VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")" == "$PANCAKENOTCH_BUILD" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$PLIST")" == "$SPARKLE_PUBLIC_ED_KEY" ]]
echo "Designated requirement: $(codesign -d -r- "$APP" 2>&1 | sed -nE 's/^(# )?designated => //p')"

rm -rf "$OUT"
mkdir -p "$OUT"
ditto -c -k --norsrc --noextattr --noacl --keepParent "$APP" "$OUT/PancakeNotch.zip"

# Sign the download for Sparkle, then check the signature with the public key inside the app.
read -r SIGNATURE LENGTH < <("$SPARKLE_BIN/sign_update" --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" "$OUT/PancakeNotch.zip" \
  | sed -E 's/.*sparkle:edSignature="([^"]+)" length="([0-9]+)".*/\1 \2/')
swift "$ROOT/scripts/verify-update-signature.swift" "$OUT/PancakeNotch.zip" "$SIGNATURE" "$SPARKLE_PUBLIC_ED_KEY"

# Release notes: the CHANGELOG section for this version ("## 0.1.0 …" up to the next "## ").
awk -v version="$PANCAKENOTCH_VERSION" '
  /^## / { inside = ($2 == version); next }
  inside { print }
' "$ROOT/CHANGELOG.md" | sed '/./,$!d' > "$OUT/notes.md"
if [[ ! -s "$OUT/notes.md" ]]; then
  echo "CHANGELOG.md has no '## $PANCAKENOTCH_VERSION' section with notes." >&2
  exit 1
fi

python3 "$ROOT/scripts/appcast.py" \
  --out "$OUT/appcast.xml" ${EXISTING_APPCAST:+--existing "$EXISTING_APPCAST"} \
  --version "$PANCAKENOTCH_VERSION" --build "$PANCAKENOTCH_BUILD" \
  --url "$DOWNLOAD_URL" --length "$LENGTH" --signature "$SIGNATURE" --notes "$OUT/notes.md"

"$ROOT/scripts/check-release-privacy.sh" "$APP" "$OUT/appcast.xml" "$OUT/notes.md"
echo "Packaged PancakeNotch $PANCAKENOTCH_VERSION ($PANCAKENOTCH_BUILD) in $OUT"
