# Contributing to PancakeNotch

Thanks for helping! A few ground rules keep the app small and fast.

## Before you start

- For bigger changes or new features, open an issue first to discuss the direction.
- For anything bigger than a bug fix, open an issue before writing code.

## Setup

Only the Command Line Tools are required (`xcode-select --install`). Xcode works too but is not needed, and please don't commit an `.xcodeproj`.

```sh
./scripts/swift.sh test
./scripts/build-app.sh debug
./scripts/check-memory.sh
```

## Rules

- **Memory budget:** < 50 MB idle, < 100 MB peak. CI fails if idle memory goes over.
- **No polling.** Use notifications, callbacks, or async streams. Idle CPU should be ~0%.
- **No new dependencies** without discussing it in an issue first (why Apple frameworks aren't enough).
- **Swift 6 strict concurrency**, macOS 15+ APIs (gate newer ones with `#available`).
- **Monochrome UI**, VoiceOver labels on every control, respect Reduce Motion.
- User-facing strings use `String(localized:)`.

## Pull requests

- Keep PRs focused, with tests for logic (geometry, state, storage).
- Describe how you tested on a real notched Mac if your change touches the UI.
- By contributing you agree your work is licensed under GPL-3.0.
