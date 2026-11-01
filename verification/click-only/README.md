# Click-only opening verification

Run `scripts/verify-click-only.sh` with `TLA2TOOLS` pointing to TLC 1.7.4 and `JAVA` pointing to Java (validated with Temurin 25.0.5+8). All checker artifacts are written outside the repo. Use the project-local `verify-click-only` skill for model correspondence, broken variants and maintenance; use `/statechart` to read every TLC result.

The model checks every reachable order of pointer entry/exit, setting changes, delay expiration, click opening and explicit closing for one notch and one pending task. Three invariants prevent queued hover-opening in click-only mode, actual hover-opening in that mode, and loss of a pending close when enabling it. Closed/Compact are one resting state. Geometry, real time, animation, module holds and system overlays are outside this finite model.

Actual Swift regression tests replay the counterexamples with real cancellable MainActor tasks. Each mutation must fail those tests as well as its model variant; a passing hand model alone does not verify the Swift implementation.

## Verified failure paths

These are deliberate broken implementations, replayed against the real Swift code and then restored:

- Missing hover guard: enable click-only (step 1), enter the notch (2), delay ends (3). `NoQueuedHoverInClickMode` fails at 2 and `NoHoverOpeningInClickMode` at 3. Cause: `hoverChanged(true)` still schedules the opening task. Fix: guard only the hover-entry opening branch.
- Missing pending-open cancellation: enter (1), enable click-only (2), delay ends (3). The same rules fail at 2 and 3. Cause: the old task already exists, so an entry guard alone cannot stop it. Fix: cancel that task when enabling the setting while not expanded. Also tested a quick on/off switch before expiration.
- Overbroad cancellation: enter (1), click (2), leave (3), enable click-only (4). `PendingCloseSurvivesSetting` fails at 4. Cause: opening and closing share `hoverTask`, so unconditional cancellation removes the scheduled close. Fix: cancel on enabling only while not expanded.

The ordinary implementation passes all three invariants over 9 reachable states and 37 transitions. Swift regression tests caught each corresponding real source mutation; their restored version passes. `/statechart` hides idle steps and transitions within an unchanged visible label.
