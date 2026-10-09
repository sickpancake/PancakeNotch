# 0003 — Minimal dependencies

**Status:** Accepted (2026-10-09)

## Decision
Apple frameworks first. Allowed third-party:
- Sparkle — updates
- sindresorhus/KeyboardShortcuts — global open/close shortcut (ADR-0028)
- ~~LaunchAtLogin~~ — not needed; use `SMAppService` (ADR-0019)
- ungive/mediaremote-adapter (BSD-3) — Now Playing (ADR-0012)

Every new dependency must justify memory cost, maintenance health, and GPL compatibility.
