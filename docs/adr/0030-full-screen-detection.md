# 0030 — Full-screen behavior and detection

**Status:** Accepted (2026-10-09)

## Decision
- In full-screen apps the notch **works normally** (hover, click, Compact), since it's often needed
  while working full screen.
- Apps on a user-managed **hide list** (e.g. games) hide the notch completely while they're full
  screen — not even hover opens it. The list lives in Settings (companion app, M4); empty by default.
- Detection uses the private, read-only `CGSCopyManagedDisplaySpaces` call (as MacroVisionKit /
  boring.notch do): a display's current Space is full screen when its `type` is 4 or it has a
  `TileLayoutManager`. macOS has no public API for another app's full-screen state.
- Checked only on `NSWorkspace.activeSpaceDidChangeNotification`, `didActivateApplicationNotification`
  and screen-parameter changes — no polling — and only when the hide list isn't empty.
- Fail safe: if the call stops working it reports "not full screen", so the notch stays visible.

## Consequences
- Could break in a future macOS; parsing is unit-tested, behavior checked manually per release.
- Fine for GitHub distribution; would not pass Mac App Store review (not a goal, ADR-0005).
