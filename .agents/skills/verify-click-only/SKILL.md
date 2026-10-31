---
name: verify-click-only
description: Verify click-only notch opening when changing NotchBehavior, NotchViewModel hover scheduling, preference wiring, or Notch settings and previews. Checks pending open cancellation and preservation of pending closes.
---

# Verify click-only notch opening

Promise: with Open on click only enabled, hovering cannot expand the notch, including a hover queued before enabling it. Changing this setting must not cancel a pending close.
Harm: the panel opens accidentally after the user disables hovering, or stays open after the pointer leaves.

## Run

Use the project's `scripts/swift.sh`, not plain Swift.
With TLC 1.7.4's jar in `TLA2TOOLS` and a Java binary in `JAVA`, run from the repo root:

```sh
./scripts/verify-click-only.sh
```

The script checks the pinned jar's SHA-256, runs real Swift tasks and isolated preference persistence tests, copies the model into a fresh system temporary directory, and runs TLC with one worker. It does not launch a visible app. Set `TLA2TOOLS` to the absolute jar path and `JAVA` to an installed Java executable before running. TLC 1.7.4 is available from the official tlaplus/tlaplus GitHub v1.7.4 release; SHA-256 is `936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88`. Validated runtime: Eclipse Temurin 25.0.5+8, macOS aarch64. These are development tools, never app dependencies.

Read every TLA+ result with `/statechart`: copy `verification/click-only/ClickOnly.tla`, `ClickOnly.cfg` and `view.mjs` into a scratch folder outside the repo, then follow that installed skill to check and render it to a new output folder. Do not copy commands from an older statechart installation. Inspect every invariant result and shortest path. The ordinary passing model reaches 9 states and 37 steps, with all three invariants holding.

## Coverage and correspondence

- `Sources/NotchCore/NotchState.swift`: `NotchBehavior.openOnClickOnly` (default false).
- `Sources/NotchCore/NotchViewModel.swift`: `behavior.didSet` → `ChangeSetting`; `hoverChanged` → `Enter`/`Leave`; `schedule` → `DelayEnds`; opening branch of `tap` → `Click`; `close`/`reset` → `Close`.
- `Sources/PancakeNotch/Settings/Preferences.swift`: default, saved value and `notchBehavior` mapping; covered by `Tests/PancakeNotchTests/PreferencesTests.swift`.
- `Tests/NotchCoreTests/NotchClickOnlyTests.swift`: replays the TLA+ counterexamples against actual cancellable MainActor tasks, plus both Closed/Compact shapes, reentry, click shrinking, shortcut, drag, accessibility and module holds.
- `Sources/PancakeNotch/AppWindow/AppComponents.swift`: `MonochromeSlider` must reject mouse, key and accessibility writes while disabled; it reads `isEnabled` and guards its shared setter. This is source/UI review coverage, outside the TLA+ model.
- Settings and preview wiring: `SettingsPages.swift`, `NotchPreview.swift`, `AppDelegate.swift`, `NotchWindowController.swift`. Confirm assignments still reach `model.behavior`; use the off-screen settings snapshots for visual review.

Each modeled action is a synchronous MainActor segment. `schedule` checks cancellation and calls its action with no suspension between them. The shared task can represent an open or a close; while expanded it cannot be a pending hover-open. The enabling observer must therefore cancel only while not expanded. A returning pointer must still cancel a close before the click-only opening guard. A Compact state above its resting state can also schedule a close: this is outside the model; in the click-shrink/peek/brief-compact cases `restingTarget` already keeps Compact, so canceling that task does not change the visible result.

The finite model exhausts all reachable orders for one notch, a boolean setting, pointer in/out, and one pending delay (none/open/close), with no length bound. Closed and Compact share Resting. Idle is stuttering; the chart hides only Idle and transitions staying in a visible label. It assumes no holds, Mission Control, pinned mode, module callbacks, geometry changes or animation overlap. Those mechanisms are covered only by focused or existing Swift tests, not the proof. Timers are cancellation/expiration events, not measured time. This is not a proof of AppKit event delivery, memory use or the entire app.

## Prove the check can fail

Work only in an isolated scratch worktree; preserve other edits and restore each mutation before the next.

1. Remove `!behavior.openOnClickOnly` from the opening guard in `hoverChanged`. `hoverCannotOpenButClickCan` must fail. In a scratch config set `BlockHoverEntry = FALSE`: enable click-only → enter → delay ends. `NoQueuedHoverInClickMode` and `NoHoverOpeningInClickMode` must fail.
2. Remove the `behavior.didSet` cancellation. `enablingCancelsQueuedHoverOpen` must fail for both switch-back cases. Set `CancelPendingOpen = FALSE`: enter → enable click-only → delay ends. The same two invariants must fail.
3. Remove only `state != .expanded` from that observer. `enablingPreservesQueuedClose` must fail. Set `PreservePendingClose = FALSE`: enter → click → leave → enable click-only. `PendingCloseSurvivesSetting` must fail.

Run `/statechart` on each scratch config; replay every shortest path with its named Swift test. If the model reports a bug the real test cannot reproduce, treat it as a modeling error until explained. Never relax an agreed invariant to get a pass. Restore the source and rerun the command; all checks must pass.

## Keeping the check aligned

The exact reviewed source hashes and base commit are in `verification/click-only/coverage.md`. Compare those records before relying on a pass. When a covered function changes, reread it and update the model, replay tests, and broken variants together. Move the sync commit forward only after confirming that the model describes the code at that commit. For changes that skipped this check, use `/maintain-formal-verification-skill` if installed; otherwise perform this alignment review explicitly.
