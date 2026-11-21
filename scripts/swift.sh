#!/usr/bin/env bash
# Runs `swift` with an SDK that works with the Command Line Tools.
# Usage: scripts/swift.sh build | test | …   (same arguments as `swift`)
#
# Why: the macOS 27 SDK in the Command Line Tools declares SwiftUI's `@State` (and other APIs) as
# macros whose implementations ship only with Xcode, so builds fail with "plugin for module
# 'SwiftUIMacros' not found". If an older macOS 26 SDK is installed alongside, use it instead.
# Has no effect with Xcode or when SDKROOT is already set (e.g. CI).
set -euo pipefail

CLT=/Library/Developer/CommandLineTools
if [[ -z "${SDKROOT:-}" && "$(xcode-select -p 2>/dev/null)" == "$CLT" ]]; then
    SDK="$(ls -d "$CLT"/SDKs/MacOSX26.*.sdk 2>/dev/null | sort -V | tail -1 || true)"
    if [[ -n "$SDK" ]]; then
        export SDKROOT="$SDK"
    fi
fi

# Swift Build (6.4) sometimes fails to resolve Swift Testing's macro plugin on the first test
# build ("plugin for module 'TestingMacros' not found"); loading it explicitly avoids that.
TESTING_MACROS="$CLT/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ "${1:-}" == "test" && "$(xcode-select -p 2>/dev/null)" == "$CLT" && -f "$TESTING_MACROS" ]]; then
    exec swift "$@" -Xswiftc -load-plugin-library -Xswiftc "$TESTING_MACROS"
fi

exec swift "$@"
