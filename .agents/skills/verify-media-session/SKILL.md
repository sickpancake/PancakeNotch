---
name: verify-media-session
description: Verify Now Playing media-session retirement and metadata reply ordering when changing the vendored adapter stream, notification observers, resetAll, requestNowPlayingInfo, or callback generation guards.
---

# Verify closed browser media sessions

Promise: replies from a retired media session cannot repopulate its cached metadata or player fields, and a superseded metadata read cannot overwrite a newer read.
Harm: a closed video's details can return, or controls and playback state can belong to a different video.

## Run

With the official TLC 1.7.4 release jar in `TLA2TOOLS` and an installed Java binary in `JAVA`, run from the project root:

```sh
./scripts/verify-media-session.sh
```

The script pins the jar SHA-256 to `936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88`, compiles and runs the actual Objective-C stream against fake MediaRemote callbacks, catches five scratch source mutations, and checks the current and broken TLA+ configurations. Confirmed with Eclipse Temurin 25.0.5+8. Java and TLC are development tools only. The native replays use the Command Line Tools, not Xcode. Expect about 15 seconds; no app or media playback is launched. macOS notification and Java local-socket access may require the harness's ordinary execution approval.

Read every model result with `/statechart`. Copy `verification/media-session/MediaSession.tla`, its `.cfg` files, and `view.mjs` to a fresh system temporary directory; follow the installed `/statechart` instructions to check each configuration and generate fresh report/chart output. Read current and both broken configurations, including all shortest paths. Do not substitute an older statechart command. The current config is `MediaSession.cfg`; `NoSessionGuard.cfg` and `NoRequestGuard.cfg` must fail their intended rules.

## Source correspondence and scope

Last source sync: commit `b1bbc4d5c756998dd6ffa56f5e6d77efdb2d9803`. The product source is unchanged after that commit. Exact covered symbols and hashes are in `verification/media-session/coverage.md`.

- `Vendor/mediaremote-adapter/src/adapter/stream.m`: startup `requestAll` issues metadata, PID, playing, and parent reads. `RequestNowPlayingInfo` is a later queue-change read. `InfoReply` is the body of the metadata callback, including the session and request checks. `FieldReply` is one of the startup PID/playing/parent callbacks. `CloseSession` is the no-process playback/info notification branch's synchronous `resetAll` and `handle`, which does not issue a new metadata read.
- `sessionGeneration`, `infoGeneration`, and `pendingInfo` correspond to real counters and outstanding completion blocks. `titleSession`, `fieldSession`, and `appliedOldReply` are observation tags for the checker, not extra product mechanisms. Each modeled transition is one synchronous serial-queue segment; request and reply are separate. The cache is modeled, not the UI: `allMandatoryPayloadKeysSet` may withhold an incomplete cache from the stream.
- `Tests/AdapterStreamTests/ClosedSessionTests.m` includes the actual production stream and stubs only MediaRemote, process lookup, and output capture. It replays normal pause/close/takeover behavior, replies before and after a newer result, and late startup metadata/PID/playing/parent callbacks after a no-process reset. Counting rejected callback emissions and accepted conversions observes whether retired data was accepted even when incomplete data would not yet be displayed.
- `scripts/test-adapter-stream.sh` compiles both replay scenarios. `ADAPTER_STREAM_SOURCE` is a test-only compiler override for a scratch source copy, not an app setting. `check_source_mutations.py` removes each of the three field guards, the metadata session guard, and the metadata request guard separately; all must fail with their named assertion. The product file is never edited in place.

The model exhausts 312 reachable states for one retirement, two total metadata reads, three independently returning startup field reads, and empty/nonempty metadata. Replies may arrive in any order or remain pending. It assumes a serial callback queue and truthful response snapshots (possibly captured earlier). Safety, not eventual delivery or latency, is verified. It does not model notification delivery by macOS/browsers, app-session refresh reads after every kind of notification, allMandatory output gating, artwork, debounce, enabled-command callbacks, process lookup failures, helper crashes, fallback, counter overflow, repeated sessions, memory/CPU, or the whole app. Pausing and application/queue event wiring are native-test coverage, not extra TLA+ properties.

The passing chart hides idle steps and transitions that stay in the same visible label; no other transitions are hidden. The broken-session chart exceeds 500 states and therefore contains shortest bug paths only.

## Prove the check detects a real break

Run the command above. It first checks the unmodified source, then compiles five source copies with exactly one guard removed, requires the corresponding native assertion to fail, checks the two broken model configs, and leaves the actual source unchanged. All three safety invariants must fail on their corresponding model variants, as interpreted with `/statechart`; each shortest path must match a native replay in code terms. If a mutated source compiles but does not fail at the expected assertion, investigate the test/model alignment. An unrelated compiler failure is not a caught mutant.

For a newly reported current-code counterexample, replay every step against the actual stream. If it does not reproduce, treat the model as wrong until explained. Do not weaken a rule to make it pass. Report findings; do not edit product code as part of a review unless the user asks.

## Keep it aligned

When a covered callback or reset changes, reread its whole serial segment and update the model, native replays, source mutations, and coverage record together. Only move the sync commit forward after confirming that the verification describes that new source commit. Use `/maintain-formal-verification-skill` for later realignment when available; otherwise perform this correspondence check explicitly.
