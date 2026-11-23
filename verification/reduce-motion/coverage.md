# Coverage sync record

Sync commit: `04fa7c35988c6fbce349294f4280b1e6ee4463eb`.
The SHA-256 values below identify the reviewed source at this commit. The model mapping, replay tests and deliberately broken variants were checked against these exact bytes. Move this sync commit forward only after confirming that the verification still describes the covered code.

| Covered file | Reviewed SHA-256 |
| --- | --- |
| `Sources/NotchCore/MotionSettings.swift` | `6b16e2f1012268f2f761b88ec8c8694226011c8d87c42256f3ef692661247e8e` |
| `Sources/NotchCore/NotchViewModel.swift` | `5c92ee63e5971a231e8ce97814f651d43343cdadf372e33b47b0c3779b1b7d83` |
| `Sources/NowPlayingCore/SoundBars.swift` | `7c260d95c3dbf87d17ce7b8e661e2f0b10959e3a2de87b52dc0487a2232c0d2a` |
| `Sources/ModuleNowPlaying/NowPlayingEars.swift` | `859828d711f232ea0ee966c9a3e31785e2f96b0ca40ccb5c83628d9f5a99e739` |
| `Sources/PancakeNotch/AppWindow/SettingsPages.swift` | `0854746d0a6c1836ee3f3ee94acd93c9e25bb36c684028480eb83a47a3e64e18` |
| `Sources/NotchCore/NotchView.swift` | `dd491de633d89658a9ac60c3f42a853766e10ee7c24028f70055135df5244102` |
| `Sources/NotchCore/NotchWindowController.swift` | `ab24e0dae34805f2971b80cfe6f39300f25353eb3113393bda38eccd45258f5c` |
| `Sources/NotchCore/NotchPreview.swift` | `ca868f82ac9bb9031de3171faa5168bef4f6986005b7a71381b794d22af475da` |
| `Sources/NotchCore/NotchSnapshot.swift` | `e67b599e2f806a32317d4eadebf3ac6d7d8754f27842fe45a56886a5782df177` |
| `Sources/PancakeNotch/AppWindow/AppWindowController.swift` | `8837610df3e67cf085b3fc23cffd2e3614ec3f9fa421b9c80b7742f89fb6da91` |
| `Sources/ModuleShelf/ShelfMenuPanel.swift` | `df14a0cfba978b3aca9ff860370d02c8ffb9f27c56bb1d90c0575c04dc2bbc79` |
| `Sources/PancakeNotch/AppWindow/AppComponents.swift` | `ec1b2923819263d79073784358b6ca05576ba54363953bd728eb70b774bf9799` |
| `Sources/PancakeNotch/AppWindow/HomeEditorView.swift` | `c4b227a679ccedd30c9ef5388abd6086cd438615771c31b7a0c7533f69416f19` |
| `Tests/NotchCoreTests/MotionSettingsTests.swift` | `0f0e9dc67a1bc81b38a3cfc7055a89e77fe02c073321b8540887418ab601b890` |
| `Tests/NowPlayingCoreTests/SoundBarsTests.swift` | `50159ac1dab4e66915dc911b3f912bc9d2ac5ce8309e1995a44ec1edf1b153da` |

Checked 2026-11-22 with TLC 1.7.4 and Temurin 21.0.13+9: 88 states, 536 steps, all six rules hold. Rules, broken variants and exclusions are in `verification/reduce-motion/README.md` and the local `verify-reduce-motion` skill.
