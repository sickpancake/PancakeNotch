# 0009 — v1 scope

**Status:** Accepted (2026-10-09), amended same day (HUD removed)

## Decision
v1 modules: **Now Playing** and **Shelf**, presented through the module Menu (ADR-0010),
plus the **Companion app** (ADR-0017).

## Removed
**HUD** (volume / brightness / keyboard-backlight pop-up replacement) is dropped from v1 entirely.
Revisit only if users ask for it. This also removes the need for the Accessibility permission
and the private DisplayServices API in v1.

## Later (wanted, not v1)
Battery/charging, Calendar, Timer, device status (AirPods/Bluetooth/Focus), privacy indicators,
download progress, clipboard, mirror, notifications, plugins, fake notch, HUD.
