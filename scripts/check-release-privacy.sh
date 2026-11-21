#!/usr/bin/env bash
# Fails if a release would carry personal details or secrets: home-folder paths from a personal Mac (CI
# builds live under /Users/runner), email addresses, private keys or access tokens, or a signature
# from anything but the project's own certificate (which names only the project).
# Usage: scripts/check-release-privacy.sh <PancakeNotch.app> [more files…]
set -euo pipefail

APP="${1:?usage: scripts/check-release-privacy.sh <PancakeNotch.app> [more files…]}"
shift
problems=0
# PEM private keys, GitHub, Anthropic, OpenAI project, AWS and Slack tokens.
SECRET_PATTERN='-----BEGIN [A-Z ]*PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{40,}|sk-ant-[A-Za-z0-9_-]{20,}|sk-proj-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|xox[abposr]-[A-Za-z0-9-]{10,}'

# Every file in the bundle (binaries included) plus any extra files (the appcast, release notes).
while IFS= read -r -d '' file; do
  paths="$(strings -a "$file" 2>/dev/null | grep -oE '/Users/[A-Za-z0-9._-]+' | grep -vE '^/Users/(runner|Shared)$' | sort -u || true)"
  if [[ -n "$paths" ]]; then
    echo "Personal path in ${file#"$APP"/}: $paths" >&2
    problems=1
  fi
  # Private keys and the access tokens of the services the project touches.
  secrets="$(strings -a "$file" 2>/dev/null | grep -oE -e "$SECRET_PATTERN" | sort -u || true)"
  if [[ -n "$secrets" ]]; then
    echo "Possible secret in ${file#"$APP"/} (not shown)." >&2
    problems=1
  fi
  # Third-party licences name their authors; that's theirs to publish, not ours. The practice notches'
  # pretend accounts use the reserved example.com / example.org addresses. Domains match whole, so
  # someone@apple.com.example.net still counts; name@2x.png is an image, not an address.
  [[ "$(basename "$file")" == *LICENSE* ]] && continue
  emails="$(strings -a "$file" 2>/dev/null | grep -oE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' \
    | grep -viE '@(apple\.com|sparkle-project\.org|github\.com|users\.noreply\.github\.com|noreply\.github\.com|example\.(com|org))$' \
    | grep -viE '@[0-9]x\.[a-z]+$' | sort -u || true)"
  if [[ -n "$emails" ]]; then
    echo "Email address in ${file#"$APP"/}: $emails" >&2
    problems=1
  fi
done < <(find "$APP" "$@" -type f -print0)

# Signed with the project's certificate, whose only name is the project's (not ad hoc, not another one).
authorities="$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=//p')"
if [[ "$authorities" != "PancakeNotch" ]]; then
  echo "Unexpected signing certificate: '${authorities:-none (ad hoc)}'" >&2
  problems=1
fi

if [[ "$problems" -ne 0 ]]; then
  echo "Release privacy check failed." >&2
  exit 1
fi
echo "Release privacy check passed."
