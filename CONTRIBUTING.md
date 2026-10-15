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
- **No polling.** Use notifications, callbacks, or async streams. Idle CPU should be ~0%. The only
  repeating work allowed is the song's progress while the notch is open, the Statistics page's live
  readings while it's on screen, the opt-in "Follow the music" sound bars while music plays, and
  Sparkle's once-a-day update check.
- **No new dependencies** without discussing it in an issue first (why Apple frameworks aren't enough).
  Today there are two: [Sparkle](https://sparkle-project.org) for updates and mediaremote-adapter for Now Playing.
- **No network calls** other than the update check.
- **Swift 6 strict concurrency**, macOS 15+ APIs (gate newer ones with `#available`).
- **Monochrome UI**, VoiceOver labels on every control, respect Reduce Motion.
- User-facing strings use `String(localized:)`.

## Pull requests

- Keep PRs focused, with tests for logic (geometry, state, storage).
- Describe how you tested on a real notched Mac if your change touches the UI.
- By contributing you agree your work is licensed under GPL-3.0.

## Website and help

The website lives in `site/` (plain HTML, CSS and a little JavaScript, no external requests) and
publishes to GitHub Pages when it changes on `main`. The app's Help page links to sections of
`site/help/` by their `id`, so keep those ids when editing.

## Releases (maintainers)

1. Add a `## X.Y.Z` section to `CHANGELOG.md`. Write it for people using the app: it becomes the
   update window's text and the GitHub Release notes.
2. Push a `vX.Y.Z` tag. The Release workflow tests, builds, signs, checks memory and privacy,
   publishes the GitHub Release and updates the website's update feed.

`./scripts/package-release.sh` is what the workflow runs. Every pull request also runs it with
throwaway keys (the `release-dry-run` CI job), so problems show up before release day. Signing keys
are made once with `./scripts/make-signing-keys.sh` and kept as repository secrets, never committed.
