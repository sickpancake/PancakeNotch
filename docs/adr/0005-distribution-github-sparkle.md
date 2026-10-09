# 0005 — Distribution: GitHub Releases + Sparkle

**Status:** Accepted (2026-10-09)

## Decision
- Ship via public GitHub Releases. No Mac App Store, no Homebrew (main cask repo is believed to
  reject non-notarized apps — unverified).
- No Apple Developer account → builds are **not notarized**.
- Sign with a **self-signed certificate** (stored as a GitHub Actions secret) so the code identity
  is stable across updates and macOS permissions (TCC) are not reset each release.
- **Sparkle** auto-updates using its own EdDSA key; `appcast.xml` hosted on GitHub Pages.
- Fully automated: pushing a version tag → GitHub Actions builds, signs, zips, signs the update,
  regenerates the appcast, publishes the Release.

## Consequences
- First install requires Gatekeeper override (System Settings → Privacy & Security → Open Anyway).
  README documents it with screenshots.
- Subsequent Sparkle updates install without the Gatekeeper prompt.
