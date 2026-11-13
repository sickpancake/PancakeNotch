# The notch

How the notch is built, how a module's page is laid out, and the controls it uses. Read
[Foundations](foundations.md) first for colours and type, and [Motion](motion.md) for how things move.

- [States](#states)
- [Sizes come from the screen](#sizes-come-from-the-screen)
- [What a module provides](#what-a-module-provides)
- [The open panel](#the-open-panel)
- [Page patterns](#page-patterns)
- [Empty, waiting and error states](#empty-waiting-and-error-states)
- [Ears](#ears)
- [Peek strips](#peek-strips)
- [Controls](#controls)
- [Holding the notch open, keyboard and drags](#holding-the-notch-open-keyboard-and-drags)
- [Practice copies and snapshots](#practice-copies-and-snapshots)

## States

| State | What it is | Shape |
| --- | --- | --- |
| **Closed** | Exactly the camera cutout: pure black, invisible | No top ears, bottom corners 14 |
| **Compact** | The notch grows a spot on each side (the "ears") showing what's active | Top ears 6, bottom 14 |
| Compact + **peek** | A 24 pt strip hangs under the compact notch for a moment (a new song, Keep Awake stopped) | Bottom 16 |
| **Expanded** | The open panel, showing one module or Home | Top ears 18, bottom 26, shadow |

The outline is `NotchShape`, which flares out into the menu bar at the top ("ears" of the shape) and has
rounded bottom corners. `NotchView` morphs it between states with the springs listed in
[Motion](motion.md); with Reduce Motion it cross-fades instead.

In the UI the compact ears are called **"the spots beside the notch"**: #1 (left) and #2 (right), swappable.
Which module gets which spot is decided by the ear rules (`docs/ear-rules.md`), not by the module's view.

## Sizes come from the screen

Never hard-code a notch size or a Mac model. Everything comes from `NotchLayout`, built from the screen at
runtime:

| You need | Use |
| --- | --- |
| The open panel's size | `layout.bodySize(for: .expanded)` (up to 600 × 180; less on a narrow screen) |
| The hardware notch | `layout.geometry.notchRect` (its width is the dead zone, its height is the top band) |
| An ear's size | `layout.compactEarWidth` × `layout.geometry.compactHeight` |
| A peek strip | `layout.bodySize(for: .compact).width` × `NotchLayout.peekStripHeight` (24) |
| A taller panel | `notch.setPanelHeight(.medium)` (228) or `.tall` (360); it returns to normal when the notch closes |

Each module copies what it needs into its own small `…Layout` struct (see below), so views read
`layout.bandHeight` instead of reaching into the geometry everywhere.

## What a module provides

A module is a class conforming to `NotchModule` (`Sources/NotchCore/NotchModule.swift`). For its looks it
gives:

| Member | What it is |
| --- | --- |
| `title`, `symbol` | Name and SF Symbol for its tab, Home and VoiceOver |
| `menuStatus` | One short line for Home's All Modules widget ("Playing", "3 items"), or nil |
| `expandedView(layout:)` | The open page, laid out at the open body size |
| `compactEars(layout:)` | `CompactEars(main:extra:)`: the view for its spot, and optionally one for the other spot when it's the only active module |
| `peekView(layout:)` | The strip under the compact notch, or nil |
| `accessibilityStatus` | What VoiceOver says about it while the notch is closed or compact |
| `notchDidOpen()` / `notchDidClose()` | Start and stop anything that only matters while its page shows |

The other members (`isActive`, `waitsForYou`, `holdsOpen`, drag and key handling) decide behaviour; see
the doc comments in `NotchModule.swift` and the ear rules.

## The open panel

Every module page has the same two parts:

```
┌────────────────────────────────────────────────────────────────┐
│ [tabs ▸ module header]   ▓▓▓ hardware notch ▓▓▓   [right controls] │  ← top band, as tall as the notch
│                                                                  │
│   page content, 20 pt from each side                             │  ← starts 6–8 pt under the band
│                                                                  │
└────────────────────────────────────────────────────────────────┘     ← ~14 pt bottom padding
```

**The top band** runs beside the hardware notch and is exactly as tall as it.

- **Nothing may sit under the camera cutout.** Reserve it with `Color.clear.frame(width: notchWidth)`.
  The snapshot covers that area in black, so anything placed there visibly goes missing.
- **Left half:** the module tabs live here (`NotchModuleBar`, drawn by `NotchView`). Read
  `@Environment(\.notchModuleBarWidth)` and start any header text after it. When it's 0 (no tabs), the module
  may show its own name there (the Shelf shows "Shelf" then "4 items").
- **Right half:** the module's own band control, right-aligned: a mode switch (Timer · Stopwatch,
  Screen on · Can sleep), the source-app pill (Now Playing), or header buttons (the Shelf's "Clear all").
  Keep it to one small thing.

**The content** sits under the band with 20 pt side padding (18 in the Shelf) and fills the rest of the body.
It's laid out at its final size; the opening outline reveals it, so don't animate its size.

A module page usually looks like this:

```swift
/// Where things sit in the open panel (origin top-left, y down).
struct ExampleLayout: Equatable {
    static let sidePadding: CGFloat = 20
    static let bottomPadding: CGFloat = 14

    let body: CGSize
    let bandHeight: CGFloat
    let notchWidth: CGFloat

    init(_ layout: NotchLayout) {
        body = layout.bodySize(for: .expanded)
        bandHeight = layout.geometry.notchRect.height
        notchWidth = layout.geometry.notchRect.width
    }

    var bandSideWidth: CGFloat { max(0, (body.width - notchWidth) / 2 - Self.sidePadding) }
}

struct ExampleView: View {
    let module: ExampleModule
    let layout: ExampleLayout

    var body: some View {
        VStack(spacing: 0) {
            band
                .frame(height: layout.bandHeight)
                .padding(.horizontal, ExampleLayout.sidePadding)
            content
                .padding(.horizontal, ExampleLayout.sidePadding)
                .padding(.bottom, ExampleLayout.bottomPadding)
                .frame(maxHeight: .infinity)
        }
        .frame(width: layout.body.width, height: layout.body.height, alignment: .top)
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Example"))
    }

    /// Beside the notch: nothing on the left (the module tabs live there), one control on the right.
    private var band: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Color.clear.frame(width: layout.notchWidth)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                // one small control, right-aligned
            }
            .frame(width: layout.bandSideWidth)
        }
    }
}
```

`expandedView(layout:)` returns `AnyView(ExampleView(module: self, layout: ExampleLayout(layout)))`.

## Home

Home replaces the old Module Menu (ADR-0042). It's a grid of widgets, 6 columns × 2 rows a page, up to 3 pages,
in `Sources/NotchCore/Home/`. Sizes: small 1×1, medium 2×1, large 2×2. Cards (`HomeWidgetCard`) are white 0.06
(0.1 under the pointer when a click opens something) with a 0.06 hairline and 12 pt corners, 8 pt apart, 10 pt
padding, 18 pt from the panel's sides. A switched-off module's widget is a dashed `HomeGhost`. A small widget
with a reading uses `HomeSmallFace` (symbol and caption on top, value below), a plain one `HomeWidgetTile`.
A medium or large widget with a title row uses `HomeWidgetHeader` (symbol in a 14 pt column, name, optional
trailing count), and "nothing here" text is a `HomeWidgetEmptyLine`, centred in the room under the title.

The in-notch add picker (`HomeWidgetPicker`) fills the same grid area with a horizontal scrolling row,
without scroll bars. Each button shows a still, non-interactive default-size widget preview and a 10.5 pt
caption; its fill brightens from white 0.13 to 0.2 on hover, with shared press feedback. A 24 pt Back to Home
round button stays at the right. When no choices remain, a centred 11 pt, white 0.5 line reads “Every widget
is on Home”. The host owns insertion, Esc and the transition back to the grid.

Keep widgets of one size looking alike:

| | Small | Medium | Large |
| --- | --- | --- | --- |
| Value | 17 semibold | 19 semibold, caption 10 medium white 0.55, 1 pt apart | as Medium (a hero reading may be bigger) |
| Ring | 13, line 2 | 30, line 3 | — |
| Caption | 9.5 medium white 0.55, one line, cut off with "…", never shrunk | | |

A small caption must fit beside the symbol (about 9 characters): say "Battery", not "On battery", and leave it
out when the symbol already says it (an idle Stopwatch, the Clock).

- A module draws its widgets in `homeWidget(_:size:context:)`; `context.isLive` is true only while the open
  notch shows Home's visible page. Anything that ticks (a `TimelineView`, a progress bar) must pause when it's
  false. `context.isSnapshot` and `fixedNow` keep pictures still.
- A click on a card opens its module (`openedFromHome(_:)` picks a page, e.g. the Timer's stopwatch); buttons
  inside the card act on their own. Never read anything that could ask macOS for permission (Now Playing reads
  only what its center already knows).
- Home's vertical page stack follows precise trackpad deltas point for point inside the clipped grid area.
  At either end it gently resists further travel. Release settles to the nearest page with a quiet spring;
  a quick flick selects the adjacent page, never skipping one. Momentum cannot move the settle target.
  The dots and live widgets follow the predicted settle page; the other mounted page stays still.
  Only the current page and the neighbour being revealed are mounted during movement.
- Wheel steps (at most one every 0.3 s), arrow keys and page dots glide between pages. With Reduce Motion,
  pages cross-fade once per gesture. Editing retains its existing single-page turns and drag-to-dot paging;
  its drag owner stays mounted. Dots show only when there is more than one page.

## Page patterns

The open panel is wide and short (about 600 × 140 under the band). Lay things out side by side, not in tall
stacks. Reuse the closest existing pattern:

| Pattern | Used by | Shape |
| --- | --- | --- |
| **Picture + column** | Now Playing | A square on the left (art 64–112, corners 14, soft shadow), 18 pt gap, then a column: title (15 semibold), subtitle (12.5, white 0.6), then progress and controls at the bottom |
| **Status + actions** | Keep Awake, the running Timer | A dial or ring (64 pt, 4 pt line) on the left, 18 pt gap, a big status (19 semibold), a detail line (12 medium, white 0.6) and an optional note (10.5, white 0.45); `NotchPill`s on the right; a row of option buttons underneath |
| **List** | Agents, AI Usage | Rows 36–40 high with 10 pt inset: a mark or icon (22), a title (13 semibold) over a subtitle (11.5, white 0.6), and a status or buttons on the right. Hover fill white 0.08 in a 9 pt rounded rectangle when the row does something |
| **Tile row** | Shelf | Tiles 74 × 90, 6 apart, with the name under the picture; scrolls sideways when long |
| **Two panes** | Timer side by side | Two areas split by a 1 pt divider (white 0.1–0.12) with a little vertical padding |

Option buttons (Keep Awake's lengths, the Timer's presets) are small rounded rectangles: 26 high, corners 9,
white 0.11 (0.2 hover), 12 semibold monospaced digits. The current default has a faint outline
(white 0.28, 1 pt).

Text that might not fit uses `.lineLimit(1)` with `.truncationMode(.tail)` or a `.minimumScaleFactor(0.8)`,
and `ViewThatFits` to drop a less important part first (a shorter label, then nothing).

## Empty, waiting and error states

Every state gets a real design, and the page keeps the same shape across them so switching doesn't jump.

- **Nothing to show yet:** `PanelNote` (in ModuleAgents; reuse or move it to NotchCore): a quiet symbol
  (20 regular, white 0.4), a title (13 semibold) and one line (11.5, white 0.55), centred.
- **Same frame, empty content:** Now Playing with nothing playing keeps the art square (a grey gradient
  placeholder with a music note) and puts "Nothing playing", a line and a way to start music in the column.
- **Can't work here:** say why in plain words and offer the fix (a pill that opens the right System Settings
  page), never a dead control.
- **Waiting for the user** (an agent's question, a finished timer): make the action the prominent pill.

## Ears

An ear is `compactEarWidth` wide (notch height + 6) and as tall as the menu bar. That's tiny: show **one thing**.

- A symbol (12 semibold) at white 0.9 while active, 0.45 when dim; album art at corners 6; a ring 17 pt with a
  1.5 pt line; four sound bars 2.5 wide; or a short text (10.5 semibold, monospaced digits,
  `.minimumScaleFactor(0.8)`).
- Size text for its **widest** value (the Timer lays out for "10:00" before it reaches "9:59"), so the ear
  doesn't jump as it changes.
- Ears are hidden from VoiceOver; `accessibilityStatus` speaks for them.
- Don't animate the ear in or out yourself: `NotchView` slides ear content out from under the notch as it grows,
  tucks it back as it shrinks, and scales the old content away when a spot changes hands.
- Anything that moves in an ear (a ticking time, bars) runs only while the notch is compact and it can be seen.

## Peek strips

A peek is a 24 pt strip under the compact notch that shows for a moment, then goes. Show it with
`notch.peek(module, for: .seconds(…))`; it's ignored while the notch is open.

Layout: centred, 12 pt side padding, one line: an icon (10 semibold, white 0.6), a title (11 semibold, white)
and a detail (11, white 0.6). Wrap it in `ViewThatFits(in: .horizontal)` so the detail drops before anything
clips. Give it a single combined VoiceOver label.

## Controls

Shared ones live in `Sources/NotchCore/NotchControls.swift`. Use them.

| Control | Use it for | Look |
| --- | --- | --- |
| `NotchPill(title:symbol:prominent:action:)` | Text actions: "Turn Off", "+30 min", "Play" | Capsule, 24 high, 11 side padding, 11.5 semibold; symbol 9.5 bold; white 0.13 (0.2 hover), or white with black text when `prominent` |
| `NotchRoundButton(symbol:label:prominent:size:action:)` | Icon actions: start, pause, reset | Circle, 36 (or 24), symbol at 36% of size, bold; same fills as the pill; has a tooltip and label built in |
| `PressableStyle()` | Any custom button in the notch | Shrinks to 0.9 while pressed (dims to 0.6 with Reduce Motion) |
| `DrainingRing(plan:epoch:lineWidth:isSnapshot:now:)` | A countdown ring | White on a white 0.25 track, round caps, drawn by Core Animation |
| `.keyFocusRing(_:in:)` (ModuleShelf) | Showing which button Tab is on | White 0.9 ring, 1.5 wide, 3 pt outside |

Patterns that exist in more than one module but aren't shared yet. Match them exactly; if you need one in a new
module, move it into NotchCore and reuse it instead of making another copy:

- **Segmented switch** (Timer's mode, Keep Awake's screen switch, AI Usage's range): a capsule track (white 0.08,
  2 pt padding) holding segments 20 high with 10 pt side padding, 11 semibold; the selected one gets a white 0.18
  capsule and full-white text; others are white 0.6 (0.85 on hover). `.fixedSize()`, each segment `.isSelected`.
- **Header pill** (`ShelfPillButton`): a 22 high `NotchPill` without a symbol, for tight headers.
- **Status pill** (Now Playing's source app): 20 high, 8 pt padding, 11 semibold, white 0.6 text on a white 0.06
  capsule (0.95 / 0.12 on hover).
- **On/off icon toggles** (shuffle, repeat): dim white 0.45 when off; white on a white 0.16 circle when on.
- **Thin progress bar**: a 4 pt capsule track (white 0.12–0.18) with a white 0.92 fill; times either side at
  10.5 medium monospaced digits, white 0.55.

A control that can't work right now is **dimmed in place** (`.disabled` + `.opacity(0.3–0.4)`, reason in
`.help` and the VoiceOver hint) if hiding it would shift the layout, and **hidden** if the layout keeps
both sides balanced without it (Now Playing hides shuffle and repeat together).

## Holding the notch open, keyboard and drags

- A menu, popover, prompt or drag in progress must keep the notch from closing under it: return true from
  `holdsOpen` while it's up and call `notch.holdReleased()` when it ends. Menus are standard dark system menus.
- Keys go to `handleKey(_:)` while the notch has focus; give Tab a visible `keyFocusRing`.
- Clicking empty space in the panel shrinks the notch (the Shelf clears its selection first). Don't swallow those
  clicks with full-size invisible buttons.

## Practice copies and snapshots

Every module page has to be drawable without real data, for two reasons:

1. **The app window** shows a working "practice" notch on each module's card and in lessons (`NotchStage`,
   `PracticeKind` in `NotchArt.swift`). It uses pretend data and touches nothing real; any button that would act
   on the real Mac says so instead ("In your notch, this opens the app that's playing").
2. **Off-screen snapshots** (`PANCAKENOTCH_SNAPSHOT`) draw each state for design checks. Each module has a
   `…Snapshot.swift` listing its states (ears alone and beside others, each page state, each strip), wired into
   `AppDelegate.writeSnapshot`. Set `isSnapshot` so Core Animation views draw their SwiftUI stand-in, and use a
   fixed clock so pictures don't change between runs.

When you add a state to a page, add it to the snapshot too, render, and look at it.

## Editing Home in the notch

Hold Home's widget area for half a second to edit, including the gaps or the empty Home note. A short
click keeps its usual action. While editing, Home stays open, takes keyboard focus and draws every
widget with a still context. Gentle independent wiggles stop when hidden, when dragging, or with
Reduce Motion. The shared `HomeWiggle` modifier returns cards to level when disabled.

The band replaces Settings and Edit with Add (Back while choosing a widget) and a prominent Done pill.
Outside editing, Edit beside the gear opens the window's Home editor. Compact icons leave room for
the one-time intro hint. The hardware notch remains clear.

Each widget has the window editor's minus badge at its top-left corner and a size capsule at the
bottom right. Click the size capsule to step through supported sizes. A private drag lifts immediately;
a dashed outline shows the drop and neighbours preview the same `HomeLayout` edit used on release.
The gesture owner stays mounted across previews and page turns. Page dots include one empty destination
while editing; drag into the dot gutter to change pages. Changes save immediately through HomeSettings.
A refused edit shows a short fading note. VoiceOver offers removal, four move directions, sizes and pages.

Done, Escape, an outside mouse-down, losing keyboard focus, selecting a module, hiding or closing the
notch all end editing and release its hold. An attention request ends editing and selects its module.
Outside-click monitors exist only for the edit session; there is no polling or clipboard drag.
