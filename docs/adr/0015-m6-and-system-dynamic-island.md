# 0015 — M6 hole-punch / system Dynamic Island

**Status:** Accepted (2026-10-09)

## Context
Rumors (Gurman, Feb 2026) say the M6 OLED MacBook Pro has a hole-punch camera and a
system Dynamic Island on macOS 27.2.

## Decision
- Geometry treats the cutout as whatever shape `NSScreen` reports, never assumes a notch shape.
- If a system Dynamic Island is active, don't compete: disable our Compact state on that Mac,
  keep Expanded / Menu / Shelf.
- Finalized once hardware ships. v1 guarantees notched Macs only.
