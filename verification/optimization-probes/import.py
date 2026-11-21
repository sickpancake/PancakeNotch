"""Time the running app from launch until a synthetic 20,480-message import commits."""

import datetime
import json
import os
from pathlib import Path
import sqlite3
import statistics
import subprocess
import sys
import tempfile
import time


def make_fixture(root, count):
    folder = root / ".claude"
    projects = folder / "projects" / "example"
    projects.mkdir(parents=True)
    (folder / ".claude.json").write_text(
        '{"oauthAccount":{"emailAddress":"fixture@example.com","organizationType":"claude_pro"}}'
    )
    timestamp = datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z")
    with (projects / "example.jsonl").open("w") as fixture:
        for i in range(count):
            record = {
                "type": "assistant",
                "timestamp": timestamp,
                "message": {
                    "id": f"example-{i}",
                    "model": "claude-sonnet-4-6",
                    "usage": {"input_tokens": 100, "output_tokens": 25},
                    "content": "x" * 1024,
                },
            }
            fixture.write(json.dumps(record, separators=(",", ":")) + "\n")
    return folder


def measure(app, folder, run_dir, count):
    run_dir.mkdir()
    db = run_dir / "statistics.sqlite"
    env = os.environ | {
        "PANCAKENOTCH_SIMULATE_NOTCH": "1",
        "PANCAKENOTCH_SKIP_ONBOARDING": "1",
        "PANCAKENOTCH_DEBUG_STATE": "closed",
        "PANCAKENOTCH_STATS_FILE": str(db),
        "PANCAKENOTCH_AGENTS_SOCKET": str(run_dir / "agents.sock"),
    }
    args = [
        str(app / "Contents/MacOS/PancakeNotch"),
        "-agents.enabled", "YES", "-aiUsage.enabled", "YES",
        "-aiUsage.addedFolders", f'("{folder}")',
        "-modules.order", '("aiUsage","agents","nowPlaying","shelf")',
    ]
    started = time.monotonic()
    child = subprocess.Popen(args, env=env, stdout=subprocess.DEVNULL)
    try:
        while time.monotonic() - started < 45 and child.poll() is None:
            try:
                with sqlite3.connect(f"{db.as_uri()}?mode=ro", uri=True, timeout=0.01) as con:
                    rows, tokens = con.execute(
                        "SELECT COUNT(*), SUM(input + output) FROM ai_usage WHERE id LIKE 'example-%'"
                    ).fetchone()
                    if rows == count:
                        assert tokens == count * 125, (rows, tokens)
                        return 1000 * (time.monotonic() - started)
            except sqlite3.OperationalError:
                pass
            time.sleep(0.02)
        raise RuntimeError(f"Import did not finish for {app}")
    finally:
        child.terminate()
        try:
            child.wait(timeout=5)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait()


with tempfile.TemporaryDirectory(prefix="usage-import-") as scratch:
    root = Path(scratch).resolve()
    count = 20_480
    folder = make_fixture(root, count)
    apps = [Path(arg) for arg in sys.argv[1:]]
    times = [[], []]
    for i in range(5):
        for j in ((0, 1) if i % 2 == 0 else (1, 0)):
            times[j].append(measure(apps[j], folder, root / f"{i}-{j}", count))
    base, candidate = [statistics.median(series) for series in times]
    print(f"First app import, {count:,} messages: {base:.0f} -> {candidate:.0f} ms")
