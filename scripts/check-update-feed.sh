#!/usr/bin/env bash
# Checks the current update feed before a release builds on it. It must be signed with the update key,
# so a feed someone swapped in is never signed over and handed to people's Macs. The one exception is
# the last feed published before feeds were signed (0.2.0's), accepted only by its exact checksum.
# Usage: scripts/check-update-feed.sh <appcast.xml> <public-key>
set -euo pipefail

FEED="${1:?usage: scripts/check-update-feed.sh <appcast.xml> <public-key>}"
PUBLIC_KEY="${2:?missing the public update key (SUPublicEDKey)}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Both downloads it lists were checked against the update key on 2026-10-28.
LAST_UNSIGNED_FEED_SHA256="f02ed31f9591c431fba40c14f562ee194247355767a128250c5e53756f35ac94"

CHECKSUM="$(shasum -a 256 < "$FEED")"
if grep -q 'sparkle-signatures:' "$FEED"; then
  swift "$ROOT/scripts/verify-update-signature.swift" --feed "$FEED" "$PUBLIC_KEY"
elif [[ "${CHECKSUM%% *}" != "$LAST_UNSIGNED_FEED_SHA256" ]]; then
  echo "The current update feed isn't signed with the update key; refusing to build on it." >&2
  exit 1
fi
echo "The current update feed checks out."
