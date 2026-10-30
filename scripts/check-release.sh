#!/usr/bin/env bash
# Checks a signed release with public information only (no keys), the way people's Macs will see it:
#   - the app in PancakeNotch.zip is signed with the project certificate and carries this version, the
#     update key, and the settings that make it refuse unsigned feeds and downloads;
#   - every part runs with the hardened runtime, only the app has entitlements (exactly the expected
#     ones), and no testing switch is built in;
#   - the feed is signed with the update key, and its newest entry is this download, with the right
#     size and a valid signature;
#   - nothing personal ships (check-release-privacy.sh).
# The app is unpacked into <unpack-folder> (new or empty) for the memory check that follows.
#
# Environment: PANCAKENOTCH_VERSION, PANCAKENOTCH_BUILD, SPARKLE_PUBLIC_ED_KEY, DOWNLOAD_URL (required);
#   SIGNING_CERT_LEAF, the release certificate's SHA-1 (releases set it; the dry run's throwaway one differs)
# Usage: scripts/check-release.sh <release-folder> <unpack-folder>
set -euo pipefail

RELEASE="${1:?usage: scripts/check-release.sh <release-folder> <unpack-folder>}"
UNPACK="${2:?usage: scripts/check-release.sh <release-folder> <unpack-folder>}"
: "${PANCAKENOTCH_VERSION:?}" "${PANCAKENOTCH_BUILD:?}" "${SPARKLE_PUBLIC_ED_KEY:?}" "${DOWNLOAD_URL:?}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ZIP="$RELEASE/PancakeNotch.zip"
FEED="$RELEASE/appcast.xml"
NOTES="$RELEASE/notes.md"

fail() { echo "$1" >&2; exit 1; }
for file in "$ZIP" "$FEED" "$NOTES"; do
  [[ -s "$file" ]] || fail "Missing $file."
done
[[ ! -e "$UNPACK" || -z "$(ls -A "$UNPACK")" ]] || fail "$UNPACK isn't empty."
mkdir -p "$UNPACK"
ditto -x -k "$ZIP" "$UNPACK"
APP="$UNPACK/PancakeNotch.app"

# The app: signed with the project certificate (not ad hoc), and set up to update safely.
codesign --verify --strict --deep "$APP"
authority="$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
[[ "$authority" == "PancakeNotch" ]] || fail "Signed by '${authority:-nobody (ad hoc)}', not the PancakeNotch certificate."
requirement="$(codesign -d -r- "$APP" 2>&1 | sed -nE 's/^(# )?designated => //p')"
echo "Designated requirement: $requirement"
# Releases pin the certificate itself: one with the same name but another key would make every
# installed copy refuse the update (and lose its permissions).
if [[ -n "${SIGNING_CERT_LEAF:-}" ]]; then
  [[ "$requirement" == "identifier \"io.github.sickpancake.PancakeNotch\" and certificate leaf = H\"$SIGNING_CERT_LEAF\"" ]] \
    || fail "Not signed with the release certificate ($SIGNING_CERT_LEAF)."
fi
# Hardened runtime everywhere, so no other program can slip code in and use PancakeNotch's permissions.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for part in "$APP" "$APP/Contents/MacOS/pancakenotch-hook" "$APP/Contents/MacOS/pancakenotch-convert" \
    "$APP/Contents/Frameworks/MediaRemoteAdapter.framework" "$APP/Contents/Frameworks/Sparkle.framework" \
    "$SPARKLE/Autoupdate" "$SPARKLE/Updater.app"; do
  flags="$(codesign -dvv "$part" 2>&1 | sed -nE 's/.*flags=0x[0-9a-f]+\(([^)]*)\).*/\1/p')"
  [[ ",$flags," == *",runtime,"* ]] || fail "${part#"$UNPACK/"} isn't signed with the hardened runtime (flags: ${flags:-none})."
  entitlements="$(codesign -d --entitlements - --xml "$part" 2>/dev/null | python3 -I -c '
import plistlib, sys
data = sys.stdin.buffer.read()
print(" ".join(sorted(plistlib.loads(data))) if data.strip() else "")')"
  if [[ "$part" == "$APP" ]]; then
    want="com.apple.security.automation.apple-events com.apple.security.cs.disable-library-validation com.apple.security.device.audio-input"
    [[ "$entitlements" == "$want" ]] || fail "The app's entitlements are '$entitlements', expected '$want'."
  else
    [[ -z "$entitlements" ]] || fail "${part#"$UNPACK/"} has entitlements ($entitlements); only the app may."
  fi
done
# Switches that point the app at other folders, files or code exist only in testing builds (Package.swift).
for binary in "$APP/Contents/MacOS/PancakeNotch" "$APP/Contents/MacOS/pancakenotch-hook"; do
  if switches="$(grep -aoE 'PANCAKENOTCH_(ADAPTER_DIR|AGENTS_SOCKET|SHELF_DIR|SHELF_SEED|STATS_FILE|SNAPSHOT)' "$binary" | sort -u | tr '\n' ' ')" \
      && [[ -n "$switches" ]]; then
    fail "${binary##*/} has testing switches built in: $switches"
  fi
done

expect() {
  local got
  got="$(/usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist" 2>/dev/null || true)"
  [[ "$got" == "$2" ]] || fail "Info.plist $1 is '$got', expected '$2'."
}
expect CFBundleShortVersionString "$PANCAKENOTCH_VERSION"
expect CFBundleVersion "$PANCAKENOTCH_BUILD"
expect SUPublicEDKey "$SPARKLE_PUBLIC_ED_KEY"
expect SURequireSignedFeed true
expect SUVerifyUpdateBeforeExtraction true
expect SUSignedFeedFailureExpirationInterval 0

# The feed: signed, and its newest entry is this download.
swift "$ROOT/scripts/verify-update-signature.swift" --feed "$FEED" "$SPARKLE_PUBLIC_ED_KEY"
entry="$(python3 -I - "$FEED" <<'PY'
import sys, xml.etree.ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
items = ET.parse(sys.argv[1]).getroot().findall("channel/item")
newest = max(items, key=lambda item: int(item.findtext(f"{{{SPARKLE}}}version", "0")))
enclosure = newest.find("enclosure")
print(newest.findtext(f"{{{SPARKLE}}}version"), newest.findtext(f"{{{SPARKLE}}}shortVersionString"),
      enclosure.get("url"), enclosure.get("length"), enclosure.get(f"{{{SPARKLE}}}edSignature"))
PY
)"
read -r build version url length signature <<<"$entry"
[[ "$build" == "$PANCAKENOTCH_BUILD" && "$version" == "$PANCAKENOTCH_VERSION" ]] \
  || fail "The feed's newest entry is $version ($build), not $PANCAKENOTCH_VERSION ($PANCAKENOTCH_BUILD)."
[[ "$url" == "$DOWNLOAD_URL" ]] || fail "The feed points at $url, not $DOWNLOAD_URL."
[[ "$length" == "$(stat -f %z "$ZIP")" ]] || fail "The feed's download size doesn't match PancakeNotch.zip."
swift "$ROOT/scripts/verify-update-signature.swift" "$ZIP" "$signature" "$SPARKLE_PUBLIC_ED_KEY"

"$ROOT/scripts/check-release-privacy.sh" "$APP" "$FEED" "$NOTES"
echo "Release $PANCAKENOTCH_VERSION ($PANCAKENOTCH_BUILD) checks out."
