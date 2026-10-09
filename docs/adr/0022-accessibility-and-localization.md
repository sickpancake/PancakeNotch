# 0022 — Accessibility and localization

**Status:** Accepted (2026-10-09)

## Decision
- VoiceOver labels on every control; Reduce Motion → cross-fades instead of springs;
  respect Increase Contrast.
- English only in v1; all user-facing strings go through `String(localized:)` with `.lproj/Localizable.strings` resources (String Catalogs need Xcode tooling, which we avoid), so the community can translate later.
