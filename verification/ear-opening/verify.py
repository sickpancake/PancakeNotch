#!/usr/bin/env python3
"""Bounded production Swift checks, with optional real-source mutation sensitivity checks."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
ALLOCATOR = "Sources/NotchCore/EarAllocator.swift"
MODEL = "Sources/NotchCore/NotchViewModel.swift"
REGRESSION = (
    "EarRenderingTests|EarRulesTests|FirstEarTests|SecondEarTests|OpeningChoiceTests|"
    "NotchModulesTests|SongFocusTests|HomeReplayNotch|NotchClickOnlyTests|"
    "NowPlayingEarTests|KeepAwakeEarTests|TimerModuleTests"
)
MUTATIONS = [
    ("waiting-alert-evicted", ALLOCATOR, "(waiting + reserved + remaining).prefix(2)",
     "(reserved + remaining + waiting).prefix(2)", "EarUsabilityVerification", "WAITING_VISIBLE"),
    ("one-ear-lost", ALLOCATOR, ".prefix(2).map(\\.moduleID)",
     ".prefix(1).map(\\.moduleID)", "EarUsabilityVerification", "CAPACITY"),
    ("swap-ignored", ALLOCATOR, "if swapsSides {",
     "if false {", "EarUsabilityVerification", "SWAPPED_SIDES"),
    ("sound-bars-lost", ALLOCATOR, "only.configuration.hasExtra ? Slot(",
     "false ? Slot(", "EarUsabilityVerification", "LONE_CONTENT"),
    ("ranked-sides-reversed", ALLOCATOR, "return candidates.filter { owners.contains($0.moduleID) }",
     "return candidates.reversed().filter { owners.contains($0.moduleID) }", "EarUsabilityVerification", "RANKED_SIDES"),
    ("first-placement-ignored", ALLOCATOR, "let first = chosen.first { $0.configuration.placement == .first }",
     "let first: Candidate? = nil", "EarUsabilityVerification", "FIRST_PLACEMENT"),
    ("second-placement-ignored", ALLOCATOR, "let second = byAttention.first { $0.moduleID != first?.moduleID && $0.takesSecond }",
     "let second: Candidate? = nil", "EarUsabilityVerification", "SECOND_PLACEMENT"),
    ("ear-target-ignored", MODEL, "return (point.x < notch.minX ? allocation.left : allocation.right)?.moduleID",
     "return nil", "OpeningUsabilityVerification/eventOrdersKeepPointingAndOpeningInAgreement", "POINTED_OWNER"),
    ("strip-target-ignored", MODEL, "if point.y < notch.maxY - geometry.compactHeight {",
     "if false {", "OpeningUsabilityVerification/eventOrdersKeepPointingAndOpeningInAgreement", "POINTED_OWNER"),
    ("explicit-target-ignored", MODEL, "if let moduleID, modules.contains(where: { $0.moduleID == moduleID }) {",
     "if let moduleID, false, modules.contains(where: { $0.moduleID == moduleID }) {",
     "OpeningUsabilityVerification/openingPriorityTable", "OPENING_DESTINATION"),
    ("waiting-opening-ignored", MODEL, "ranked.first(where: { $0.waitsForYou })",
     "ranked.first(where: { _ in false })", "OpeningUsabilityVerification/openingPriorityTable", "OPENING_DESTINATION"),
    ("idle-home-fallback-lost", MODEL, "else if homeIsAvailable, selectedModule?.isIdleForOpening == true {",
     "else if false, selectedModule?.isIdleForOpening == true {",
     "OpeningUsabilityVerification/openingPriorityTable", "OPENING_DESTINATION"),
    ("agents-ear-metadata-lost", "Sources/ModuleAgents/AgentsModule.swift",
     "public var earConfiguration: CompactEarConfiguration? { CompactEarConfiguration() }",
     "public var earConfiguration: CompactEarConfiguration? { nil }",
     "EarModuleContractVerification", "MODULE_CONFIGURATION"),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mutations", action="store_true", help="Also prove sensitivity using 13 temporary source mutations")
    args = parser.parse_args()
    logs = Path(tempfile.mkdtemp(prefix="pancakenotch-ear-opening-"))
    print("Verification logs and mutation recovery copies: " + str(logs), flush=True)
    # The Command Line Tools' Python shim can inject SDKROOT. Preserve the caller's setting,
    # rather than allowing that shim to override the SDK selection in scripts/swift.sh.
    swift_env = os.environ.copy()
    caller_sdk = swift_env.pop("PANCAKENOTCH_VERIFICATION_SDKROOT", "")
    if caller_sdk:
        swift_env["SDKROOT"] = caller_sdk
    else:
        swift_env.pop("SDKROOT", None)
    version = subprocess.check_output([str(ROOT / "scripts/swift.sh"), "--version"], text=True, cwd=ROOT, env=swift_env)
    print(version.strip(), flush=True)
    print("Python " + sys.version.split()[0], flush=True)
    coverage = json.loads((ROOT / "verification/ear-opening/coverage.json").read_text())
    for name, expected in coverage["sha256"].items():
        if hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != expected:
            print("COVERAGE DRIFT: reread " + name + " before trusting or advancing the sync record", flush=True)

    def run(name, selection, skip_build=False):
        command = [str(ROOT / "scripts/swift.sh"), "test", "--disable-sandbox"]
        if skip_build:
            command += ["--skip-build"]
        command += ["--filter", selection]
        log = logs / (name + ".log")
        start = time.monotonic()
        with log.open("w") as output:
            result = subprocess.run(command, cwd=ROOT, env=swift_env, stdout=output, stderr=subprocess.STDOUT)
        print("{}: exit {}, {:.1f}s, {}".format(name, result.returncode, time.monotonic() - start, log), flush=True)
        return result.returncode, log.read_text(errors="replace")

    def baseline(prefix):
        for name, selection, skip in [
            ("allocation", "EarAllocatorTests|EarUsabilityVerification", False),
            ("opening-and-adapters", "OpeningUsabilityVerification|EarModuleContractVerification", True),
            ("regressions", REGRESSION, True),
        ]:
            code, output = run(prefix + name, selection, skip)
            if code != 0 or "Test run with" not in output:
                raise RuntimeError("Current code did not pass " + name + "; read its log. Report findings; do not relax the property.")

    baseline("current-")
    if args.mutations:
        originals = {name: (ROOT / name).read_bytes() for _, name, *_ in MUTATIONS}
        for name, content in originals.items():
            backup = logs / "originals" / name
            backup.parent.mkdir(parents=True, exist_ok=True)
            backup.write_bytes(content)

        def stop(signum, frame):
            raise KeyboardInterrupt("signal " + str(signum))

        previous = signal.signal(signal.SIGTERM, stop)
        try:
            for label, name, old, new, selection, expected in MUTATIONS:
                original = originals[name].decode()
                if original.count(old) != 1:
                    raise RuntimeError("Mutation anchor drift: " + label + "; update after source review")
                path = ROOT / name
                try:
                    path.write_text(original.replace(old, new, 1))
                    code, output = run("mutation-" + label, selection)
                    if code == 0 or expected not in output or "failed after" not in output or "error:" in output:
                        raise RuntimeError("Mutation was not rejected by its intended property: " + label)
                    print("CAUGHT " + label + " by " + expected, flush=True)
                finally:
                    path.write_bytes(originals[name])
        finally:
            signal.signal(signal.SIGTERM, previous)
        for name, content in originals.items():
            if (ROOT / name).read_bytes() != content:
                raise RuntimeError("Source changed during verification: " + name + "; preserved for review")
        baseline("restored-")
    print("PASS: bounded ear/opening usability checks" + ("; all 13 real-source mutations caught and restored" if args.mutations else ""), flush=True)


if __name__ == "__main__":
    main()
