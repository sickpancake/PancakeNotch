# 0002 — Native Swift 6, SwiftUI + AppKit

**Status:** Accepted (2026-10-09)

## Decision
Swift 6 (strict concurrency), SwiftUI for views, AppKit (`NSPanel`) for the notch window,
window level, Spaces and full-screen behavior. No Electron / Tauri / Flutter.

## Consequences
- Only realistic path to the memory budget.
- Built with Command Line Tools + SwiftPM only; Xcode is not required (ADR-0014).
