# Ear and opening usability verification

Result: **PASS within the stated bounds; no product finding.**

Reviewed product source: `08cd27a8761449f9a6415a3b922325d1404ad0d2`.
Verified on 2026-11-22 using Apple Swift 6.3.3 (`swiftlang-6.3.3.1.3 clang-2100.1.1.101`),
the project's SDK wrapper, Swift Testing, and Python 3.9.6. Exact product hashes and the
toolchain record are in `coverage.json`.

The selector is deterministic, so bounded enumeration runs against production Swift rather
than a translated model. Generated histories also call the real notch model and compare drawn
ownership, hit targeting, and the module that actually opens. This is not an unbounded proof
of the application or a substitute for live usability testing.

- 576,240 four-candidate cases match the frozen pre-refactor behavior.
- 552,960 six-module cases satisfy independent alert, capacity, content, rank, placement, and
  side-swap properties across all 720 rankings.
- 6,480 real opening decisions preserve explicit targeting, waiting priority, Home settings,
  paused/empty music fallback, remembered selection, and Tabs-only availability.
- All 400 histories through length three over seven events pass. Each is independently replayed
  before each valid ear/center/strip probe; events include alert changes, Shelf badges, ranking,
  swapped sides, removal, and strips. These are synchronous API histories, not exhaustive
  asynchronous schedules.
- All seven migrated adapter classes declare content matching the real views they provide.
- The existing interaction regressions pass, including click-only, hover, music yielding,
  Home lifecycle, Timer settings, and Keep Awake ear behavior.

The generated skill was followed with real-source mutations. **All 13 were detected by their
intended properties**, including a removed adapter declaration. Compilation errors and missing
tests were not accepted as detections. All ten covered product files were restored byte for byte,
then allocation, opening/adapter, and interaction checks passed again. No product source change
was needed or retained.

Examples of detected deliberate breaks, in user terms:

1. A song plays, an agent needs an answer, then a Shelf drop shows its temporary badge. Putting
   ordinary activity first hides the agent behind music and the Shelf. `WAITING_VISIBLE` fails.
2. Keep Awake owns the first ear. Removing ear targeting causes a click there to open music.
   The actual rendered owner and opened module disagree; `POINTED_OWNER` fails.
3. Ignoring explicit targets loses the requested module; ignoring waiting priority loses the alert;
   removing the paused-music fallback loses Home. Each fails `OPENING_DESTINATION` on a generated
   opening input, while restoring the code makes the same table pass.

Run `./scripts/verify-ear-opening.sh` from the checkout root; add `--mutations` to repeat the
sensitivity proof. Each run prints the directory containing its complete logs and mutation
recovery copies. The reusable instructions, bounds, source correspondence, mutation list,
and maintenance rules are in `.agents/skills/verify-ear-opening/SKILL.md`.

Excluded: rendered appearance, physical pointer/hover delivery, VoiceOver announcements,
window-controller/full-screen behavior, other geometry, arbitrary timer/animation ordering,
and memory/CPU budgets. Those exclusions prevent a claim that every aspect of usability is
proven unchanged. CI and separately approved live checks remain necessary for those claims.
