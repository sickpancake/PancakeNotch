#!/usr/bin/env python3
"""Reproduce the disk-backed AI Usage ledger probe on Linux or macOS."""
import argparse
import json
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import tempfile


def git_show(repo, rev, path):
    return subprocess.check_output(["git", "-C", str(repo), "show", f"{rev}:{path}"], text=True)


def build(repo, rev, role, directory, swift):
    linux = platform.system() == "Linux"
    sources = directory / "Sources"
    stats = sources / "Stats"
    probe = sources / "Probe"
    stats.mkdir(parents=True)
    probe.mkdir()
    extension = '.define("BASELINE")' if role == "base" else ""
    sqlite_target = '.systemLibrary(name: "SQLite3"),' if linux else ""
    sqlite_dependency = '"SQLite3"' if linux else ""
    probe_dependencies = '"Stats", "SQLite3"' if linux else '"Stats"'
    (directory / "Package.swift").write_text(f"""// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "CheckpointProbe", platforms: [.macOS(.v15)], targets: [
    {sqlite_target}
    .target(name: "Stats", dependencies: [{sqlite_dependency}]),
    .executableTarget(name: "Probe", dependencies: [{probe_dependencies}], swiftSettings: [{extension}])
])
""")
    if linux:
        sqlite = sources / "SQLite3"
        sqlite.mkdir()
        (sqlite / "module.modulemap").write_text('module SQLite3 [system] { header "sqlite.h" link "sqlite3" export * }\n')
        (sqlite / "sqlite.h").write_text("""#include <sqlite3.h>
#ifdef __linux__
#include <stddef.h>
void *memmem(const void *haystack, size_t haystack_count, const void *needle, size_t needle_count);
#endif
""")
    def read(path):
        return git_show(repo, rev, path) if rev != "worktree" else (repo / path).read_text()

    for name in ("Database", "StatsStore", "StatsStore+AIUsage", "StatsSummary", "PlayKind", "AppHealth"):
        if linux and name == "AppHealth":
            continue
        source = read(f"Sources/Stats/{name}.swift")
        if linux and name == "Database":
            source = source.replace("import os\n", "").replace(", privacy: .public", "")
            source += """\nprivate struct Logger {
    init(subsystem: String, category: String) {}
    func error(_ text: String) { FileHandle.standardError.write(Data((text + "\\n").utf8)) }
}
"""
        (stats / f"{name}.swift").write_text(source)

    # Copy the actual parser, scanner, SQLite layer and pricing. Drop the unrelated limits reader.
    usage = read("Sources/AgentsCore/UsageLogs.swift")
    begin = usage.index("/// Codex's plan limits")
    end = usage.index("/// Reads the token history")
    usage = "import CoreFoundation\n" + usage[:begin] + usage[end:]
    json_lines = "import Foundation\n" + "enum JSONLines" + read(
        "Sources/AgentsCore/ClaudeSessions.swift"
    ).split("enum JSONLines", 1)[1]
    if linux:
        usage = usage.replace("import os", "import Glibc\nimport SQLite3")
        json_lines = "import Glibc\n" + json_lines.replace("Darwin.open", "Glibc.open")
    date = read("Sources/AgentsCore/CodexRollouts.swift").split("    nonisolated(unsafe) private static let fractional", 1)[1].split("\n    /// The app a rollout", 1)[0]
    (probe / "UsageLogs.swift").write_text(usage)
    (probe / "JSONLines.swift").write_text(json_lines)
    (probe / "ModelPrices.swift").write_text(read("Sources/AgentsCore/ModelPrices.swift"))
    (probe / "Support.swift").write_text("""import Foundation
enum AgentTool: Sendable { case claude, codex }
enum CodexRollout {
    nonisolated(unsafe) private static let fractional""" + date + """
}
#if os(Linux)
func autoreleasepool<T>(invoking body: () -> T) -> T { body() }
final class OSAllocatedUnfairLock<State>: @unchecked Sendable {
    private let lock = NSLock()
    private var state: State
    init(initialState: State) { state = initialState }
    func withLock<T>(_ body: (inout State) -> T) -> T { lock.withLock { body(&state) } }
}
#endif
""")
    shutil.copyfile(Path(__file__).with_name("CheckpointProbe.swift"), probe / "CheckpointProbe.swift")
    subprocess.run([swift, "build", "-c", "release", "--package-path", str(directory)], check=True)
    return Path(subprocess.check_output(
        [swift, "build", "-c", "release", "--show-bin-path", "--package-path", str(directory)], text=True
    ).strip()) / "Probe"


def run(repo, base, changed, swift, count, root):
    binaries = {role: build(repo, rev, role, root / role, swift)
                for role, rev in (("base", base), ("changed", changed))}
    correctness = {}
    for role, executable in binaries.items():
        correctness[role] = json.loads(subprocess.check_output([
            executable, "correctness", root / f"correctness-{role}"
        ], text=True))
    assert correctness["base"] == correctness["changed"], correctness
    print("Correctness (baseline == changed):", json.dumps(correctness["base"], sort_keys=True), flush=True)
    for label, stored, eligible, appended in (("small", 32, 32, 4),
                                              ("large-sparse", 12000, 1000, 16),
                                              ("busy-recent", 4000, 4000, 120)):
        fixture = root / label
        subprocess.run([binaries["base"], "prepare", fixture, str(stored), str(eligible), str(appended)], check=True)
        results = {role: [] for role in binaries}
        for iteration in range(count):
            for role in (tuple(binaries) if iteration % 2 == 0 else tuple(reversed(binaries))):
                shutil.copyfile(fixture / "stats.sqlite", fixture / "run.sqlite")
                result = json.loads(subprocess.check_output([binaries[role], "scan", fixture], text=True))
                assert result.pop("firstFiles") == appended and result.pop("repeatFiles") == 0, result
                results[role].append(result)
                for suffix in ("", "-wal", "-shm"):
                    (fixture / f"run.sqlite{suffix}").unlink(missing_ok=True)
        metrics = {role: {key: round(statistics.median(row[key] for row in runs), 3)
                          for key in runs[0]}
                   for role, runs in results.items()}
        assert metrics["base"]["dailyTokens"] == metrics["changed"]["dailyTokens"] == 6 * appended, metrics
        print(label, stored, eligible, appended, json.dumps(metrics, sort_keys=True), flush=True)
        (root / f"{label}.json").write_text(json.dumps(results, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repo", type=Path)
    parser.add_argument("base", help="git revision for baseline")
    parser.add_argument("changed", help="git revision, or worktree")
    parser.add_argument("--swift", default=os.environ.get("SWIFT", "swift"))
    parser.add_argument("--runs", type=int, default=11)
    parser.add_argument("--output", type=Path, help="New directory to retain fixture and raw runs")
    opts = parser.parse_args()
    if opts.output:
        opts.output.mkdir()
        run(opts.repo, opts.base, opts.changed, opts.swift, opts.runs, opts.output.resolve())
    else:
        with tempfile.TemporaryDirectory(prefix="checkpoint-probe-") as directory:
            run(opts.repo, opts.base, opts.changed, opts.swift, opts.runs, Path(directory))
