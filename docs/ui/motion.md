# Motion

Motion is a big part of how PancakeNotch feels. The notch doesn't switch between pictures: it grows, slides and
settles like one soft, physical object. Almost every change on screen is animated: things appearing, things
leaving, numbers changing, icons swapping, a selection moving, a panel getting taller. New UI should move the same
way, using the curves and transitions on this page. Read [Foundations](foundations.md) first.

- [What the motion feels like](#what-the-motion-feels-like)
- [What should move](#what-should-move)
- [The curves](#the-curves)
- [The transitions](#the-transitions)
- [How to wire it up](#how-to-wire-it-up)
- [Layout while moving](#layout-while-moving)
- [Continuous motion](#continuous-motion)
- [Timing, order and interruptions](#timing-order-and-interruptions)
- [Reduce Motion](#reduce-motion)
- [Checking motion](#checking-motion)

## What the motion feels like

1. **Fluid, not flashy.** Springs that settle quickly with little or no overshoot (damping 0.8–1.0). Nothing
   bounces for fun; the one bounce in the app (Shelf's count after a drop) is a tiny reward for an action.
2. **Short.** Most motion is 0.15–0.3 s. Opening the notch is the longest common move, and it's under half a
   second. Anything slower than 0.4 s needs a reason (a gauge refilling once, a recording dot pulsing).
3. **It comes from somewhere.** Things grow from the notch, from the button that opened them, or slide in from
   the side they live on. Home grows from the top-left where its button is, and its pages slide up or down (a cross-fade with Reduce Motion); the AI Usage menu from the
   top-right; panel content grows down from the notch.
4. **Direction means something.** Moving to a module further right slides the new page in from the right; a
   countdown's digits roll down, a stopwatch's roll up; Timer slides left, Stopwatch slides right.
5. **Soft edges.** Bigger swaps add a small blur (5–10 pt) while fading, so two pages never look like a muddy
   double image halfway through.
6. **It never blocks.** Every animation can be interrupted: hover away mid-open and the notch turns around from
   where it is. Nothing waits for an animation to end before it accepts the next click.

## What should move

If it changes on screen, it should animate. Before you finish, check each change in your UI against this list:

| Change | How it moves |
| --- | --- |
| A view appears or disappears | A transition (below), never a hard cut. `.opacity` at the least |
| One piece of content replaces another (new song, new page, new state) | `.id(…)` on the content plus a transition, so the old one leaves and the new one arrives |
| Text changes in place | `.contentTransition(.opacity)`, or the 3 pt rise for something new arriving (a new song title) |
| A number changes | `.contentTransition(.numericText())` (with `value:` when you know the direction), digits `.monospacedDigit()` |
| An SF Symbol changes (play → pause, off → on) | `.contentTransition(.symbolEffect(.replace))` |
| A selection moves (tab, segment) | The highlight glides: `matchedGeometryEffect` in a `@Namespace` |
| Something grows or shrinks (panel height, progress, a gauge) | The size or value animates; custom shapes and gauges conform to `Animatable` |
| Rows are added, removed or reordered | Each row `.transition(.opacity)`, and the list animates on its list of IDs |
| A section opens or closes | The rows fade, a chevron turns 90° |
| Hover | Fill or text brightness steps up, 0.15 s |
| Press | `PressableStyle` (notch) or the pill styles (app window) |

Two things are deliberately instant: **switching pages in the app window's sidebar** (it behaves like any Mac
window) and **the closed notch at rest** (it must look like the hardware).

## The curves

Use these. Don't invent a new duration or damping when one here is close.

### Notch

| Name | Curve | Used for | Reduce Motion |
| --- | --- | --- | --- |
| Open | `NotchViewModel.animation(opening: true)`: `.spring(response: 0.42, dampingFraction: 0.8)` | The notch opening or waking into compact | `.easeInOut(duration: 0.2)` |
| Close | `NotchViewModel.animation(opening: false)`: `.spring(response: 0.45, dampingFraction: 1.0)` | Closing; no overshoot so it tucks cleanly into the hardware | `.easeInOut(duration: 0.2)` |
| Switch | `NotchViewModel.switchAnimation`: `.spring(response: 0.32, dampingFraction: 0.86)` | Changing module, opening Home, pages inside a module (Timer ↔ Stopwatch) | `.easeInOut(duration: 0.15)` |
| Tall | `NotchViewModel.tallAnimation`: `.spring(response: 0.28, dampingFraction: 0.88)` | The panel growing to a taller height and back; quicker because it follows a click | `.easeInOut(duration: 0.15)` |
| Tabs | `.spring(response: 0.3, dampingFraction: 0.85)` | The tab highlight gliding, the tab bar changing | `.easeInOut(duration: 0.15)` |
| Ear swap | `.spring(response: 0.35, dampingFraction: 0.85)` | One module's ears replacing another's | `.easeInOut(duration: 0.15)` |
| Small pop | `.spring(response: 0.3, dampingFraction: 0.75)` | A small icon appearing in an ear (the paused symbol) | `.easeInOut(duration: 0.2)` |
| Press | `.spring(response: 0.2, dampingFraction: 0.6)` | Button scale on press (inside `PressableStyle`) | `.easeOut(duration: 0.1)`, dims instead |
| Hover | `.easeOut(duration: 0.15)` | Hover fills, brightening text, drop targets lighting up | same |
| Fade | `.easeInOut(duration: 0.2)`–`0.25` | Small state changes inside a page (a status line, rows coming and going) | same, or `nil` |
| Content change | `.easeInOut(duration: 0.3)`–`0.35` | A new song's text, new album art cross-fading | `.opacity` only |
| Glide | `.linear(duration:)` matching the update interval | Smoothing between regular updates: the progress bar between once-a-second ticks (1 s), sound bars between level updates (0.05 s) | `nil` (jump) |

Big notch moves (open, close, switch, tall) are triggered from `NotchViewModel` with `withAnimation(Self.…)`.
In a module, reuse those statics instead of copying their numbers, so a later tweak changes everything at once.

### App window

| Curve | Used for | Reduce Motion |
| --- | --- | --- |
| `.snappy(duration: 0.22)` | Switches flipping, segments and chips changing (built into the controls) | `nil` |
| `.snappy(duration: 0.2)`–`0.25` | Reordering modules, starring a favourite, a slider jumping to its recommended value | `nil` |
| `.easeOut(duration: 0.15)` | Hover on rows, sidebar items and pills | `nil` |
| `.easeInOut(duration: 0.25)` | Card sections opening (Settings disclosure), a module card's rows when it's switched on or off, dismissing a Home box, onboarding steps | `.easeInOut(duration: 0.15)` |
| `.easeInOut(duration: 0.3)` | The welcome handing over to the main window; the big Home switch | `0.15` or `nil` |
| `.easeOut(duration: 0.3)` | Numbers and bars updating (Statistics, Home stat tiles) | `nil` |

## The transitions

| Name | What it does | Where | Code |
| --- | --- | --- | --- |
| **Blur reveal** | Fades in from a 10 pt blur while stretching down from the notch (y 0.6 → 1, anchored at the top) | The open panel's content when the notch opens | `NotchView.swift` (`blurReveal`) |
| **Module switch** | The new page slides in 34 pt from its side with a 6 pt blur; the old one blurs and shrinks to 0.97 *in place* | Changing module | `NotchView.swift` (`moduleSwitch(forward:)`) |
| **Menu reveal** | Grows from 0.96 at the top-left corner with a 5 pt blur | Home | `NotchView.swift` (`menuReveal`) |
| **Page slide** | `.opacity` + 24 pt sideways offset, direction from the page's place | Pages inside one module (Timer ↔ Stopwatch) | `TimerView.swift` (`pageTransition`) |
| **Rise** | `.opacity` + 3 pt upward offset | New text arriving in place (song title and artist) | `NowPlayingView.swift` |
| **Grow from anchor** | `.opacity` + `.scale(0.96, anchor: <where its button is>)` | Small menus and popovers inside a page (AI Usage's menu) | `AIUsageView.swift` |
| **Ear grow** | `.scale(0.5)` + `.opacity` | Ear content changing hands | `NotchView.swift` (`CompactEarsView`) |
| **Ear tuck** | Ears slide in under the notch (`offset` of ear width + 8) as it closes, then fade after 0.3 s | Compact → closed | `NotchView.swift` (`CompactEarsView`) |
| **Fade** | `.opacity` | Everything small: rows, notes, badges, status text, states inside a page, all Reduce Motion fallbacks | everywhere |

Rules behind them:

- **Leaving things don't travel.** A page that's going away blurs and fades where it is; only the arriving page
  slides. That way a quick change of direction never sends the old page the wrong way.
- **Pick the direction from order.** `NotchViewModel.switchedForward` says whether the new module is to the right
  of the old one; do the same for pages within a module.
- **Anchor scales where the thing came from** (`anchor: .topLeading` for something opened from the top-left).
- **Small things just fade.** Slides and blurs are for whole pages and menus. A row, a badge or a hint uses
  `.opacity`.
- To add a new kind of transition, build it like the ones in `NotchView.swift`: an `AnyTransition.modifier`
  with a small `ViewModifier` for the active and identity states. Reuse `SlideBlurModifier`'s values before
  inventing new ones, and ask the maintainer before adding a new style.

## How to wire it up

**Pick one of three ways, depending on where the change comes from:**

1. **A big, model-driven change** (open, switch, taller panel): change the state inside `withAnimation(...)` in
   the model, with the shared curve:

   ```swift
   withAnimation(NotchViewModel.switchAnimation) { mode = .stopwatch }
   ```

2. **A local change in one view** (hover, a status changing, a list updating): attach `.animation(_:value:)` to
   the smallest view that changes, always with a `value:`. Never use `.animation(_:)` without a value; it
   animates everything around it, including things you didn't mean to.

   ```swift
   .animation(.easeOut(duration: 0.15), value: isHovered)
   ```

   To animate only one property, use the scoped form: `.animation(curve) { $0.opacity(isShown ? 1 : 0) }`.

3. **Content that replaces other content**: give it an identity and a transition, and animate on that identity:

   ```swift
   TrackText(track: track)
       .id(track.identity)
       .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 3)))
       .animation(.easeInOut(duration: 0.3), value: track.identity)
   ```

**The other tools:**

- **Text, numbers and symbols** change in place with `.contentTransition(…)`: `.numericText(value:)` for counts
  (Shelf's badge), `.symbolEffect(.replace)` for icons, `.opacity` for other text. Put a `.animation(…, value:)`
  or `withAnimation` next to it, or the content transition won't play.
- **A gliding selection**: one highlight shape with `matchedGeometryEffect(id: "selection", in: namespace)`,
  drawn only behind the selected item. Turn the effect off with Reduce Motion (see `SelectionSlide` in
  `NotchModuleBar.swift`).
- **Custom shapes and gauges** animate smoothly when they're `Animatable`: expose the changing numbers as
  `animatableData` (`NotchShape` animates its corner radii this way; AI Usage's `RefillRing` its fill and colour
  together). This is how to animate a value without a timer.
- **Rolling digits**: use Timer's `DrumText` for clocks rather than writing another one.
- **Async sequences** (wait, then animate): use `Task.sleep`, check `Task.isCancelled`, and pass `nil` as the
  animation when cancelled so the final state shows at once (see `countUpAfterDrop` in `ShelfView.swift`).

## Layout while moving

- **Lay out at the final size; reveal by clipping.** The open panel's content is built at the panel's full size
  and the growing `NotchShape` clip uncovers it, so text never re-wraps mid-animation. Don't make a view's size or
  font depend on an animating value.
- **Keep the shape steady across states.** Space for a button that comes and goes is kept (dim it or fade it)
  rather than collapsing, so nothing beside it jumps. Now Playing keeps its art square even with nothing playing.
- **Animate `opacity`, `offset`, `scaleEffect` and `blur`**, which are cheap and don't change layout. Avoid
  animating `frame` sizes of things with text inside.
- **Use `ViewThatFits` or fixed widths for text that changes** (digits with `.monospacedDigit()`), so a
  changing number doesn't push its neighbours around every tick.

## Continuous motion

Things that move all the time (the draining ring, the sound bars) must not wake the app on every frame.

- **Core Animation, not SwiftUI.** Draw them with a `CALayer` in an `NSViewRepresentable` and hand the window
  server one long animation (`CABasicAnimation` / `CAKeyframeAnimation` with a duration or `repeatCount =
  .infinity`). See `DrainingRing.swift` and the sound bars in `NowPlayingEars.swift`.
- **Stop when not visible**, and remove the animation when the state changes (paused, finished, closed).
- **Snapshot stand-in.** Off-screen snapshots can't draw Core Animation layers, so each has a plain SwiftUI
  version when `isSnapshot` is true.
- **Glide, don't tick.** When a value updates on a schedule (once a second, 30 times a second), animate linearly
  over the gap between updates so it looks continuous (Now Playing's progress bar, the sound bars). Check that
  the jump is a normal step first; after a seek, jump straight there.
- A SwiftUI `.repeatForever` is acceptable only for a tiny indicator that lives briefly and only while visible
  (the recording dot in the shortcut recorder). Nothing that stays on screen.
- No `Timer`, `DispatchSource` or polling loops to drive animation. `TimelineView(.animation(paused:))` is fine
  for short bursts, paused the rest of the time (`DrumText` runs it only while a digit rolls).

## Timing, order and interruptions

- **Mostly no delays.** Things start moving the moment the person acts. The few delays in the app have a
  reason: the ears wait 0.3 s to fade so their slide under the notch stays visible; Shelf's count waits 0.3 s
  after a drop so the eye has landed on it; AI Usage's refill ring waits 0.25 s after it appears.
- **Things that leave by themselves give people time.** A few seconds by default, longer while VoiceOver is on
  (`NSWorkspace.shared.isVoiceOverEnabled`), and they end early once what they offer no longer makes sense. Use a
  cancellable `Task.sleep`, never a `Timer`.
- **One thing leads.** When several things change at once, put them in the same `withAnimation` so they move
  together, rather than chaining completions.
- **Springs over fixed curves for moves**, because a spring that is interrupted carries its speed into the new
  target instead of snapping. Fixed ease curves are for fades and hover.
- **Never depend on an animation finishing.** No `DispatchQueue.main.asyncAfter` to "clean up after the
  animation"; if you need to know, use `withAnimation(_:completionCriteria:_:completion:)` and make the
  completion safe to skip.

## Reduce Motion

Read it with `@Environment(\.accessibilityReduceMotion)` in views, or
`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` in models. Every animation in this guide has a
Reduce Motion version, and new ones need one too:

| Normally | With Reduce Motion |
| --- | --- |
| Slide, scale, blur, grow, rise transitions | `.opacity` |
| Springs | `.easeInOut(duration: 0.15)`–`0.2` |
| The notch outline morphing between states | A cross-fade between the states (`NotchView` swaps them by `.id(state)`) |
| Gliding selection (`matchedGeometryEffect`) | The highlight just moves (effect off) |
| Press scale | Dim to 0.6 |
| Rolling digits | Cross-fade (`DrumText`'s `fade`) |
| Dancing sound bars, pulsing dot | A still pose |
| Ears tucking under the notch | Fade only |
| App window controls (`snappy`) | `nil`: change instantly |

Write the choice right where the animation is, so the two stay together:

```swift
.transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(x: forward ? 24 : -24)))
.animation(reduceMotion ? .easeInOut(duration: 0.15) : NotchViewModel.switchAnimation, value: mode)
```

## Checking motion

The off-screen snapshots show where each animation starts and ends, not the movement itself, so check the
motion in three steps:

1. **Both ends on the sheet.** Add the before and after states to the module's `…Snapshot.swift` and look at
   them in `snapshot.sh`'s pictures. If the two ends have different layouts (things jump sideways, text
   re-wraps), the animation between them will look wrong.
2. **Read your diff against this page.** For every `if`, `switch`, `ForEach` and changing value in your views:
   does it have a transition or `.animation(_:value:)`, from the tables above, with a Reduce Motion version?
3. **Describe the motion in your summary** ("the note fades up 3 pt when it changes; Clear fades the text out
   with the Fade curve"), so the maintainer knows what to look for when they try it in the real app.
