# Ear rules

The **ears** are the two spots that grow beside the closed notch (the Compact state). This page is the reference
for which module shows there and where. In the app and in Help they're called the "spots beside the notch":
**#1** is the first spot (left) and **#2** the second spot (right). Users read the plain-English version in Help,
under [What shows beside the notch](https://sickpancake.github.io/PancakeNotch/help/#beside-the-notch).

The logic lives in `NotchViewModel.ears(layout:)` and `activityChanged()` (`Sources/NotchCore`), driven by each
module's `isActive`, `prefersFirstEar` (arrives with Keep Awake), `prefersSecondEar`, `opensFromEar` and
`compactEars(layout:)`. Tests:
`EarRulesTests`, `NotchModulesTests` and `SecondEarTests` (NotchCoreTests), `NowPlayingEarTests`, and each module's
own tests. If you change a rule, change this page, Help and the tests together.

## When the ears are out

1. The notch rests in Compact while **any module is active**; otherwise it's closed, plain black.
2. It's also Compact, whatever is active: after a click shrinks the open panel (it stays Compact until a click on
   the open panel, Esc or the shortcut closes it; a click on the shrunk notch opens it again), for ~1.5 s after a
   Shelf drop, and while a peek strip shows under the notch.
3. Switched-off modules never get an ear. A module's own "beside the notch" setting keeps it out of the ears too,
   except for the shrink after a click, which shows the module the open notch last showed anyway (ADR-0013's Shelf
   rule, applied to every module). While the notch hides (full screen, Mission Control), the ears hide too.

## When each module is active

| Module | Active while | Turned off by |
| --- | --- | --- |
| Now Playing | a song plays, or is paused until you switch to another module; it comes back when the notch opens on Now Playing or the song plays again | "Show album art and sound bars beside the notch" |
| Shelf | it holds 15 items or more ("!" at 20, full); also briefly after a drop | "Show the Shelf's count beside the notch" |
| Agents | a thread works or needs you, or finished, was stopped or failed and you haven't looked yet | no ear setting; switch Agents off or hide its tools |
| AI Usage | the followed limit is under 10% left ("When close", default), or always once there's a reading ("Always") | "Beside the closed notch": Never |
| Timer | a timer or stopwatch runs, is paused, or is stopped but not reset; **always while Done** | "Beside the notch": Don't show (Done still shows) |
| Keep Awake | it keeps the Mac awake | turning Keep Awake off |

## Who gets which ear

4. The candidates are the active modules (plus the brief after-drop Shelf), in the user's order from the Modules
   page. Modules with no ear content are skipped.
5. With no candidates, the module the open notch last showed appears, but only for the shrink after a click. A peek strip with nothing
   active shows no ears.
6. Normally the **top two by rank** take #1 and #2. Others wait and show once a spot frees up.
7. **Set spots:**
   - Keep Awake takes **#1** (`prefersFirstEar`).
   - The Timer takes **#2** on "Second spot" (the default) and always while Done (`prefersSecondEar`). On
     "By order" it ranks like any other module.
   - The after-drop Shelf count, when the Shelf isn't active on its own (under 15 items), borrows **#2**.
   - The other spot goes to the best-ranked other candidate. If two modules ask for #2, the better-ranked one
     gets it, and the other can still take #1 when Keep Awake doesn't and it outranks the remaining candidates.
     Keep Awake and the Timer together fill both spots.
8. **A module alone:** one with an extra view fills both ears (Now Playing: art in #1, sound bars in #2). A #2
   module (the Timer on "Second spot" or while Done) stays in #2 and leaves #1 empty. Any other module takes #1.
9. **Two showing:** each shows only its main view (Now Playing drops its sound bars).
10. **Swap sides** flips left and right for everything, including a lone module's two views.

## Opening from the ears

11. Hovering (unless "Open on click only" is on) or clicking the ear of a module with `opensFromEar` (Timer, Keep
    Awake) opens the notch on that module. Elsewhere it opens on the best-ranked module that wants focus (music
    playing, an agent that needs you, a finished timer), else on the module used last.
12. Peek strips are separate: a strip never changes who holds a spot.
