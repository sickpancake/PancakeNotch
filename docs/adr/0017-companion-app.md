# 0017 — Companion app

**Status:** Accepted (2026-10-09)

## Decision
- A window **inside the same process**, opened on demand (menu bar icon, gear in the notch Menu,
  or relaunching the app). Not a separate app.
- App is normally an accessory (no Dock icon); the Dock icon appears only while the window is open.
- The window's view hierarchy is torn down on close. Counts toward the 100 MB peak, not the 50 MB idle.
- Contents: settings, module management (favorite / reorder / hide), statistics (ADR-0018), help.
