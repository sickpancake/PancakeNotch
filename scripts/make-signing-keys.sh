#!/usr/bin/env bash
# Makes the two keys a release needs, as files in <folder> (nothing goes into your Keychain):
#   - a self-signed code-signing certificate named "PancakeNotch" (no name or email in it), so macOS
#     recognises every release as the same app and keeps its permissions across updates (ADR-0005);
#   - Sparkle's update-signing key, so the app only installs updates that really come from you.
# Usage: scripts/make-signing-keys.sh <folder> [--throwaway]
#
# It prints what to store as GitHub secrets. Keep the folder somewhere safe (a password manager or an
# encrypted backup): if these keys are lost, people would have to reinstall by hand to get updates.
# --throwaway skips the instructions; CI uses it to test the release pipeline with keys nobody keeps.
set -euo pipefail

OUT="${1:?usage: scripts/make-signing-keys.sh <folder> [--throwaway]}"
THROWAWAY="${2:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# macOS's own OpenSSL (LibreSSL): its .p12 files import into the Keychain without extra flags.
OPENSSL=/usr/bin/openssl

if [[ -e "$OUT" && -n "$(ls -A "$OUT")" ]]; then
  echo "$OUT isn't empty; refusing to replace or mix keys. Pick a new folder." >&2
  exit 1
fi
umask 077 # everything made here is readable only by you
mkdir -p "$OUT"
chmod 700 "$OUT"

# The certificate: RSA 2048, valid 20 years, for code signing only. Its bare private key only ever
# exists in a private temporary folder that's removed however the script ends; the .p12 keeps it
# encrypted. The password reaches openssl through its environment, not the command line, which
# other programs on the Mac can read.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 7300 \
  -subj "/CN=PancakeNotch" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false" \
  -keyout "$WORK/signing-key.pem" -out "$OUT/signing-cert.pem" 2>/dev/null
P12_PASSWORD="$("$OPENSSL" rand -base64 24)"
P12_PASSWORD="$P12_PASSWORD" "$OPENSSL" pkcs12 -export -name "PancakeNotch" \
  -inkey "$WORK/signing-key.pem" -in "$OUT/signing-cert.pem" \
  -out "$OUT/signing.p12" -passout env:P12_PASSWORD
printf '%s' "$P12_PASSWORD" > "$OUT/signing-p12-password.txt"

# Sparkle's EdDSA key: the private key file is the base64 of a 32-byte Ed25519 seed (the format
# Sparkle's `generate_keys -x` exports); the public key goes into the app's Info.plist.
swift "$ROOT/scripts/make-update-key.swift" "$OUT/update-private-key.txt" > "$OUT/update-public-key.txt"
chmod 600 "$OUT"/*

if [[ "$THROWAWAY" == "--throwaway" ]]; then
  exit 0
fi

cat <<EOF

Keys made in $OUT. Add these as secrets of the "release" environment (Settings › Environments ›
release › Environment secrets), not as repository secrets, so only the approved signing step sees them:

  SIGNING_CERT_P12          base64 of signing.p12:  base64 -i "$OUT/signing.p12" | pbcopy
  SIGNING_CERT_PASSWORD     the contents of signing-p12-password.txt
  SPARKLE_PRIVATE_KEY       the contents of update-private-key.txt

and this as a repository variable (it's public; it goes into the app):

  SPARKLE_PUBLIC_ED_KEY     $(cat "$OUT/update-public-key.txt")

Then back the folder up somewhere safe and private. Never commit it.
EOF
