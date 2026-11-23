# Reduce motion verification

Run `scripts/verify-reduce-motion.sh` with `TLA2TOOLS` pointing to TLC 1.7.4 and `JAVA` pointing to Java
(validated with Temurin 21.0.13+9). It runs the real Swift tests first, then TLC on the model; nothing opens on
screen and all checker output goes to a temporary folder. Use the project-local `verify-reduce-motion` skill for
the code mapping, the broken variants and upkeep; read every TLC result with `/statechart`.

## What it promises

PancakeNotch reduces motion when the Mac's Reduce motion is on **or** its own switch (Settings › General ›
Motion) is. The model checks every order of: clicking that switch, the Mac's switch changing and the Mac
telling the app, trackpad scrolls on Home (fingers down, a page turning, fingers lifting), arrow keys and page
dots, Home's settle animation ending, the views redrawing, and music starting or stopping.

| Rule | In plain words |
| --- | --- |
| `NoHomePageStuckHalfway` | A Home page is never left between two pages with nothing moving it (stuck pages can't be clicked). |
| `NoHomeScrollWhileReduced` | With Reduce motion on, Home's pages never slide: there's no in-between position. |
| `BarsStillWhenReduced` | With Reduce motion on, the sound bars never dance. |
| `DefaultMotionUnchanged` | With both switches off, playing music still makes the bars dance: the default is unchanged. |
| `NoDeadSwitch` | Every click on the switch changes what you see; while the Mac's is on, it's locked on and your own choice is kept. |
| `TypeOK` | Every variable keeps an expected value. |

The correct model reaches 88 states and 536 steps; all rules hold.

## Verified failure paths

Each guard was removed on purpose, in the model (a constant set to `FALSE`) and in the Swift code, then
restored. All were caught:

- **No reset when the setting changes** (`ResetOnChange`; `NotchViewModel.motionChanged`). Start scrolling Home
  (1), turn on Reduce motion (2), lift your fingers (3). `NoHomeScrollWhileReduced` breaks at 2 and
  `NoHomePageStuckHalfway` at 3: the page stays halfway, and once Reduce motion is off again it can't be
  clicked. Swift: `switchingMidScrollSettlesThePage`, `macSwitchMidScrollSettlesThePage` fail.
- **Scrolling ignores Reduce motion** (`ReducedTakesFadePath`; the `motion.reducesMotion` checks in
  `scrollHome` and `showHomePage`). Start scrolling with Reduce motion on (1): `NoHomeScrollWhileReduced`
  breaks. Swift: `reducedTrackpadScrollNeverDragsHome` fails for `scrollHome`. The `showHomePage` check (arrow
  keys, page dots) is covered by the model and by review only: in unit tests a settle animation ends at once,
  so neither branch leaves a trace.
- **Bars ignore Reduce motion** (`BarsHonorReduce`; `SoundBarsMode.resolve`). Breaks in the first state.
  Swift: `SoundBarsTests` `gentleMotion` and `followTheMusicListensOnlyWhenEverythingFits` fail.
- **Switch not locked while the Mac's is on** (`LockWhileMac`; `MotionSettings.switchClicked`). One click
  breaks `NoDeadSwitch`. Swift: `lockedSwitchKeepsTheOwnChoice` fails.
- Also checked in Swift only: dropping the own switch from `reducesMotion` fails four `MotionSettingsTests`.

## What it leaves out

Animation curves and transitions in the ~40 view files are not in the model: they read
`accessibilityReduceMotion`, which `followsMotionSettings()` hands down from each window's root, and
`swiftUIReadsTheValueTheRootHandsDown` guards that SwiftUI keeps returning the value handed down. A window root
that forgets the modifier only follows the Mac's switch; that is review coverage, listed in the skill. Real
time, the Home editor, Mission Control, full screen and memory use are out of scope. The model checks every
order of events, but only for one notch, two Home pages and one song.
