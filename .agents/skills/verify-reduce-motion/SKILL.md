---
name: verify-reduce-motion
description: Verify PancakeNotch's Reduce motion (the Mac's switch or its own Settings switch) when changing MotionSettings, NotchViewModel's Home scrolling or motionChanged, the notch's animation curves, SoundBarsMode, the General › Motion card, or any window root (NSHostingView, ImageRenderer, popover). Checks Home pages never stick halfway or slide while reduced, still sound bars, and a switch that never swallows a click.
---

# Verify Reduce motion

Promise: PancakeNotch reduces motion whenever the Mac's Reduce motion or its own switch (Settings › General ›
Motion) is on, everywhere, and switching either one never leaves Home caught between two pages.
Harm: motion-sensitive people get springs, slides and dancing bars anyway, or a Home page freezes halfway and
its widgets stop responding to clicks.

## Run

Use the project's `scripts/swift.sh`, not plain Swift. With TLC 1.7.4's jar in `TLA2TOOLS` and a Java binary
in `JAVA`, run from the repo root:

```sh
./scripts/verify-reduce-motion.sh
```

It checks the jar's SHA-256, runs `MotionSettingsTests` and `SoundBarsTests`, copies the model to a fresh
temporary folder and runs TLC with one worker. Nothing opens on screen. TLC 1.7.4 comes from the official
tlaplus/tlaplus GitHub v1.7.4 release (SHA-256
`936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88`). Validated with Eclipse Temurin
21.0.13+9 on macOS aarch64. These are development tools, never app dependencies.

Read every TLA+ result with `/statechart`: copy `verification/reduce-motion/ReduceMotion.tla`,
`ReduceMotion.cfg` and `view.mjs` into a scratch folder outside the repo and follow that installed skill to
check and draw it into a new output folder. Don't copy commands from an older statechart installation. The
passing model reaches 88 states and 536 steps with all six rules holding; its chart has two regions (Motion:
Full motion / Reduced by the Mac, PancakeNotch or both switches; Home: on a page / fingers scrolling /
settling) and no "Home stuck halfway" state.

## Coverage and correspondence

Each model action is one synchronous MainActor step:

- `Sources/NotchCore/MotionSettings.swift`: `reduceMotionInApp` didSet + `switchClicked(toReduce:)` →
  `YouClickSwitch`; `macSettingChanged` (on `accessibilityDisplayOptionsDidChangeNotification`) →
  `MacTellsApp`; `announceIfChanged` posts `didChangeNotification` only when `reducesMotion` changes;
  `followsMotionSettings()` sets `_accessibilityReduceMotion` for every view below a root.
- `Sources/NotchCore/NotchViewModel.swift`: `motionChanged()` (via a `queue: nil` observer, same step) →
  `HomeAfterChange`; `scrollHome` + `handleHomePreciseScroll` (.began/.changed/.ended) → `FingersDown`,
  `FingersTurnPageReduced`, `FingersLift`; `showHomePage` → `PageKey` / the reduced branch; `settleHome`'s
  completion (generation-checked) → `SettleEnds`; the `…Animation(reducesMotion:)` curves.
- `Sources/NowPlayingCore/SoundBars.swift` `SoundBarsMode.resolve` and
  `Sources/ModuleNowPlaying/NowPlayingEars.swift` (`NowPlayingBarsEar`, `SoundBarsNSView.refresh/apply`) →
  `ViewsRedraw`, `MusicStartsOrStops`, `BarsFor`.
- `Sources/PancakeNotch/AppWindow/SettingsPages.swift` `MotionCard`: switch shows `reducesMotion`, disabled and
  explained while `macReducesMotion` (`LockWhileMac`), Open Accessibility row.
- Window roots (review coverage, outside the model): `NotchWindowController.swift`, `NotchPreview.swift`,
  `NotchSnapshot.swift`, `AppWindowController.swift` (`makeWindow`, covers every app snapshot),
  `ShelfMenuPanel.swift`, the popovers in `AppComponents.swift` and `HomeEditorView.swift`. A new root without
  `.followsMotionSettings()` only follows the Mac's switch: grep for `NSHostingView(`, `NSHostingController(`,
  `ImageRenderer(` and `.popover(` on every change.
- `NotchView.swift` `OutlineID` (peek strip cross-fade) and the per-view fallbacks are review coverage, with
  the rules in `docs/ui/motion.md` › Reduce Motion.
- Tests: `Tests/NotchCoreTests/MotionSettingsTests.swift` replays the model's paths against the real view
  model (including real trackpad `NSEvent`s through `handleScroll`); `Tests/NowPlayingCoreTests/SoundBarsTests.swift`.

The model has one notch, two Home pages and one song; `own`, `mac` and `playing` start in every combination.
`macSeen` lags `mac` until the Mac's notification arrives (`MacFlips` is hidden in the chart). Real time,
animation frames, the Home editor, Mission Control, full screen, `isOnScreen` and memory are out of scope.
In unit tests `withAnimation` completions run at once, so `settling` is only visible in the model.

## Prove the check can fail

Work only on a scratch copy or a branch you own; keep other people's edits and restore each mutation before
the next. For each, set the model constant to `FALSE` in a scratch config and run `/statechart`, then make the
matching Swift change and run the script:

1. `ResetOnChange`: empty `motionChanged()`. Path: start scrolling Home → click Reduce motion → lift fingers.
   `NoHomeScrollWhileReduced` breaks at step 2, `NoHomePageStuckHalfway` at 3; `switchingMidScrollSettlesThePage`
   and `macSwitchMidScrollSettlesThePage` fail.
2. `ReducedTakesFadePath`: drop `motion.reducesMotion ||` in `scrollHome`. Path: start scrolling Home while
   reduced. `NoHomeScrollWhileReduced` breaks; `reducedTrackpadScrollNeverDragsHome` fails. (The same check in
   `showHomePage` has no unit test that can see it; confirm it by reading the code.)
3. `BarsHonorReduce`: drop `reduceMotion ||` in `SoundBarsMode.resolve`. `BarsStillWhenReduced` breaks in the
   first state; two `SoundBarsTests` fail.
4. `LockWhileMac`: drop the guard in `switchClicked`. `NoDeadSwitch` breaks after one click;
   `lockedSwitchKeepsTheOwnChoice` fails.

If the model reports a path the Swift test can't reproduce, treat the model as wrong until you show it isn't.
Never weaken a rule to get a pass. Restore the code and rerun the script: everything must pass.

## Keeping the check aligned

`verification/reduce-motion/coverage.md` holds the sync commit and the SHA-256 of each covered file as
reviewed. Compare them before relying on a pass. When a covered function changes, reread it and update the
model, the replay tests and the broken variants together. Move the sync commit forward only after confirming
that the model describes the code at the new commit. For changes that skipped this check, use
`/maintain-formal-verification-skill` if installed; otherwise do this alignment review by hand.
