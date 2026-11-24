---
name: verify-ear-opening
description: Verify ear and opening usability when changing EarAllocator, earConfiguration, NotchViewModel ear targeting or opening selection, or a module's compact ear adapter. Exhausts bounded inputs on production Swift and checks real-source mutations.
---

# Verify ear and opening usability

Promise: waiting alerts stay visible, logical spots and extra views obey the ear rules, and activating an ear or strip opens the feature it shows while untargeted opening respects the Home and music rules.
Harm: a user misses an alert, loses a familiar ear, or opens the wrong feature.

## Run from a checkout of PancakeNotch

```sh
./scripts/verify-ear-opening.sh
```

To prove sensitivity after changing a covered function or this verification:

```sh
./scripts/verify-ear-opening.sh --mutations
```

Use an isolated worktree for mutations. The second command temporarily changes real product source, rebuilds it, requires the named property to fail, restores the exact original bytes after each case, and reruns the passing checks at the end. It never intentionally leaves a product fix or mutation behind. It creates recovery copies before making any change and prints their system temporary directory. Do not run concurrent edits or builds in that worktree. SIGINT and SIGTERM restore the active mutation; after a forced kill, use the printed recovery copies before continuing.

The checker uses Swift Testing on the actual Swift implementation, plus the Python standard library to drive and inspect mutation runs. There is no hand-written state-transition model or additional app dependency. This is bounded exhaustive execution, not an unbounded theorem or a proof of AppKit input delivery. The refactored selector is synchronous and deterministic, so real-code enumeration avoids a separate model drifting from that selector.

Validated toolchain: Apple Swift 6.4 (`swiftlang-6.4.0.34.1 clang-2100.3.34.1`) with the SDK chosen by `scripts/swift.sh`, and Python 3.9.6. Swift Testing ships with that toolchain. Use the wrapper, never Xcode. The command supplies an in-checkout compiler cache and disables SwiftPM's manifest sandbox, which is incompatible with the enclosing agent sandbox here. Restricted agent sessions may need tool approval for the tests' macOS service access. No visible app, real pointer movement, music playback, or power assertion is requested. All run logs are written to a fresh system temporary directory.

## Coverage and bounds

The last source correspondence review's commit, toolchain and exact source SHA-256 values are in `verification/ear-opening/coverage.json`. A mismatch prints COVERAGE DRIFT: reread the changed source before claiming the pass still guards the intended policy. Move the sync commit and hashes forward only after checking this correspondence and rerunning the sensitivity checks.

- `Sources/NotchCore/EarAllocator.swift`: `choose`, `place`, `allocate`. `EarAllocatorTests` compares the pre-refactor algorithm over 576,240 four-candidate cases. `EarUsabilityVerification` separately checks policy invariants over 552,960 six-module cases: all 720 ranks; music/Shelf/Keep Awake/AI Usage inactive or active; Agents inactive/working/waiting; Timer inactive/by-rank/second/Done; Shelf brief badge on/off; swapped sides on/off. Only Now Playing has extra content in this six-module domain. IDs are unique. The general four-candidate domain also covers multiple first/second claims and optional extra content.
- `Sources/NotchCore/NotchViewModel.swift`: `earAllocation`, `ears`, `moduleUnderPointer`, `tap`, `open`, `chooseModuleForOpening`, `modulesChanged`, `closeThroughCompact`, `peek`. `OpeningUsabilityVerification.openingPriorityTable` runs 6,480 actual opening decisions: six ranks of music/Agents/Timer; music playing/paused/empty; four waiting combinations; all three navigation modes; both Home preferences; each remembered module; automatic, three explicit, and disabled explicit targets. The test doubles declare focus/idle state; the real music module is checked by the existing SongFocusTests.
- `OpeningUsabilityVerification.eventOrdersKeepPointingAndOpeningInAgreement` replays every sequence of length zero through three over seven events (400 traces, including repetition): Agents waits, Timer Done, Shelf badge, swap sides, reverse rank, remove Agents, show song strip. Each trace is reconstructed separately before probing left ear, right ear, center, and the strip when present. It compares real rendered ownership, real targeting, and real tap/open results. Active modules and default navigation are fixed for this domain; settings combinations are handled by the separate priority table. A state mutation plus `activityChanged()` is one synchronous MainActor segment, like the production callback. The Shelf badge event includes open/queue-badge/close as a setup macro; this check does not explore interruption between those three calls.
- `Sources/NotchCore/NotchModule.swift` and all seven migrated adapter classes (the six modules plus ShelfPreviewModule): `EarModuleContractVerification` instantiates the real modules using temporary/practice data and checks that each declaration matches its actual main/extra content and default placement. It catches an adapter forgotten during the protocol migration.
- `EarRenderingTests` checks absent content, rank changes, swapped targeting, no view construction during targeting, only chosen owners constructing views, and a lone owner's two views sharing one construction.
- Existing `OpeningChoiceTests`, `EarRulesTests`, `FirstEarTests`, `SecondEarTests`, `NotchModulesTests`, `HomeReplayNotch`, `SongFocusTests`, `NotchClickOnlyTests`, `NowPlayingEarTests`, `KeepAwakeEarTests`, and `TimerModuleTests` cover the named histories, real music yield/pause/stop behavior, callback balancing, Home/Tabs behavior, hover cancellation, click-only behavior, and module-specific settings. These are regression tests, not an exhaustive exploration of asynchronous scheduling.

Each generated failure prints the input state or event trace in PancakeNotch terms. Preserve that trace as a focused replay if it identifies a real bug. If the trace only fails because the input violates a module contract, establish that from the production code; distinguish a verification error from a product finding. Never weaken an agreed property merely to get a pass. Report product findings without changing product code unless the user asks for a fix.

## Prove the checks can fail

`--mutations` performs thirteen independent real-source experiments; each must compile, fail a test with the intended property name, and restore before the next experiment:

| Deliberate break | Required detector |
| --- | --- |
| Put ordinary activity ahead of waiting alerts | WAITING_VISIBLE |
| Select only one owner | CAPACITY |
| Ignore Swap sides | SWAPPED_SIDES |
| Drop a lone song's extra view | LONE_CONTENT |
| Reverse ranked owners before placement | RANKED_SIDES |
| Ignore a first-spot claim | FIRST_PLACEMENT |
| Ignore a second-spot claim | SECOND_PLACEMENT |
| Stop targeting ears | POINTED_OWNER |
| Treat strip coordinates as ears | POINTED_OWNER |
| Ignore an explicit opening target | OPENING_DESTINATION |
| Ignore waiting alerts when opening | OPENING_DESTINATION |
| Remove the idle Now Playing → Home fallback | OPENING_DESTINATION |
| Remove the real Agents adapter's ear declaration | MODULE_CONFIGURATION |

An anchor mismatch means the covered source changed. A compiler failure, missing test output, or failed detector is not a successful mutation catch. Read the saved log, update the verification after reviewing the source, and rerun. Final PASS requires the restored production code to pass all three phases again.

## Limits and maintenance

This check does not verify visual quality, VoiceOver announcements, physical hover hit testing, full-screen/window-controller delivery, multi-screen geometry, memory/CPU budgets, arbitrary time/animation overlap, every asynchronous event order, or behavior outside the input domains above. Synthetic geometry is used; no screen permissions are required. Existing tests cover more individual cases but do not turn those exclusions into a proof. Run CI and separately approved live interaction/performance checks before claiming complete usability preservation.

For changes that skipped this check, use `/maintain-formal-verification-skill` if available, or explicitly repeat the source correspondence review, update the bounds/tests/mutation anchors as needed, and advance the sync record only after verification passes again.
