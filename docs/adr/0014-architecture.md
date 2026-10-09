# 0014 — Architecture and build system

**Status:** Accepted (2026-10-09), amended same day (Xcode project → SwiftPM only)

## Decision
- **No Xcode project. Pure Swift Package Manager**, buildable with Apple's Command Line Tools
  alone (verified 2026-10-09 on macOS 27.0.1 / Swift 6.4: SwiftUI + AppKit compile, `NSScreen`
  notch inset reads 32 pt, Swift Testing runs).
- `Package.swift` with targets:
  - `PancakeNotch` (executable app target)
  - `NotchCore` — geometry, window (`NSPanel`), state machine, module protocol
  - `ModuleNowPlaying`, `ModuleShelf` (one target per module)
- `scripts/build-app.sh` assembles `PancakeNotch.app` (Info.plist, resources, `iconutil` icon,
  `codesign`). The same script runs locally and in GitHub Actions.
- Modules are created lazily and release heavy resources (artwork, thumbnails) when hidden.
- State: `@Observable` + Swift concurrency (actors).
- Single notch window, built-in display only (v1).
- Module protocol shaped so a future plugin system can reuse it.
- Tests use Swift Testing (`swift test`).

## Rationale
- Maintainer is not installing Xcode; everything must work from the terminal.
- Plain-text `Package.swift` is easier to edit and review than `.xcodeproj` files.
- Target boundaries keep modules isolated and the dependency graph explicit.

## Trade-offs
No SwiftUI previews, Interface Builder, or Instruments GUI. Memory is measured with
`footprint` / `leaks` / `vmmap` (built into macOS) instead.
