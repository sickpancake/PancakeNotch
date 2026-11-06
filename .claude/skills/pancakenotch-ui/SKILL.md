---
name: pancakenotch-ui
description: Build or change PancakeNotch's user interface so it matches the existing look and feel (pure black/white/grey, SF Pro, the notch's panel layout, the app window's glass cards and monochrome controls, and its fluid, springy motion where almost everything animates). Use this whenever you add or edit any SwiftUI view in PancakeNotch — a new notch module or its open page, compact ears, peek strips, Module Menu, buttons, switches, empty or error states, an app window page, a Modules card, a settings row, onboarding or Learn screens, animations and transitions — and when reviewing UI for consistency, restyling something, or answering "what should this look like?". Use it even for small tweaks like adding one button or one setting, since those are where styles drift.
---

# Building PancakeNotch UI

PancakeNotch should feel like one calm, monochrome thing that grows out of the MacBook notch. New UI earns its
place by looking like it was always there: same colours, sizes, shapes, motion and words as its neighbours, and
working fully in every state a person can hit. Motion matters as much as the look: almost every change on screen
is animated, so the notch feels like one soft object that grows, slides and settles, never a set of pictures
that cut from one to the next.

The full reference is the UI guide in the repo. Read the parts you need before writing code:

| Read | When |
| --- | --- |
| `docs/ui/README.md` | Always first (short): the look, principles, where code lives |
| `docs/ui/foundations.md` | Always: colour, type, spacing, corners, states, accessibility, words, speed |
| `docs/ui/motion.md` | Always when anything appears, disappears or changes (nearly every UI change): curves, transitions, wiring, Reduce Motion |
| `docs/ui/notch.md` | Anything in the notch: module pages, ears, peek strips, notch controls |
| `docs/ui/app-window.md` | Anything in the PancakeNotch window: pages, cards, rows, settings, module cards |

## Workflow

### 1. Find the nearest neighbour

Before designing, find the existing screen most like what you're building and read its code. Its structure is
your template.

- A notch page with a picture and text → `Sources/ModuleNowPlaying/NowPlayingView.swift`
- A notch page with a status and actions → `Sources/ModuleKeepAwake/KeepAwakeView.swift`
- A notch list → `Sources/ModuleAgents/AgentsView.swift`
- Ears and strips → `Sources/Module*/…Ears.swift` (Keep Awake's is the smallest)
- A settings page → `Sources/PancakeNotch/AppWindow/SettingsPages.swift`
- A module card → `Sources/PancakeNotch/AppWindow/KeepAwakeModuleCard.swift`
- Shared parts → `Sources/NotchCore/NotchControls.swift`, `Sources/PancakeNotch/AppWindow/AppComponents.swift`
- Motion → `Sources/NotchCore/NotchView.swift` (page transitions), `NotchModuleBar.swift` (gliding highlight),
  `Sources/ModuleTimer/DrumText.swift` (rolling digits), `Sources/NotchCore/DrainingRing.swift` (continuous motion)

### 2. List every state before drawing

Write down each state the UI can be in and what it shows: first run, empty, loading or waiting, working,
paused, done, error, missing permission, nothing playing, disabled, practice copy in the app window, narrow
screen, Reduce Motion, VoiceOver. For each control, note the states where it works; everywhere else it is
hidden, or dimmed with the reason in its tooltip. A button that shows but does nothing is a bug, not a detail.

Keep the page's shape the same across states (Now Playing keeps its art square even when nothing plays), so
switching doesn't jump.

### 3. Build from the shared parts

Use the existing components and the values in the guide's tables. Don't re-style a button, switch or card; don't
invent a new opacity, font size or radius when a listed one is close. If the same custom control already
exists privately in two modules (the segmented switch, the header pill), move it into NotchCore and reuse it
rather than making another copy. If something truly needs a new style, stop and ask the maintainer first.

Quick reference for the values you'll reach for most (the guide has the rest):

| | Notch | App window |
| --- | --- | --- |
| Font | `.system(size:weight:)` SF Pro | `.app(size:weight:)` SF Pro Rounded |
| Text | white; secondary white 0.6; quiet 0.45 | `AppPalette.primaryText` / `.secondaryText` / `.tertiaryText` |
| Main action | `NotchPill(…, prominent: true)` white with black text | `ProminentPillButtonStyle()`, one per card |
| Other actions | `NotchPill`, `NotchRoundButton` (fill white 0.13, hover 0.2) | plain `Button` (gets `PillButtonStyle`) |
| Choices | segmented capsule: track white 0.08, selected 0.18 | `MonochromeSegmented`, `MonochromeChips`, `MonochromeDropdown` |
| On/off | — | `Toggle(…).labelsHidden()` (monochrome switch) |
| Surfaces | `Color.black` | `SettingsCard` / `.glassPanel()` |
| Corners | continuous; rows 9, art 14, tiles 12; capsules for pills | cards 16, rows 9 |
| Hover | `.easeOut(duration: 0.15)` | same |
| Press | `PressableStyle()` | built into the pill styles |
| Big moves | `NotchViewModel.switchAnimation` / `.tallAnimation` / `.animation(opening:)` | `.snappy(duration: 0.22)` controls, `.easeInOut(duration: 0.25)` sections |
| Small changes | `.easeInOut(duration: 0.2)`–`0.25` with `.opacity` | same |

Rules that are easy to break:

- **Monochrome.** Black, white and grey only. Colour is allowed only for the user's content (album art, file
  previews) and the small status marks in Agents and AI Usage (`StatusColors`). No accent colour, no system
  blue, no stock `Picker`, `Slider` or tinted `Toggle` in the app window.
- **Nothing under the camera cutout.** In the open notch, reserve the notch's width in the top band with
  `Color.clear.frame(width: notchWidth)`; the module tabs own the left half (`notchModuleBarWidth`).
- **Sizes come from `NotchLayout`**, never hard-coded per Mac. The open panel is wide and short: lay out side by
  side.
- **Reduce Motion**: every slide, scale or blur has an `.opacity` fallback.
- **VoiceOver**: every control has a label; icon-only buttons also get `.help`; selected items get
  `.isSelected`; decoration is hidden.
- **Words**: plain English, second person, say what happens. Buttons are short title-case verbs ("Turn On");
  setting titles are sentence case; subtitles are full sentences. All strings via `String(localized:)`
  (`Text("…")` literals count), with a `comment:` when a word is ambiguous.
- **No timers or polling** to drive the UI. Clocks tick only while visible and counting
  (`TimelineView(.periodic…)` or `.animation(minimumInterval:paused:)`); continuous motion uses Core Animation
  with a SwiftUI stand-in for snapshots (`isSnapshot`).
- Swift 6 strict concurrency, UI on `@MainActor`, macOS 15 APIs (gate anything newer with `#available`).

### 4. Make it move

Go back over the states from step 2: every change between them gets motion. Read `docs/ui/motion.md` and, for each
`if`, `switch`, `ForEach`, changing text, number, icon or size in your views, pick from its tables:

- **Appearing or leaving:** a transition. Whole pages and menus slide or grow with a little blur
  (`moduleSwitch`, `menuReveal`, the 24 pt page slide); small things (rows, notes, badges) just `.opacity`.
- **Replacing content:** `.id(…)` + transition + `.animation(curve, value: id)` (a new song's text rises 3 pt).
- **In place:** `.contentTransition(.numericText(value:))` for numbers, `.symbolEffect(.replace)` for icons,
  `.opacity` for text; a moving highlight glides with `matchedGeometryEffect`; custom gauges are `Animatable`.
- **Feel:** short (0.15–0.3 s), springs that settle without bouncing for moves, ease curves for fades and hover.
  Things come from where they live (anchor scales at their button, slide from the module's side) and leaving
  things fade in place instead of travelling. Reuse the `NotchViewModel` curves rather than copying numbers.
- **Wiring:** model-driven changes inside `withAnimation(…)`; local ones with `.animation(_:value:)` on the
  smallest view that changes. Never `.animation(_:)` without a value, and never wait on an animation finishing.
- **Reduce Motion:** write the fallback right beside each animation: slides, scales and blurs become `.opacity`;
  springs become `.easeInOut(duration: 0.15)`; app window controls change instantly.
- **Continuous motion** (something that moves the whole time it's shown) uses a Core Animation layer with a
  SwiftUI stand-in for snapshots, never a timer or a SwiftUI `repeatForever` that stays on screen.
- Lay views out at their final size and let clipping reveal them, so text never re-wraps mid-animation.

### 5. Make it reachable end to end

A screen isn't done until a person can get to it and use it in the real app:

- New notch module: `NotchModule` members (`title`, `symbol`, `menuStatus`, `accessibilityStatus`, ears, peek),
  its name and symbol in `AppContext.moduleInfo`, a `ModuleCard` with a practice copy (`PracticeKind`), a Learn
  lesson for "Try it", and a Help topic if people might get stuck.
- New app page: an `AppSection` case and a snapshot in `AppWindowController.writeSnapshots`.
- New notch state: add it to the module's `…Snapshot.swift` (wired into `AppDelegate.writeSnapshot`).

### 6. Look at it

Build and render off-screen. Don't open the real app on screen to check; nothing here needs a window or Xcode.

```sh
.claude/skills/pancakenotch-ui/scripts/snapshot.sh <out-folder> [--app]
```

It builds, writes every notch state to `<out>/notch.png` and cuts it into `notch-0.png…` pieces small enough to
view; `--app` also writes every app window page to `<out>/app/`. Open the pieces with your image viewer and
check:

- [ ] Nothing sits under the black cutout area; nothing clips or truncates badly at the panel's edges.
- [ ] It lines up with its neighbours: same side padding, same baseline for the band, same row heights.
- [ ] Every state from step 2 is on the sheet and looks intentional (empty and error states too).
- [ ] Only black, white and grey, except allowed content and status colours.
- [ ] Text sizes and weights match the tables; numbers use monospaced digits; no label is cut off, even the
  longest one.
- [ ] Each animation's start and end states are both on the sheet and share the same layout (nothing jumps
  sideways or re-wraps between them).
- [ ] Every change in your diff has a transition or `.animation(_:value:)` from `motion.md`, with a Reduce Motion
  version.

Then run `./scripts/swift.sh test`. Mention in your summary which states you looked at, and describe the motion
("the note fades up 3 pt when it changes") so the maintainer knows what to watch for in the real app.

### 7. Keep the guide true

If you added a shared component, a new pattern or a new value, update `docs/ui/` in the same change so the next
person finds it. If the code and the guide disagree, the code wins; fix the guide.
