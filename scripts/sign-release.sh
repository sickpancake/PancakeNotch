#!/usr/bin/env bash
# Signs one release: the only step that uses the signing keys (ADR-0005). It takes the app as built and
# tested elsewhere (an ad hoc signed PancakeNotch.app, zipped) and writes to <folder>:
#   PancakeNotch.zip  the app signed with the project certificate, for the GitHub Release
#   appcast.xml       the update feed with this release added, signed with the update key
#   notes.md          this version's release notes from CHANGELOG.md
# It runs no build tools, package installs or the app, so nothing else ever runs next to the keys.
# The release workflow runs it after the maintainer approves; CI runs it with throwaway keys.
#
# Environment:
#   PANCAKENOTCH_VERSION   e.g. 0.3.0                                     (required)
#   PANCAKENOTCH_BUILD     a number that grows every release               (required)
#   CODESIGN_IDENTITY      the signing certificate (SHA-1 or name)         (required)
#   SPARKLE_PUBLIC_ED_KEY  the update key's public half                    (required)
#   SPARKLE_PRIVATE_KEY    the update key's private half                   (required; never written to disk)
#   SPARKLE_BIN            folder with Sparkle's sign_update               (required)
#   DOWNLOAD_URL           where PancakeNotch.zip will be downloaded from  (required)
#   EXISTING_APPCAST       the current feed, to keep older releases        (optional)
# Usage: scripts/sign-release.sh <unsigned PancakeNotch.zip> <folder>
set -euo pipefail

UNSIGNED_ZIP="${1:?usage: scripts/sign-release.sh <unsigned PancakeNotch.zip> <folder>}"
OUT="${2:?usage: scripts/sign-release.sh <unsigned PancakeNotch.zip> <folder>}"
: "${PANCAKENOTCH_VERSION:?}" "${PANCAKENOTCH_BUILD:?}" "${CODESIGN_IDENTITY:?}" "${SPARKLE_PUBLIC_ED_KEY:?}"
: "${SPARKLE_PRIVATE_KEY:?}" "${SPARKLE_BIN:?}" "${DOWNLOAD_URL:?}"
# The private key stays in this shell: programs started from here don't inherit it, and it reaches
# sign_update only through a pipe (never a file or a command line).
UPDATE_KEY="$SPARKLE_PRIVATE_KEY"
unset SPARKLE_PRIVATE_KEY
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail() { echo "$1" >&2; exit 1; }
[[ "$PANCAKENOTCH_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Version must look like 1.2.3, got '$PANCAKENOTCH_VERSION'."
[[ "$PANCAKENOTCH_BUILD" =~ ^[0-9]+$ ]] || fail "Build must be a number, got '$PANCAKENOTCH_BUILD'."
[[ "$DOWNLOAD_URL" == https://* ]] || fail "The download URL must be https, got '$DOWNLOAD_URL'."
[[ ! -e "$OUT" || -z "$(ls -A "$OUT")" ]] || fail "$OUT isn't empty."

# The current feed must be one we published, before anything is signed on top of it.
if [[ -n "${EXISTING_APPCAST:-}" ]]; then
  "$ROOT/scripts/check-update-feed.sh" "$EXISTING_APPCAST" "$SPARKLE_PUBLIC_ED_KEY"
fi

# The zip comes from another job, so nothing in it may point or lead outside the app: a link to the
# scripts folder, say, could otherwise make unpacking overwrite what runs here, next to the keys.
python3 -I - "$UNSIGNED_ZIP" <<'PY'
import stat, sys, zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    for entry in archive.infolist():
        parts = entry.filename.rstrip("/").split("/")
        if parts[0] != "PancakeNotch.app" or ".." in parts or "" in parts:
            sys.exit(f"Unexpected path in the app zip: {entry.filename}")
        if stat.S_ISLNK(entry.external_attr >> 16):
            target = archive.read(entry).decode()
            if target.startswith("/") or ".." in target.split("/"):
                sys.exit(f"Link out of the app in the zip: {entry.filename} -> {target}")
PY
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ditto -x -k "$UNSIGNED_ZIP" "$WORK"
APP="$WORK/PancakeNotch.app"
[[ -d "$APP" ]] || fail "The zip has no PancakeNotch.app."

# Version, build and the update key. The settings that make installed copies refuse unsigned feeds and
# downloads come from Resources/Info.plist; check-release.sh checks they're there.
PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $PANCAKENOTCH_VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $PANCAKENOTCH_BUILD" "$PLIST"
/usr/libexec/PlistBuddy -c "Delete :SUPublicEDKey" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_ED_KEY" "$PLIST"

# The project certificate, so macOS sees every release as the same app (ADR-0005).
"$ROOT/scripts/sign-app.sh" "$APP" "$CODESIGN_IDENTITY"
codesign --verify --strict --deep "$APP"

mkdir -p "$OUT"
ditto -c -k --norsrc --noextattr --noacl --keepParent "$APP" "$OUT/PancakeNotch.zip"

# The download's update signature, checked with the public key inside the app.
SIGNED="$(printf '%s' "$UPDATE_KEY" | "$SPARKLE_BIN/sign_update" --ed-key-file - "$OUT/PancakeNotch.zip")"
SIGNATURE="$(sed -nE 's/.*sparkle:edSignature="([^"]+)".*/\1/p' <<<"$SIGNED")"
LENGTH="$(sed -nE 's/.* length="([0-9]+)".*/\1/p' <<<"$SIGNED")"
[[ -n "$SIGNATURE" && "$LENGTH" == "$(stat -f %z "$OUT/PancakeNotch.zip")" ]] || fail "sign_update didn't sign the download."
swift "$ROOT/scripts/verify-update-signature.swift" "$OUT/PancakeNotch.zip" "$SIGNATURE" "$SPARKLE_PUBLIC_ED_KEY"

# Release notes: the CHANGELOG section for this version ("## 0.1.0 …" up to the next "## ").
awk -v version="$PANCAKENOTCH_VERSION" '
  /^## / { inside = ($2 == version); next }
  inside { print }
' "$ROOT/CHANGELOG.md" | sed '/./,$!d' > "$OUT/notes.md"
[[ -s "$OUT/notes.md" ]] || fail "CHANGELOG.md has no '## $PANCAKENOTCH_VERSION' section with notes."

# The feed with this release added, signed as a whole: installed copies refuse it otherwise.
python3 -I "$ROOT/scripts/appcast.py" \
  --out "$OUT/appcast.xml" ${EXISTING_APPCAST:+--existing "$EXISTING_APPCAST"} \
  --version "$PANCAKENOTCH_VERSION" --build "$PANCAKENOTCH_BUILD" \
  --url "$DOWNLOAD_URL" --length "$LENGTH" --signature "$SIGNATURE" --notes "$OUT/notes.md"
printf '%s' "$UPDATE_KEY" | "$SPARKLE_BIN/sign_update" --ed-key-file - --disable-signing-warning "$OUT/appcast.xml" >/dev/null
swift "$ROOT/scripts/verify-update-signature.swift" --feed "$OUT/appcast.xml" "$SPARKLE_PUBLIC_ED_KEY"

echo "Signed PancakeNotch $PANCAKENOTCH_VERSION ($PANCAKENOTCH_BUILD) in $OUT"
