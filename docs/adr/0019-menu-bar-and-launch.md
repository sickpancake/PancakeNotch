# 0019 — Menu bar icon and launch at login

**Status:** Accepted (2026-10-09)

## Decision
- Menu bar icon (open companion, pause, quit), on by default, hideable.
- Launch at login via the system `SMAppService` API, offered during onboarding.
  This removes the need for the `LaunchAtLogin` package.
