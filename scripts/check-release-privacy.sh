#!/usr/bin/env bash
# Fails if a release would carry personal details: home-folder paths from a personal Mac (CI builds
# live under /Users/runner), email addresses, or a signing certificate with more than the project's
# name in it. Usage: scripts/check-release-privacy.sh <PancakeNotch.app> [more files…]
set -euo pipefail

APP="${1:?usage: scripts/check-release-privacy.sh <PancakeNotch.app> [more files…]}"
shift
problems=0

# Every file in the bundle (binaries included) plus any extra files (the appcast, release notes).
while IFS= read -r -d '' file; do
  paths="$(strings -a "$file" 2>/dev/null | grep -oE '/Users/[A-Za-z0-9._-]+' | grep -vE '^/Users/(runner|Shared)$' | sort -u || true)"
  if [[ -n "$paths" ]]; then
    echo "Personal path in ${file#"$APP"/}: $paths" >&2
    problems=1
  fi
  # Third-party licences name their authors; that's theirs to publish, not ours.
  [[ "$(basename "$file")" == *LICENSE* ]] && continue
  emails="$(strings -a "$file" 2>/dev/null | grep -oE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' \
    | grep -viE '@(apple\.com|sparkle-project\.org|github\.com|noreply\.github\.com|2x|3x)' | sort -u || true)"
  if [[ -n "$emails" ]]; then
    echo "Email address in ${file#"$APP"/}: $emails" >&2
    problems=1
  fi
done < <(find "$APP" "$@" -type f -print0)

# The signature's certificate names only the project.
authority="$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
if [[ -n "$authority" && "$authority" != "PancakeNotch" ]]; then
  echo "Unexpected signing certificate name: $authority" >&2
  problems=1
fi

if [[ "$problems" -ne 0 ]]; then
  echo "Release privacy check failed." >&2
  exit 1
fi
echo "Release privacy check passed."
