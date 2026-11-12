# The app window

The PancakeNotch window: Overview, Modules, Home, Learn, Statistics, the settings pages (General, Notch, Keyboard), Help
and About, plus the first-run welcome. Read [Foundations](foundations.md) first. The building blocks below live
in `Sources/PancakeNotch/AppWindow/AppComponents.swift` unless noted.

- [The shell](#the-shell)
- [Pages](#pages)
- [Cards and rows](#cards-and-rows)
- [Controls](#controls)
- [Module cards and practice notches](#module-cards-and-practice-notches)
- [Other page patterns](#other-page-patterns)
- [Adding a page or a module](#adding-a-page-or-a-module)

## The shell

`AppWindowView` puts a 232 pt sidebar (`AppPalette.sidebar`) and a 1 pt hairline beside the page
(`AppPalette.background`). Until the welcome is done, `OnboardingView` fills the window instead.

- **Sidebar:** the logo glyph and "PancakeNotch" (15 bold) at the top; Overview, Modules, Home, Learn, Statistics; a
  "SETTINGS" `SectionLabel` over General, Notch, Keyboard; Help, About and Quit at the bottom with the version
  in `tertiaryText`. Rows are 32 high, 9 pt corners, icon 13 medium in an 18 pt column, title 13.5
  (semibold when selected). Selected: `selection` fill plus a hairline border; hover: `hover` fill. The first nine
  pages have ⌘1 … ⌘9 in sidebar order (there is no ⌘10, so About has none).
- **`.appWindowStyle()`** is applied once at the root. It makes every `Toggle` a `MonochromeSwitchStyle`, every
  `Button` a `PillButtonStyle`, tints white, forces dark mode and sets the minimum size. Don't override these per
  view unless you need the prominent variant.

## Pages

Every page is an `AppPage`:

```swift
AppPage(
    title: String(localized: "General"),
    subtitle: String(localized: "How PancakeNotch starts, where you find it and how it updates.")
) {
    SettingsCard(header: String(localized: "Startup")) { … }
    UpdatesCard(updates: updates)
}
```

- Title 30 bold Rounded, subtitle 14 in `secondaryText`, one sentence about the page.
- An optional `accessory:` sits right of the title for a control that affects the whole page (Statistics'
  time range).
- `PageScroll` gives every page the same column: max 760 wide, 40 side padding, 48 top, 40 bottom.
- The page's sections stack with 28 pt between them.

## Cards and rows

| Building block | What it is |
| --- | --- |
| `.glassPanel(cornerRadius: 16)` | The card surface: faint white fill, top highlight, hairline border brighter at the top |
| `SettingsCard(header:footer:) { rows }` | A glass card of rows with hairlines drawn between them for you. The header is a `SectionLabel` above the card; the footer is 12.5 `secondaryText` under it. Both start at the card inset (20) |
| `SettingsRow(title:subtitle:) { control }` | One setting: title (13.5 medium) and a grey sentence under it (12.5) on the left, the control on the right. Min 62 high |
| `SettingsRowLabel` + `.settingsRowPadding()` | The same, for rows that need a custom layout |
| `HairlineRows { rows }` | Rows with hairlines between them, without the card (used inside module cards) |
| `SectionLabel(title:)` | 11 semibold, all caps, kerning 0.8, `secondaryText`, marked as a header |

Rows only show when they apply. A row that depends on another setting appears under it when it matters
(Keep Awake's "When you plug in" only after "Stop" is chosen), or is dimmed with `.disabled` + `.opacity(0.4)`
when hiding it would confuse ("Open after hovering for" while "Open on click only" is on). When a setting needs
something else switched on, say so in the subtitle and offer a button that does it ("Turn On Agents").

## Controls

Use these instead of system controls; stock pickers, sliders and accent-coloured switches break the monochrome
look.

| Need | Use | Notes |
| --- | --- | --- |
| On/off | `Toggle(…).labelsHidden()` (styled as `MonochromeSwitchStyle` by the window) | White track with a black knob when on, grey when off. `.large` size only for Overview's big notch switch. Always give the Toggle a real title for VoiceOver, even though it's hidden |
| One of 2–4 short options | `MonochromeSegmented(title:options:selection:)` | Chosen option is a white capsule with black text; reads as a Picker |
| Any of several options | `MonochromeChips(title:options:selection:)` | Same look, several can be on; each reads as on/off |
| One of a longer list | `MonochromeDropdown(title:sections:selection:onChoose:width:)` | A pill showing the choice, a dark list that scrolls, opens at the chosen row, arrow keys and Return work |
| A number in a range | `MonochromeSlider(value:range:step:accessibilityLabel:accessibilityValue:)` | White fill on a grey rail, 18 pt knob, arrow keys step it. Usually with the value and a "recommended" mark beside it (`DelayRow`) |
| A secondary action | `Button(…)` (gets `PillButtonStyle`) | Quiet glass capsule with a hairline outline, 13 semibold, min 30 high |
| The main action | `.buttonStyle(ProminentPillButtonStyle())` | Solid white capsule, black text. At most one per card |
| A link that leaves the app | `Label(…, systemImage: "arrow.up.right").labelStyle(TrailingIconLabelStyle())` | Text first, small arrow after |

Disabled controls dim themselves to 0.4. A disabled button explains itself with `.help`.

## Module cards and practice notches

Each module has one card on the Modules page, built with `ModuleCard` (`AgentsModuleCards.swift`):

1. **A practice notch** on top: `NotchStage` on black, top corners 16. It's a working copy of the notch with
   pretend data (`PracticeKind`, `PracticeSet` in `NotchArt.swift`), live only while the module is on. Hints
   under it say what to do: `inactiveHint` ("Turn on Keep Awake to try it here.") and `activeHint` ("A practice
   copy: it doesn't keep your Mac awake. Hover the notch and turn it on.").
2. A hairline, then **`ModuleAbout`**: the module's symbol in a 30 pt square (`selection` fill, corners 8), its
   name (18 bold) and its on/off switch; a summary sentence or two (13.5, `secondaryText`); four short bullet
   points in two columns (12.5 medium, 4 pt dots); and a "Try it" button with `graduationcap` that opens its
   Learn lesson.
3. While the module is on: a hairline and a **Settings** disclosure row (48 high, chevron turns 90°). Opened,
   its settings show as `SettingsRow`s inside `HairlineRows`.

The whole card is clipped to 16 pt corners and wrapped in `.glassPanel()`. Writing for cards: the summary says
what it's for in everyday terms, and the bullet points are things a person would notice ("A coffee cup beside
the notch while it's on, and in the menu bar"), not features.

The Notch settings page also has a practice notch at the top (corners 18, hairline gradient border) so people
can try their settings right there.

## Other page patterns

- **Home (the editor):** a black panel as wide as the open notch with the grid of the page being edited (page
  tabs, Undo/Redo and a Layouts menu above it), and a gallery of widgets below. Widgets are drawn with practice
  data and wiggle gently (±0.9°) only while the window is active, nothing is being dragged and Reduce Motion is
  off. Each has a − badge, a size button that shows on hover or focus, a right-click menu and VoiceOver actions;
  arrows move the focused one, Delete removes it. Drags are private (no pasteboard), so nothing lands in the Shelf.
- **Overview:** a hero card with the notch art and the big notch switch, small boxes (update ready, Learn
  progress) with a 16 bold icon tile, stat tiles with big 34 bold numbers, and a tips card.
- **Statistics:** charts with Swift Charts in white (`AppPalette.ink`, 0.8 for bars not highlighted) on
  `hairline` grid lines, axis labels 10.5 in `secondaryText`. The live memory and CPU readings tick once a
  second only while the page is visible. Empty sections say what will appear and when.
- **Learn and the welcome:** steps with a practice notch the person actually uses; progress shown as segments.
- **Help:** links to topics on the website through `HelpLinks.url(_:)`; never hard-code the address.

## Adding a page or a module

A new **page** needs a case in `AppSection` (title, SF Symbol, its place in the sidebar), its view in
`AppWindowView`, and a picture in `AppWindowController.writeSnapshots`. Adding a case renumbers the ⌘ shortcuts
of the pages after it.

A new **module** shows up in the window in several places. To be finished, it needs:

- its name and symbol in `AppContext.moduleInfo` (the same as its `NotchModule.title` and `symbol`);
- a `ModuleCard` on the Modules page with a practice notch (a `PracticeKind` and its pretend module), a summary,
  four points and its settings rows;
- a Learn lesson for "Try it", and a Help topic (`HelpTopic`) if people might get stuck;
- its states in the snapshots (`PANCAKENOTCH_SNAPSHOT_SETTINGS` for the card and its settings open).
