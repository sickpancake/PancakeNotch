# 0030 — Full-screen detection

**Status:** Accepted (2026-10-09)

## Context
ADR-0011 says the notch is hidden while a full-screen app is in front, unless hovered. macOS has no
public API that reports whether *another* app is full screen on a given display.

## Decision
- Use the private, read-only `CGSCopyManagedDisplaySpaces` call (as MacroVisionKit/boring.notch do):
  a display's current Space is full screen when its `type` is 4 or it has a `TileLayoutManager`.
- Query only on `NSWorkspace.activeSpaceDidChangeNotification` and screen-parameter changes — no polling.
- While full screen, the notch rests **closed** (pure black inside the hardware cutout, so invisible)
  and Compact is suppressed. Hover / click still open it.
- Fail safe: if the call stops working, report "not full screen" and the notch stays visible.

## Consequences
- Could break in a future macOS; covered by unit tests on the parsing and a manual check per release.
- Fine for GitHub distribution; would not pass Mac App Store review (not a goal, ADR-0005).
