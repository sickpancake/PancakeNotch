#!/usr/bin/env python3
"""Issue #84 offline IPC probe. Requires macOS CLT and Pillow (fixture generation only).

Usage: python3 benchmark-84.py /path/to/PancakeNotch [--runs 9]
Use --wire-only on Linux to size a Pillow thumbnail/JSON proxy for the same fixtures.
The native probe runs the Objective-C sender's real output boundary and Swift receiver
in separate processes. It samples their combined physical footprint at 1 ms intervals.
"""

import argparse
import base64
import ctypes
import io
import json
import random
import statistics
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

from PIL import Image, ImageOps


BASE = "2bd2e2ed1105789c504ba58db19bc7c1db9eead5"
CANDIDATE = "0a728da6ec8303da91aac8986ecf1621d198087e"
STREAM = "Vendor/mediaremote-adapter/src/adapter/stream.m"
NOW_PLAYING = "Sources/NowPlayingCore/"
RECEIVER_FILES = [NOW_PLAYING + name for name in (
    "AdapterStream.swift", "ArtworkImage.swift", "NowPlayingTrack.swift", "NowPlayingBackend.swift",
)]
CASES = {
    "large": [0, 1, 0, 1, 0, 1],
    "mixed": [2, 0, 3, 1, 2, 0],
}


def generate_fixtures(directory):
    fixtures = []
    for index, side in enumerate((1600, 1600, 192, 640)):
        path = directory / f"{index}.jpg"
        image = Image.frombytes("RGB", (side, side), random.Random(84 + index).randbytes(side * side * 3))
        image.save(path, format="JPEG", quality=91 if side != 640 else 95)
        fixtures.append(path)
    print("Input JPEG bytes", [path.stat().st_size for path in fixtures], flush=True)
    assert all(512 * 1024 <= p.stat().st_size <= 3 * 1024 * 1024 for p in fixtures[:2])
    assert all(p.stat().st_size < 512 * 1024 for p in fixtures[2:])
    return fixtures


def wire_proxy(fixtures):
    for index, path in enumerate(fixtures):
        original = path.read_bytes()
        preview = original
        if 512 * 1024 <= len(original) <= 3 * 1024 * 1024:
            image = ImageOps.exif_transpose(Image.open(io.BytesIO(original)))
            image.thumbnail((256, 256), Image.Resampling.LANCZOS)
            encoded = io.BytesIO()
            image.save(encoded, format="PNG")
            preview = min((original, encoded.getvalue()), key=len)

        def wire_bytes(artwork, mime):
            payload = {"processIdentifier": 42, "bundleIdentifier": "test.browser", "playing": True,
                       "title": "probe-0", "artworkMimeType": mime,
                       "artworkData": base64.b64encode(artwork).decode()}
            line = json.dumps({"type": "data", "diff": False, "payload": payload}, separators=(",", ":"))
            # Foundation's default JSON serialization escapes slashes.
            return len(line.replace("/", "\\/")) + 1

        print(f"fixture {index} Python/Pillow JSON-line bytes: "
              f"{wire_bytes(original, 'image/jpeg'):,} -> "
              f"{wire_bytes(preview, 'image/png' if preview is not original else 'image/jpeg'):,}")


def blob(repo, ref, path):
    return subprocess.check_output(["git", "show", f"{ref}:{path}"], cwd=repo, text=True)


def build_sender(repo, ref, out):
    source = blob(repo, ref, STREAM)
    # Use the checked-in preview, serializer/diff functions, and their cache block verbatim.
    output_functions = source[source.index("static CFRunLoopRef g_runLoop"):source.index("static void appForNotification(")]
    print_block = source[source.index("    __block NSData *previousArtwork") if "__block NSData *previousArtwork" in source
                         else source.index("    void (^localPrintData)"):source.index("    void (^directHandle)")]
    sender = out.with_suffix(".m")
    sender.write_text('''
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import "adapter/keys.h"
#import "utility/helpers.h"
#include <time.h>
''' + output_functions + '''
int main(int argc, const char *argv[]) {
  @autoreleasepool {
    const BOOL no_diff = NO, human_readable = NO;
''' + print_block + '''
    fprintf(stderr, "ready\\n");
    char line[20];
    int update = 0;
    while (fgets(line, sizeof(line), stdin)) {
      @autoreleasepool {
        int fixture = atoi(line) + 1;
        if (fixture < 1 || fixture >= argc) return 2;
        NSData *art = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[fixture]]];
        if (!art) return 3;
        NSDictionary *payload = @{kMRAProcessIdentifier: @42, kMRABundleIdentifier: @"test.browser",
            kMRAPlaying: @YES, kMRATitle: [NSString stringWithFormat:@"probe-%d", update++],
            kMRAArtworkMimeType: @"image/jpeg", kMRAArtworkData: art};
        uint64_t start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID);
        localPrintData(payload);
        fprintf(stderr, "%llu\\n", (unsigned long long)(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start));
      }
    }
  }
  return 0;
}
''')
    vendor = repo / "Vendor/mediaremote-adapter"
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-O2", "-mmacosx-version-min=15.0",
                    "-I", str(vendor / "src"), "-I", str(vendor / "include"),
                    "-framework", "Foundation", "-framework", "AppKit", "-framework", "ImageIO",
                    "-framework", "UniformTypeIdentifiers", str(sender), str(vendor / "src/adapter/keys.m"),
                    str(vendor / "src/utility/helpers.m"), "-o", str(out)], check=True)


def build_receiver(repo, out):
    main = out.parent / "main.swift"
    main.write_text('''
import AppKit
import Darwin

var parser = AdapterStreamParser()
var chunk = [UInt8](repeating: 0, count: 65536)
var wire = 0
var parse: UInt64 = 0
var index = 0
print("ready")
fflush(stdout)
while true {
    let count = chunk.withUnsafeMutableBytes { Darwin.read(STDIN_FILENO, $0.baseAddress, $0.count) }
    precondition(count >= 0)
    if count == 0 { break }
    wire += count
    let start = DispatchTime.now().uptimeNanoseconds
    let update = parser.feed(Data(chunk.prefix(count)), receivedAt: Date())
    parse += DispatchTime.now().uptimeNanoseconds - start
    if let update {
        let side: CGFloat = CommandLine.arguments[1] == "mixed" && [0, 4].contains(index) ? 192 : 256
        precondition(update.track?.title == "probe-\\(index)" && update.artwork?.size == NSSize(width: side, height: side))
        print("\\(wire) \\(parse)")
        fflush(stdout)
        wire = 0
        parse = 0
        index += 1
    }
}
precondition(index == 6)
''')
    subprocess.run(["xcrun", "swiftc", "-O", str(main), *(str(repo / path) for path in RECEIVER_FILES),
                    "-o", str(out)], check=True)


class RusageV0(ctypes.Structure):
    _fields_ = [("uuid", ctypes.c_ubyte * 16)] + [(name, ctypes.c_uint64) for name in (
        "user", "system", "pkg_idle_wakeups", "interrupt_wakeups", "pageins", "wired", "resident",
        "phys_footprint", "start", "exit",
    )]


def run_once(sender, receiver, fixtures, mode):
    proc_rusage = ctypes.CDLL("/usr/lib/libproc.dylib").proc_pid_rusage
    proc_rusage.argtypes = (ctypes.c_int, ctypes.c_int, ctypes.POINTER(RusageV0))
    proc_rusage.restype = ctypes.c_int
    with subprocess.Popen([str(sender), *map(str, fixtures)], stdin=subprocess.PIPE,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE) as tx:
        with subprocess.Popen([str(receiver), mode], stdin=tx.stdout, stdout=subprocess.PIPE) as rx:
            tx.stdout.close()
            try:
                phase = "idle"
                peaks = {"idle": 0, "active": 0}
                stop = threading.Event()

                def sample():
                    footprints = [RusageV0(), RusageV0()]
                    while not stop.is_set():
                        bucket = phase
                        for pid, usage in zip((tx.pid, rx.pid), footprints):
                            if proc_rusage(pid, 0, ctypes.byref(usage)):
                                break
                        else:
                            total = sum(usage.phys_footprint for usage in footprints)
                            peaks[bucket] = max(total, peaks[bucket])
                        stop.wait(0.001)

                assert tx.stderr.readline() == b"ready\n" and rx.stdout.readline() == b"ready\n"
                worker = threading.Thread(target=sample, daemon=True)
                worker.start()
                time.sleep(0.030)
                phase = "active"
                updates = []
                try:
                    for fixture in CASES[mode]:
                        sent = time.perf_counter_ns()
                        tx.stdin.write(f"{fixture}\n".encode())
                        tx.stdin.flush()
                        wire, parse = map(int, rx.stdout.readline().split())
                        latency = (time.perf_counter_ns() - sent) / 1e6
                        sender_cpu = int(tx.stderr.readline()) / 1e6
                        updates.append((wire, parse / 1e6, latency, sender_cpu))
                finally:
                    stop.set()
                    worker.join()
                tx.stdin.close()
                assert tx.wait(timeout=5) == rx.wait(timeout=5) == 0
                assert min(peaks.values()) > 0, peaks
                return {
                    "wire per update (bytes)": [u[0] for u in updates],
                    "first artwork (ms)": updates[0][2],
                    "large artwork median latency (ms)": statistics.median(u[2] for i, u in enumerate(updates) if CASES[mode][i] < 2),
                    "parser total (ms)": sum(u[1] for u in updates),
                    "large sender median CPU (ms)": statistics.median(u[3] for i, u in enumerate(updates) if CASES[mode][i] < 2),
                    "combined idle (MiB)": peaks["idle"] / (1024 * 1024),
                    "combined sampled peak (MiB)": peaks["active"] / (1024 * 1024),
                }
            finally:
                for child in (tx, rx):
                    if child.poll() is None:
                        child.kill()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repo", nargs="?", default=".", type=Path)
    parser.add_argument("--base", default=BASE)
    parser.add_argument("--candidate", default=CANDIDATE)
    parser.add_argument("--runs", default=9, type=int)
    parser.add_argument("--wire-only", action="store_true")
    args = parser.parse_args()
    assert args.runs > 0
    with tempfile.TemporaryDirectory(prefix="pancakenotch-84-") as work:
        directory = Path(work)
        fixtures = generate_fixtures(directory)
        if args.wire_only:
            wire_proxy(fixtures)
            return
        if sys.platform != "darwin":
            parser.error("the release-mode probe requires macOS; use --wire-only for the Pillow proxy")
        repo = args.repo.resolve()
        # Both revisions use identical receiver, serializer and key sources. The sender's differing
        # code is extracted from each pinned commit regardless of the working tree.
        for path in (*RECEIVER_FILES, "Vendor/mediaremote-adapter/src/utility/helpers.m",
                     "Vendor/mediaremote-adapter/src/adapter/keys.m"):
            assert blob(repo, args.base, path) == blob(repo, args.candidate, path) == (repo / path).read_text(), path
        senders = {"base": directory / "base", "candidate": directory / "candidate"}
        for variant, ref in (("base", args.base), ("candidate", args.candidate)):
            build_sender(repo, ref, senders[variant])
        receiver = directory / "receiver"
        build_receiver(repo, receiver)
        for mode in CASES:
            results = {"base": [], "candidate": []}
            for iteration in range(args.runs):
                for variant in tuple(senders)[::(-1 if iteration % 2 else 1)]:
                    result = run_once(senders[variant], receiver, fixtures, mode)
                    results[variant].append(result)
                    print(mode, variant, iteration + 1, json.dumps(result), flush=True)
            print(f"{mode} medians over {args.runs} paired runs", flush=True)
            for key in results["base"][0]:
                if key == "wire per update (bytes)":
                    print(f"  {key}: {results['base'][0][key]} -> {results['candidate'][0][key]}")
                else:
                    left, right = (statistics.median(r[key] for r in results[v]) for v in senders)
                    print(f"  {key}: {left:.2f} -> {right:.2f} (delta {right - left:+.2f})")


if __name__ == "__main__":
    main()
