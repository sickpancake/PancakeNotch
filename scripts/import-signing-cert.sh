#!/usr/bin/env bash
# CI only: puts the signing certificate into a temporary keychain, trusts it for code signing, and
# prints its SHA-1 so codesign can use it (CODESIGN_IDENTITY). Never run this on your own Mac: it
# changes the keychain search list and the system's trust settings.
# Usage: scripts/import-signing-cert.sh <signing.p12> <p12-password>
set -euo pipefail

P12="${1:?usage: scripts/import-signing-cert.sh <signing.p12> <p12-password>}"
P12_PASSWORD="${2:?missing the .p12 password}"
if [[ "${CI:-}" != "true" ]]; then
  echo "This only runs in CI (it changes keychain and trust settings)." >&2
  exit 1
fi

KEYCHAIN="$RUNNER_TEMP/signing.keychain-db"
KEYCHAIN_PASSWORD="$(/usr/bin/openssl rand -base64 24)"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >&2
security set-keychain-settings -lut 21600 "$KEYCHAIN" >&2
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >&2
security import "$P12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign >&2
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
# shellcheck disable=SC2046
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')

# A self-signed certificate has to be trusted before codesign will use it.
CERT="$RUNNER_TEMP/signing-cert.pem"
security find-certificate -c "PancakeNotch" -p "$KEYCHAIN" > "$CERT"
sudo security add-trusted-cert -d -r trustRoot -p codeSign -k /Library/Keychains/System.keychain "$CERT" >&2

IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" | awk '/PancakeNotch/ { print $2; exit }')"
if [[ -z "$IDENTITY" ]]; then
  echo "The PancakeNotch signing identity didn't import." >&2
  security find-identity -p codesigning "$KEYCHAIN" >&2
  exit 1
fi
echo "$IDENTITY"
