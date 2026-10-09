# PancakeNotch — Project Context

## Pitch

A free, open-source (GPL-3.0), native macOS app that turns the MacBook notch into a
Dynamic Island–style surface. Differentiator: **lightweight and measured** — a published,
enforced memory budget (< 50 MB idle, < 100 MB peak) and ~0% idle CPU.

Started from scratch (not a fork of boring.notch) so the project owns its architecture and direction.

## Glossary

- **Notch** — the hardware camera cutout on the built-in display. Geometry is read at runtime
  from `NSScreen` (`safeAreaInsets`, `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`), never hard-coded.
- **Module** — a self-contained feature (Now Playing, HUD, Shelf, …) that plugs into the notch.
- **Menu** — expanded-notch navigation: Favorites grid on top + scrolling single-column module list (ADR-0010).
- **Companion app** — main window for settings, module management, and statistics (ADR-0017).
- **HUD** — system volume/brightness pop-up replacement. *Dropped from v1 (ADR-0009).*
- **Shelf** — a temporary drop zone for files dragged onto the notch.
- **Fake notch** — a simulated notch for Macs without one / external displays. *(Later.)*

## Constraints

- RAM: < 50 MB idle, < 100 MB peak (physical footprint), enforced by a check. See ADR-0006.
- CPU: ~0% idle; event-driven, no polling loops.
- macOS 15+; black visual design on all versions. See ADR-0007.
- Distributed via GitHub Releases, not notarized (no Apple Developer account). See ADR-0005.

## Decision log

| ADR | Decision |
| --- | --- |
| [0001](docs/adr/0001-build-from-scratch.md) | Build from scratch; lead our own direction |
| [0002](docs/adr/0002-native-swift-swiftui-appkit.md) | Native Swift 6 + SwiftUI, AppKit for the window |
| [0003](docs/adr/0003-minimal-dependencies.md) | Dependencies: Sparkle, mediaremote-adapter, KeyboardShortcuts |
| [0004](docs/adr/0004-license-gpl-3.md) | GPL-3.0 |
| [0005](docs/adr/0005-distribution-github-sparkle.md) | GitHub Releases + Sparkle, self-signed, no notarization |
| [0006](docs/adr/0006-memory-budget.md) | Memory and CPU budget |
| [0007](docs/adr/0007-macos-15-black-design.md) | macOS 15+, black design |
| [0008](docs/adr/0008-hardware-support.md) | All notched Macs; fake notch later |
| [0009](docs/adr/0009-v1-scope.md) | v1 = Now Playing + Shelf + Companion app (HUD dropped) |
| [0010](docs/adr/0010-module-menu.md) | Module Menu: Favorites grid + scrolling list |
| [0011](docs/adr/0011-notch-states-and-interaction.md) | Closed / Compact / Expanded; hover-to-open |
| [0012](docs/adr/0012-now-playing.md) | Now Playing via mediaremote-adapter, AppleScript fallback, placeholder |
| [0013](docs/adr/0013-shelf.md) | Shelf stores references, persists, 20-item cap |
| [0014](docs/adr/0014-architecture.md) | SwiftPM only (no Xcode), build script makes the .app; lazy modules |
| [0015](docs/adr/0015-m6-and-system-dynamic-island.md) | Don't fight a system Dynamic Island |
| [0016](docs/adr/0016-privacy.md) | No telemetry; local-only |
| [0017](docs/adr/0017-companion-app.md) | Companion app: window in same process |
| [0018](docs/adr/0018-statistics.md) | Stats: listening, usage, app health; local SQLite |
| [0019](docs/adr/0019-menu-bar-and-launch.md) | Menu bar icon + SMAppService launch at login |
| [0020](docs/adr/0020-onboarding.md) | Onboarding with notch + Now Playing checks → Help |
| [0021](docs/adr/0021-displays-and-architecture-target.md) | Built-in display only; arm64 only |
| [0022](docs/adr/0022-accessibility-and-localization.md) | Accessible; English, translation-ready |
| [0023](docs/adr/0023-testing-and-ci.md) | CI idle-memory gate + per-release peak check |
| [0024](docs/adr/0024-milestones.md) | Milestones M0–M5 → 0.1 beta |
| [0025](docs/adr/0025-repository.md) | Public GitHub repo from day one |
| [0026](docs/adr/0026-name.md) | Name: PancakeNotch |
| [0027](docs/adr/0027-help.md) | Help: basic in-app, full on GitHub, domain-ready |
| [0028](docs/adr/0028-keyboard-shortcut.md) | Configurable global shortcut (KeyboardShortcuts) |
| [0029](docs/adr/0029-visual-identity.md) | Pure monochrome visual identity |
| [0030](docs/adr/0030-full-screen-detection.md) | Hide in full screen via private Spaces API, event-driven, fail-safe |

## Open questions

None for v1 planning (grilling session closed 2026-10-09). No Xcode required — Command Line Tools are enough (ADR-0014).
