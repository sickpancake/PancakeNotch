# AGENTS.md — PancakeNotch

Guidance for AI coding agents (Claude Code, Codex, Cursor, …) working in this repo.

## What this is

PancakeNotch: a free, GPL-3.0, native macOS app that turns the MacBook notch into a Dynamic
Island–style surface. Its differentiator is being **lightweight and measured**.
Start with [`CONTEXT.md`](CONTEXT.md) (pitch, glossary, constraints) and the ADRs in `docs/adr/`.
ADRs are the source of truth for product and architecture decisions.

## Working with the maintainer

- The maintainer is **vibe coding** and is not a professional developer. Explain choices in plain
  language, avoid unexplained jargon, and do the technical work (building, testing, measuring)
  yourself rather than asking them to.
- They do **not** use Xcode. Never require it; everything must work with the Command Line Tools.
- When several decisions are needed, batch them as multiple-choice questions with a recommended option.
- Product decisions are theirs. If a change contradicts an ADR, ask first, then record the outcome.

## Commands

```sh
swift build                         # debug build
swift test                          # Swift Testing unit tests
./scripts/build-app.sh [debug|release]   # assembles build/PancakeNotch.app (ad-hoc signed)
open build/PancakeNotch.app         # run it (accessory app: no Dock icon)
./scripts/check-memory.sh [app] [settle-secs] [limit-MiB]   # idle memory gate, default 30 s / 50 MiB
pkill -x PancakeNotch               # stop it
log stream --predicate 'subsystem == "io.github.sickpancake.PancakeNotch"'   # app logs
```

Environment switches:
- `PANCAKENOTCH_SIMULATE_NOTCH=1` fakes a notch on screens without one (CI VMs, external displays).
- `PANCAKENOTCH_DEBUG_STATE=compact|expanded` starts pinned in that state (ignores hover).
- `PANCAKENOTCH_SNAPSHOT=/path/out.png` renders every notch state off-screen to a PNG and quits.

To see UI changes, prefer the off-screen snapshot (no window appears, no permissions needed):
`swift build && PANCAKENOTCH_SNAPSHOT=out.png .build/debug/PancakeNotch`, then inspect the image.
**Don't launch the app on the maintainer's screen while they're working** unless they agree; the
real-window run and memory gate happen in CI. (`screencapture` also needs Screen Recording
permission for the terminal, which isn't granted.)

## Layout

```
Package.swift             SwiftPM only — there is no .xcodeproj (ADR-0014)
Sources/PancakeNotch/     app target: entry point, AppDelegate, wiring
Sources/NotchCore/        notch geometry, window, state machine, module protocol
Sources/Module*/          one target per module (added per milestone: Shelf M2, NowPlaying M3)
Tests/                    Swift Testing tests
Resources/Info.plist      bundle metadata (LSUIElement, min macOS 15)
scripts/                  build-app.sh, check-memory.sh
docs/adr/                 architecture decision records
```

## Hard rules

1. **Memory:** < 50 MB idle, < 100 MB peak, physical footprint (ADR-0006). Run
   `scripts/check-memory.sh` after meaningful changes. The Now Playing helper process counts too.
2. **CPU:** ~0% idle. No timers or polling loops; use notifications, callbacks, `AsyncStream`.
   Animations and observers must stop when the notch is closed or the module is hidden.
3. **Dependencies:** only those in ADR-0003 (Sparkle, mediaremote-adapter, KeyboardShortcuts).
   Anything else needs a new ADR and the maintainer's approval.
4. **Swift 6** language mode, strict concurrency. UI code is `@MainActor`. Must also build with the
   Swift 6.x toolchain on the `macos-15` CI runner, so avoid APIs/features newer than macOS 15
   unless gated with `#available`.
5. **macOS 15+, Apple Silicon only, built-in display only** (ADR-0007, 0021).
6. **Look:** pure monochrome black/white/gray, SF Pro + SF Symbols; album art is the only color
   (ADR-0029). The closed notch must be pure black and match the hardware cutout exactly.
7. **Accessibility:** VoiceOver labels on all controls; Reduce Motion → cross-fades.
   User-facing strings via `String(localized:)`.
8. **Privacy:** no telemetry or network calls except the Sparkle update check (ADR-0016).
9. **Notch geometry** always comes from `NSScreen` at runtime; never hard-code sizes per model.
   Recompute on `NSApplication.didChangeScreenParametersNotification`.

## Recording decisions

When the maintainer settles something new, add `docs/adr/NNNN-short-title.md` (Status, Decision,
and Context/Consequences when useful) and add a row to the decision log in `CONTEXT.md`.
Amend an existing ADR instead when refining it, noting the amendment date.

## Milestones

See ADR-0024. Current: **M1** (notch window + Closed/Compact/Expanded states) in progress on `m1-notch-window`.
