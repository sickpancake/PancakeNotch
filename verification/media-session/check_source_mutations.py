#!/usr/bin/env python3
"""Compile scratch mutations of the actual stream; never edit product source in place."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'Vendor/mediaremote-adapter/src/adapter/stream.m').read_text()
metadata_guard = 'if (generation != sessionGeneration || request != infoGeneration) return;'
assert source.count(metadata_guard) == 1, 'Metadata callback changed: review model/source alignment.'
mutants = {
    'retired-metadata': source.replace(metadata_guard, 'if (request != infoGeneration) return;'),
    'superseded-metadata': source.replace(metadata_guard, 'if (generation != sessionGeneration) return;'),
}
for name, function in [('retired-PID', 'requestNowPlayingApplicationPID'),
                       ('retired-parent', 'requestNowPlayingParentApplicationBundleIdentifier'),
                       ('retired-playback', 'requestNowPlayingApplicationIsPlaying')]:
    start = source.index('void (^' + function + ')')
    guard = 'if (generation != sessionGeneration) return;'
    position = source.index(guard, start)
    mutants[name] = source[:position] + source[position:].replace(guard, '', 1)

expected = {
    'retired-metadata': 'retired metadata must not be accepted into the cache',
    'superseded-metadata': 'superseded metadata reply ignored while newest read is pending',
    'retired-PID': 'retired PID callback must be ignored',
    'retired-parent': 'retired parent callback must be ignored',
    'retired-playback': 'retired playback callback must be ignored',
}
with tempfile.TemporaryDirectory(prefix='pancakenotch-media-mutants-') as folder:
    for name, changed in mutants.items():
        path = Path(folder) / (name + '.m')
        path.write_text(changed)
        result = subprocess.run([str(root / 'scripts/test-adapter-stream.sh')], cwd=root,
                                env={**os.environ, 'ADAPTER_STREAM_SOURCE': str(path)},
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        assert result.returncode != 0 and 'FAIL: ' + expected[name] in result.stdout, (
            f'{name} was not caught by the expected regression:\n{result.stdout}')
        print(f'Caught source mutation: {name} -> {expected[name]}')
