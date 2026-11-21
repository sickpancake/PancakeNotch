# PancakeNotch UI guide

How PancakeNotch looks and behaves, written down so new screens match the ones already there. It covers the
Mac app only: the **notch** (closed, its ears, and the open panel with each module's page) and the
**app window** (Home, Modules, Learn, Statistics, the settings pages, Help and About). The website is
separate and has its own look.

Everything here is taken from the code as it is today. If the code and this guide disagree, the code
wins: fix the guide in the same change.

| Page | What's in it |
| --- | --- |
| [Foundations](foundations.md) | The rules everything follows: colour, type, spacing, corners, accessibility, wording, speed |
| [Motion](motion.md) | How things move: the curves, the transitions, how to wire them up, continuous motion, Reduce Motion |
| [The notch](notch.md) | Notch states, the open panel's layout, ears, peek strips, and the notch's own controls |
| [The app window](app-window.md) | Pages, cards, rows, the monochrome controls, module cards and practice notches |

## The look in one paragraph

PancakeNotch is **black, white and grey**, drawn in **SF Pro** with **SF Symbols**. The closed notch is pure
black and exactly the size of the camera cutout, so it disappears into the hardware. Everything that grows out
of it is still black, with white text and soft see-through white for controls (white at 6–20% opacity). The
only real colour is the user's own content: album art, file previews, and a few small status marks (Agents'
dots and AI Usage's gauges). The app window is always dark too, uses SF Pro **Rounded**, and builds every
page from the same glass cards and capsule controls. Almost everything is animated: the notch grows, slides
and settles like one soft object, with short springy motion that turns into plain cross-fades when Reduce
Motion is on.

## Core principles

1. **Design for the person first.** Each screen should let someone get the job done end to end in the real
   app, not just look right in a picture. Think through first run, empty, error, missing permission,
   nothing playing and screen changes before you draw anything.
2. **Every visible control works.** A button that shows but does nothing in the current state (or does the
   wrong thing) is a bug. Hide it, or dim and disable it with a reason in its tooltip and VoiceOver hint.
3. **Reuse what's there.** Use the shared components listed in these pages instead of re-styling a button
   or a switch. A copy that drifts by half a point or 2% opacity is how an app stops feeling like one thing.
   If you need something new, build it from the same tokens, and ask before inventing a new style.
4. **Light and quiet.** No timers or polling to drive the UI; animations stop when they can't be seen. The
   app's speed and memory budget are part of the design (see [Foundations › Speed](foundations.md#speed-is-part-of-the-design)).

## Where the code lives

| What | File |
| --- | --- |
| Notch outline, sizes per state | `Sources/NotchCore/NotchShape.swift`, `NotchLayout.swift`, `NotchGeometry.swift` |
| Notch root view, ears, transitions | `Sources/NotchCore/NotchView.swift` |
| Module tabs and the Home button | `Sources/NotchCore/NotchModuleBar.swift` |
| Home in the notch (grid, cards, ghosts, page dots) | `Sources/NotchCore/Home/NotchHomeView.swift`, widget sizes in `HomeWidgetContext.swift` |
| Each module's widgets | `Sources/Module*/*Widget*.swift`; Battery and Statistics in `Sources/PancakeNotch/HomeExtras.swift` |
| The Home editor (app window) | `Sources/PancakeNotch/AppWindow/HomeEditorView.swift` |
| Shared notch controls | `Sources/NotchCore/NotchControls.swift` (`PressableStyle`, `NotchPill`, `NotchRoundButton`), `DrainingRing.swift` |
| What a module provides | `Sources/NotchCore/NotchModule.swift` (`NotchModule`, `CompactEars`) |
| Each module's pages | `Sources/Module*/…View.swift`, `…Ears.swift`, `…Layout.swift` |
| App window colours, type and controls | `Sources/PancakeNotch/AppWindow/AppComponents.swift`, `AppFont.swift` |
| App window shell and sidebar | `Sources/PancakeNotch/AppWindow/AppWindowView.swift` |
| Module cards and practice notches | `Sources/PancakeNotch/AppWindow/AgentsModuleCards.swift` (`ModuleCard`), `ModulesView.swift`, `NotchArt.swift` |

## Checking your work

You don't need Xcode or a visible window. Build, then render pictures off-screen:

```sh
./scripts/swift.sh build
PANCAKENOTCH_SNAPSHOT=/tmp/notch.png .build/debug/PancakeNotch          # every notch state, one tall sheet
PANCAKENOTCH_SNAPSHOT_SETTINGS=/tmp/app .build/debug/PancakeNotch       # every app window page, one PNG each
```

The notch sheet draws a grey desktop and a light menu bar behind each notch, and covers the camera cutout
with black, so anything placed under the cutout shows up as missing. Add your new states to the module's
`…Snapshot.swift` so they appear on the sheet. Debug builds only; published builds ignore these switches.
