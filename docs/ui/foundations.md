# Foundations

The rules every PancakeNotch screen follows. Numbers are points (pt) unless they say otherwise. Opacities
are white on black: "white 0.6" means `.white.opacity(0.6)`.

- [Colour](#colour)
- [Type](#type)
- [Spacing and sizes](#spacing-and-sizes)
- [Corners and shapes](#corners-and-shapes)
- [Depth](#depth)
- [Icons](#icons)
- [States: hover, press, selected, disabled](#states-hover-press-selected-disabled)
- [Motion](#motion)
- [Accessibility](#accessibility)
- [Words](#words)
- [Speed is part of the design](#speed-is-part-of-the-design)

## Colour

**Monochrome.** Backgrounds are black, text is white, and everything in between is white at some opacity.
There is no accent colour: no blue buttons, no system tint, no coloured switches. The closed notch must be
pure black (`Color.black`) so it matches the camera cutout exactly.

The only colour allowed:

| Colour source | Where |
| --- | --- |
| The user's content | Album art, Shelf file previews and file icons |
| Small status marks and gauges | Agents' status dots (working blue, needs you orange, done green, stopped grey, error red) and AI Usage's bars and rings by % left (green ≥ 50%, yellow ≥ 20%, orange ≥ 10%, red below). Use `StatusColors` (`Sources/ModuleAgents/StatusColors.swift`); text and backgrounds stay grey |

App icons shown in the notch (the playing app, the media apps menu) are drawn **in grey**, not in colour.

### In the notch

The notch has no colour enum; it uses a small, consistent set of white opacities. Pick from this table rather
than inventing a new value.

| Use | Value |
| --- | --- |
| Surface | `Color.black` |
| Main text, selected icon | white 1.0 (`.foregroundStyle(.white)` on the page) |
| Secondary text (artist, details, status lines) | white 0.6 (0.55 for small times and helper lines) |
| Quiet text and hints, section labels | white 0.45 |
| Quiet icons in empty states | white 0.4 |
| Unselected tab icons / segment text | white 0.5–0.6, 0.85 on hover |
| Control fill (pill, round button) | white 0.13, 0.2 on hover |
| Main action fill | white 1.0 with **black** text, 0.88 on hover |
| Segmented track | white 0.08; selected segment white 0.16–0.18 |
| Row or tile hover | white 0.07–0.1 |
| Dividers | white 0.1–0.12, 1 pt |
| Thin border on artwork and tiles | white 0.06–0.08 |
| Progress tracks | white 0.12–0.18; filled part white 0.92 |
| Ring track | white 0.25; ring white 1.0 |
| Dimmed overlay on art | black 0.35 |

### In the app window

The app window uses named colours in `AppPalette` (`AppComponents.swift`). Always use these; several have a
stronger version for Increase Contrast built in.

| Token | Value | Use |
| --- | --- | --- |
| `background` | grey 0.035 | The page behind everything |
| `sidebar` | grey 0.058 | The sidebar |
| `glass` | white 0.045 (0.08 high contrast) | Card fill (via `.glassPanel()`) |
| `hairline` / `hairlineStrong` | white 0.085 / 0.16 | Lines between rows, card borders, pill outlines |
| `selection` / `hover` / `pressed` | white 0.1 / 0.055 / 0.13 | Selected rows, hovered rows, pressed buttons |
| `primaryText` | white | Titles and values |
| `secondaryText` | white 0.64 (0.85 high contrast) | Subtitles, explanations. Never go dimmer for text people need to read |
| `tertiaryText` | white 0.46 | Decoration and hints that repeat something said elsewhere |
| `ink` | grey 0.96 | Filled parts: the "on" switch track, the slider's filled side, the chosen segment |
| `rail` | white 0.17 | Empty parts: the "off" switch track, the slider rail |
| `knobOn` / `knobOff` | grey 0.06 / 0.9 | Switch knobs |

The window is always dark (`.environment(\.colorScheme, .dark)`), whatever the system appearance.

## Type

Everything is **SF Pro** through `.system(size:weight:)` (or SF Pro **Rounded** in the app window). Sizes are
small and exact, often in half points. Weights are mostly `.semibold` for anything you act on or read first,
`.medium` for supporting labels, regular for body text.

Anything that counts or ticks (times, percentages, item counts) uses `.monospacedDigit()` so it doesn't jiggle.

### Notch scale (SF Pro, `.system`)

| Role | Size and weight | Example |
| --- | --- | --- |
| Big status | 19 semibold | "Keeping your Mac awake" |
| Panel title | 15 semibold | Song title, "Nothing playing" |
| Row or item title | 12–13 semibold | An agent's thread, a Menu row |
| Body and secondary | 12–12.5 regular/medium, white 0.6 | Artist · album, status detail |
| Header beside the notch | 12 semibold | "Shelf" |
| Pill and button labels | 11.5 semibold | `NotchPill` |
| Segmented switch labels | 11 semibold | "Timer · Stopwatch", "Screen on · Can sleep" |
| Small details, times | 10.5 medium, monospaced digits, white 0.55 | "2:31", "-0:41" |
| Notes, captions | 10.5 medium, white 0.45 | Keep Awake's screen note |
| Section labels | 9.5 semibold, ALL CAPS, kerning 0.7, white 0.45 | "FAVORITES" |
| Symbols inside pills | 9.5 bold | The ▶ in "Play" |

Ears are tiny: icons around 10–12, text 10.5 semibold with `.minimumScaleFactor(0.8)`.

### App window scale (SF Pro Rounded, `Font.app(size:weight:)`)

| Role | Size and weight |
| --- | --- |
| Home's big headline and stat numbers | 34 bold |
| Page title (`AppPage`) | 30 bold, kerning −0.4 |
| Module name on its card | 18 bold |
| Card titles (Home boxes, welcome) | 15–17 bold |
| Page subtitle | 14 regular, `secondaryText` |
| Row title (`SettingsRowLabel`) | 13.5 medium |
| Buttons (`PillButtonStyle`) | 13 semibold |
| Row subtitle, card footers, bullet points | 12.5 regular (bullets medium), `secondaryText` |
| Segments and chips | 12 semibold |
| Section labels (`SectionLabel`) | 11 semibold, ALL CAPS, kerning 0.8, `secondaryText` |

Use `.font(.app(size:weight:))` for text in the window. Don't mix SF Pro and SF Pro Rounded inside one
surface: the notch (and the practice notches shown in the window) is SF Pro; the window around it is Rounded.

## Spacing and sizes

### Notch

| Thing | Value |
| --- | --- |
| Open panel body | up to 600 × 180 (taller: 228 "medium", 360 "tall"); computed by `NotchLayout`, never hard-coded |
| Side padding inside the open panel | 20 (the Shelf and the Module Menu use 18) |
| Bottom padding | 12–16 |
| Top band | as tall as the hardware notch; content starts 6–8 below it |
| Gap between a picture and its text column | 18 |
| Gaps inside a row of controls | 6–8; inside a pill 5 |
| Module tabs | start 16 from the left edge; buttons 28 × 22, 2 apart |
| Pill height | 24 (`NotchPill`); 22 in tighter headers; 20 for segments and small badges |
| Round buttons | 36 by default (24 small) |
| Peek strip | 24 high, 12 side padding |

### App window

| Thing | Value |
| --- | --- |
| Window | 1000 × 780 default, 860 × 600 minimum |
| Sidebar | 232 wide, rows 32 high |
| Page column | max 760 wide, 40 side padding, 48 top, 40 bottom (`PageScroll`) |
| Title to content | 28; between sections 28 |
| Card inset | 20 (`AppMetrics.cardInset`): card content, section labels and footers all start on this line |
| Settings row | min 62 high, 14 vertical padding, 24 between label and control |
| Header to card | 10 |
| Buttons | min 30 high, 14 side padding; segments and chips 26 high |

## Corners and shapes

Rounded rectangles are always `style: .continuous` (the smooth Apple squircle), never plain circular corners.
Pills, segments, tabs and chips are **capsules**.

| Thing | Radius |
| --- | --- |
| Notch closed | bottom 14, no top ears |
| Notch compact | top ears 6, bottom 14 (16 with a peek strip) |
| Notch open | top ears 18, bottom 26 |
| Album art in the open panel | 14 |
| Art in an ear | 6 |
| Module Menu favourite tiles | 12 |
| Rows, small square buttons, length buttons | 9 |
| Note backgrounds on art | 8 |
| Icon squares | 7–8 |
| App window cards (`glassPanel`) | 16 |
| Practice notch stage | 18 |
| Sidebar rows | 9 |
| Drop-down rows | 7 |

## Depth

The design is flat. Depth comes from opacity, not from shadows or materials.

- The open notch casts one shadow: black 0.5, radius 14, y 6. Compact and closed cast none.
- Album art has a soft shadow (black 0.5, radius 10, y 4) because it's the one picture on the panel.
- App window cards are "glass": a faint white fill, a highlight fading down from the top, and a hairline border
  brighter at the top, as if lit from above. Use `.glassPanel()`; don't build your own.
- No blur materials, no Liquid Glass, no gradients except the glass highlight and the artwork placeholder.

## Icons

- SF Symbols only. No custom icon images (the logo glyph is the one exception).
- Prefer the outline symbol at rest and the `.fill` version for "on" or "playing" (`cup.and.heat.waves` →
  `cup.and.heat.waves.fill`, `star` → `star.fill`).
- When an icon changes, use `.contentTransition(.symbolEffect(.replace))`.
- Each module has one symbol, used in its tab, the Module Menu and its card in the app window. It's set twice
  (`NotchModule.symbol` and `AppContext.moduleInfo`): keep them the same.
- Icon-only buttons always get a `.help()` tooltip and an accessibility label.

## States: hover, press, selected, disabled

| State | Notch | App window |
| --- | --- | --- |
| Hover | fill goes up a step (0.13 → 0.2; text 0.6 → 0.85), `.easeOut(duration: 0.15)` | `hover` → `selection`, same timing |
| Press | `PressableStyle`: scale 0.9 with a quick spring; with Reduce Motion, dim to 0.6 instead | `pressed` fill (white 0.13); prominent buttons go to 0.78 white |
| Selected | soft capsule behind (white 0.16–0.18), full-white text, `.isSelected` trait | `ink` fill with black text (segments), or `selection` fill plus hairline border (sidebar) |
| Main action | white fill, black text, 0.88 on hover | `ProminentPillButtonStyle`: white capsule, black text |
| Disabled | `.disabled(true)` plus `.opacity(0.4)`; keep it in place so nothing moves; say why in `.help` | Controls dim themselves to 0.4 when disabled; dim a whole row with `.opacity(0.4)` |
| Keyboard focus | `keyFocusRing`: a white 0.9 ring, 1.5 wide, 3 outside the shape | system focus, or arrow keys on custom controls |

A second click to confirm a destructive action turns the button prominent and asks the question in its label
("Clear all" → "Clear 4 items?").

## Motion

Almost everything in PancakeNotch moves: the notch grows and settles like one soft object, pages slide and blur
into each other, numbers roll and icons morph. Motion is short (mostly 0.15–0.3 s) and springy without bouncing,
it comes from where things live, and Reduce Motion always turns it into a cross-fade. The most used values:

| What | Animation | Reduce Motion |
| --- | --- | --- |
| Notch opens / closes | `NotchViewModel.animation(opening:)`: spring(0.42, 0.8) / spring(0.45, 1.0) | `.easeInOut(duration: 0.2)` |
| Switching modules and pages | `NotchViewModel.switchAnimation`: spring(0.32, 0.86) | `.easeInOut(duration: 0.15)` |
| Panel grows taller | `NotchViewModel.tallAnimation`: spring(0.28, 0.88) | `.easeInOut(duration: 0.15)` |
| Hover | `.easeOut(duration: 0.15)` | same |
| Small changes inside a page | `.easeInOut(duration: 0.2)`–`0.25`, `.opacity` | same |
| App window controls | `.snappy(duration: 0.22)` | none |

Every curve, transition and technique, with Reduce Motion versions and how to check them, is in
**[Motion](motion.md)**. Read it before adding anything that appears, disappears or changes.

## Accessibility

- **Every control has a VoiceOver label.** Text buttons read their title; icon-only ones need
  `.accessibilityLabel`. Add `.accessibilityHint` when the result isn't obvious ("Shows Shelf in the notch.").
- Mark the chosen tab, segment or row with `.accessibilityAddTraits(.isSelected)`, and section labels with
  `.isHeader`.
- Hide decoration from VoiceOver (`.accessibilityHidden(true)`): rings, sound bars, placeholder art, dots.
- Group a panel with `.accessibilityElement(children: .contain)` and a label naming it ("Keep Awake").
- Combine a title and its detail into one element with `.accessibilityElement(children: .combine)`, or give a
  custom spoken version (times in words: "2 minutes 5 seconds", not "2:05").
- Custom controls read as standard ones with `.accessibilityRepresentation` (the monochrome switch reads as a
  Toggle, the segmented control as a Picker).
- Each module offers `accessibilityStatus` for the closed and compact notch ("Shelf is full").
- Increase Contrast: use `AppPalette` colours in the window, which strengthen by themselves.

## Words

PancakeNotch talks like a helpful person, not a manual.

- **Plain English, second person.** "Hovering won't open the notch. Click to open it." No jargon, no internal
  names (say "the spots beside the notch", not "ears", in the UI).
- **Say what happens**, including the limits: "Closing a MacBook's lid still puts it to sleep." "Nothing about
  you or this Mac is sent."
- **Buttons** are short verbs in title case: "Turn On", "Check Now", "Not Now", "Take a Look", "Resume Music".
  Follow the buttons next to yours when unsure.
- **Setting titles and labels** are sentence case: "Launch at login", "Open after hovering for".
  **Subtitles** are full sentences with a full stop.
- **Section labels** are written in normal case and shown in capitals by the view (`.uppercased()`), so
  translations aren't shouted at.
- Short units: "30 min", "1 hr", "4 items". Join bits with a middle dot: "Until 3:13 AM · 1 hr left".
- Every user-facing string goes through `String(localized:)` (or a `Text("…")` literal, which is localized
  for you). Add a `comment:` when a word could be read two ways ("Done", "Ad").
- Practice copies in the app window say so: "A practice copy: it doesn't keep your Mac awake."

## Speed is part of the design

PancakeNotch promises to be light: about 0% CPU when idle and under 50 MB of memory. UI choices matter here.

- **No timers or polling** to drive the UI. React to notifications, callbacks and observed state.
- A clock on screen ticks only while it's visible and something is counting, at the slowest pace that looks
  right: `TimelineView(.periodic(from:by:))` lined up with the moment the shown digit changes, or
  `.animation(minimumInterval:paused:)` with `paused` true when nothing moves.
- Continuous motion (the draining ring, the sound bars) is drawn by Core Animation layers so the window server
  animates it and the app does nothing between frames. Off-screen snapshots can't draw those layers, so each has
  a plain SwiftUI stand-in when `isSnapshot` is true.
- Start work when a module's page appears (`notchDidOpen`) and stop it, releasing big things like images, when
  it goes away (`notchDidClose`).
- Don't add packages for UI. Everything is SwiftUI and AppKit.
