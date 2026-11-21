#!/usr/bin/env python3
"""From PancakeNotch: python3 benchmark_codex_prefix.py --base 2bd2e2e --tests

Run from the candidate checkout. Requires Swift 6, Python 3, and /usr/bin/time.
Use --rollout PATH for an extra sanitized rollout or --candidate REF to use a
committed candidate. The extract uses repo sources for the reader and parser.
Linux substitutes Glibc.open and makes autoreleasepool a direct call.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import statistics
import subprocess
import tempfile


def source(ref, file):
    return subprocess.check_output(["git", "show", f"{ref}:{file}"], text=True) if ref else Path(file).read_text()


def section(text, start, end):
    return text[text.index(start):].split(end, 1)[0]


def sources(ref):
    reader = source(ref, "Sources/AgentsCore/ClaudeSessions.swift").split("enum JSONLines {", 1)[1]
    usage = source(ref, "Sources/AgentsCore/UsageLogs.swift")
    rollout = source(ref, "Sources/AgentsCore/CodexRollouts.swift")
    stats = source(ref, "Sources/Stats/StatsStore+AIUsage.swift")
    date = section(rollout, "    nonisolated(unsafe) private static let fractional", "    /// The app a rollout")
    prelude = "import Foundation\nimport CoreFoundation\n"
    if platform.system() == "Linux":
        prelude += "import Glibc\nfunc autoreleasepool<T>(invoking work: () -> T) -> T { work() }\n"
        reader = reader.replace("Darwin.open", "Glibc.open")
    else:
        prelude += "import Darwin\n"
    return "\n".join([
        prelude,
        "enum JSONLines {" + reader,
        section(usage, "private func count(", "/// Token counts from Claude"),
        section(usage, "struct CodexUsageLog", "/// Codex's plan limits"),
        "enum CodexRollout {\n" + date + "}\n",
        section(stats, "public struct AIUsageRecord", "\n}\n") + "\n}\n",
        source(ref, "Sources/AgentsCore/ModelPrices.swift"),
    ])


def run_tests(work, ref):
    package = work / "TestsPackage"
    src = package / "Sources" / "Reader"
    tests = package / "Tests" / "ReaderTests"
    src.mkdir(parents=True)
    tests.mkdir(parents=True)
    (src / "Reader.swift").write_text(sources(ref))
    (package / "Package.swift").write_text("""// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Reader", platforms: [.macOS(.v15)], targets: [
    .target(name: "Reader"),
    .testTarget(name: "ReaderTests", dependencies: ["Reader"])
])
""")
    original = source(ref, "Tests/AgentsCoreTests/UsageTests.swift")
    functions = [
        section(original, "    @Test func codexRecordsWhatEachRequestAdded", "    @Test func addedCodexFolders"),
        section(original, "    @Test func jsonLinesStopsBeforeAHalfWrittenLine", "    @Test func theLedgerReadsEachFile"),
        "}\n" + section(original, "func temporaryFolder()", "\n}"),
    ]
    (tests / "ReaderTests.swift").write_text(
        "import Foundation\nimport Testing\n@testable import Reader\nstruct ReaderTests {\n"
        + "\n".join(functions) + "\n}\n"
    )
    subprocess.run(["swift", "test", "--package-path", str(package), "-j", "2"], check=True)


def build(work, label, ref, optimized):
    src = work / f"{label}.swift"
    exe = work / label
    filter_arg = ", spanningLineFilter: CodexUsageLog.spanningLineFilter" if optimized else ""
    src.write_text(sources(ref) + f"""
let path = URL(fileURLWithPath: CommandLine.arguments[1])
var count = 0
var checksum: UInt64 = 0
var tokenTotals: Int64 = 0
var usage = CodexUsageLog()
let clock = ContinuousClock()
let start = clock.now
let end = JSONLines.read(path, from: 0{filter_arg}) {{ line, at in
    if let record = autoreleasepool(invoking: {{
        usage.record(line, account: "fixture", fallbackThread: "unnamed")
    }}) {{
        count += 1
        checksum &+= at &* UInt64(count)
        tokenTotals += record.input + record.output + record.cacheRead
    }}
}}
let elapsed = (clock.now - start).components
print(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
print(count, checksum, end, tokenTotals, usage.thread ?? "", usage.model ?? "",
      usage.input, usage.cached, usage.output, usage.total)
""")
    subprocess.run(["swiftc", "-swift-version", "6", "-O", str(src), "-o", str(exe)], check=True)
    return exe


def json_line(event, payload):
    return json.dumps({"timestamp": "2026-10-17T19:41:48Z", "type": event, "payload": payload},
                      separators=(",", ":"), ensure_ascii=False).encode() + b"\n"


def tool_output(size):
    empty = json_line("response_item", {"type": "function_call_output", "call_id": "call_sanitized", "output": ""})
    tail = b'""}}\n'
    assert empty.endswith(tail)
    return empty[:-len(tail)] + b'"' + b"x" * (size - len(empty)) + b'"}}\n'


def tokens(index):
    return json_line("event_msg", {"type": "token_count", "info": {"total_token_usage": {
        "input_tokens": index * 100, "cached_input_tokens": index * 20,
        "output_tokens": index * 25, "total_tokens": index * 125,
    }}})


def fixture(path, repeats, size, unfinished=False, mixed=False):
    output = tool_output(size)
    with path.open("wb") as log:
        log.write(json_line("session_meta", {"id": "fixture", "originator": "codex_cli_rs"}))
        log.write(json_line("turn_context", {"model": "gpt-6.1-sol"}))
        for i in range(1, repeats + 1):
            if mixed:
                call = f"call_{i}"
                for top, payload in [
                    ("event_msg", {"type": "task_started"}),
                    ("event_msg", {"type": "user_message", "message": "Sanitized prompt 漢字"}),
                    ("response_item", {"type": "function_call", "name": "exec_command", "call_id": call,
                                       "arguments": "{}"}),
                    ("response_item", {"type": "reasoning", "summary": [{"text": "redacted"}]}),
                ]:
                    log.write(json_line(top, payload))
                log.write(tool_output({0: 768 * 1024, 1: 64 * 1024, 2: 4096}.get(i % 20, 512)))
                log.write(json_line("response_item", {"type": "message", "role": "assistant",
                                                     "content": [{"type": "output_text", "text": "redacted"}]}))
                log.write(json_line("event_msg", {"type": "task_complete"}))
            else:
                log.write(output)
            log.write(tokens(i))
        if unfinished:
            log.write(output[:-1])


def time_run(exe, path):
    mac = platform.system() == "Darwin"
    flags = ["-l"] if mac else ["-f", "%M"]
    result = subprocess.run(["/usr/bin/time", *flags, str(exe), str(path)], capture_output=True, text=True, check=True)
    elapsed, parity = result.stdout.splitlines()
    if mac:
        peak_bytes = int(re.search(r"^\s*(\d+)\s+peak memory footprint", result.stderr, re.M)[1])
    else:
        peak_bytes = int(result.stderr.strip()) * 1024
    return float(elapsed), peak_bytes, parity


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default="origin/main")
    parser.add_argument("--candidate")
    parser.add_argument("--runs", type=int, default=9)
    parser.add_argument("--rollout", type=Path, help="optional extra sanitized Codex JSONL")
    parser.add_argument("--tests", action="store_true")
    args = parser.parse_args()
    os.environ["LC_ALL"] = "C"
    with tempfile.TemporaryDirectory(prefix="codex-prefix-") as directory:
        work = Path(directory)
        if args.tests:
            run_tests(work, args.candidate)
        baseline = build(work, "baseline", args.base, optimized=False)
        candidate = build(work, "candidate", args.candidate, optimized=True)
        print("Peak memory metric:", "macOS physical footprint" if platform.system() == "Darwin" else "Linux RSS")
        cases = {
            "short": (20000, 512, False, False),
            "64KiB": (320, 64 * 1024, False, False),
            "8MiB": (5, 8 * 1024 * 1024, True, False),
            "mixed": (1000, 0, False, True),
        }
        paths = {}
        for name, spec in cases.items():
            path = work / f"{name}.jsonl"
            fixture(path, *spec)
            paths[name] = path
        if args.rollout:
            paths["external"] = args.rollout
        for name, path in paths.items():
            with path.open("rb") as log:
                digest = hashlib.sha256(log.read()).hexdigest()
            samples = {baseline: [], candidate: []}
            warm = [time_run(binary, path) for binary in samples]
            expected = warm[0][-1]
            assert warm[1][-1] == expected, (name, warm)
            for iteration in range(args.runs):
                order = (baseline, candidate) if iteration % 2 == 0 else (candidate, baseline)
                for binary in order:
                    elapsed, peak_bytes, parity = time_run(binary, path)
                    assert parity == expected, (name, binary, parity, expected)
                    samples[binary].append((elapsed, peak_bytes / 1024 / 1024))
            print(f"{name}: {path.stat().st_size} bytes sha256={digest}")
            print(f"  parity (records, positioned checksum, committed offset, tokens, thread, model, totals): {expected}")
            for binary, data in samples.items():
                milliseconds, footprint = zip(*data)
                totals = statistics.median(milliseconds), statistics.median(footprint)
                print(f"  {binary.name:9} {totals[0]:7.2f} ms {totals[1]:6.2f} MiB"
                      f" (ms range {min(milliseconds):.2f}–{max(milliseconds):.2f})")


if __name__ == "__main__":
    main()
