# PancakeNotch 🥞

A free, open-source app that turns your MacBook's notch into a Dynamic Island.
Built to be **light**: under 50 MB of memory when idle, under 100 MB at peak, ~0% CPU when nothing is happening — and we test for it.

> **Status: pre-alpha.** Nothing to install yet. Follow along or help out!

## Planned for v1

- **Now Playing** — album art and sound bars beside the notch; open it to pause, skip, scrub, shuffle and repeat, for any app that plays.
- **Shelf** — drag files onto the notch to park them; drag them out or AirDrop them later.
- **Module menu** — tabs for your favorite modules, a menu with all of them, or a two-finger swipe.
- **Companion app** — settings, favorites, and stats (listening, usage, and the app's own memory use).

Later: battery, calendar, timers, AirPods/Bluetooth, and more.

## Requirements

- A MacBook with a notch (14″/16″ MacBook Pro M1 Pro/Max or later, MacBook Air M2 or later)
- macOS 15 Sequoia or later

## Installing (once releases exist)

PancakeNotch isn't notarized by Apple (that needs a paid developer account), so macOS will warn you the first time:

1. Download `PancakeNotch.zip` from [Releases](../../releases), unzip it, and move **PancakeNotch.app** to **Applications**.
2. Open it. macOS will say it can't verify the developer — click **Done**.
3. Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to PancakeNotch.
4. Confirm. You only need to do this once — updates install automatically after that.

## Building from source

Only Apple's Command Line Tools are needed — no Xcode.

```sh
xcode-select --install          # if you don't have the Command Line Tools yet
./scripts/swift.sh test         # run the tests
./scripts/build-app.sh          # builds build/PancakeNotch.app
open build/PancakeNotch.app
./scripts/check-memory.sh       # checks idle memory against the budget
```

## Privacy

No analytics, no accounts, no telemetry. Everything stays on your Mac. The only network request is the update check, which you can turn off.

## Thanks

Inspired by [boring.notch](https://github.com/TheBoredTeam/boring.notch), [Atoll](https://github.com/Ebullioscopic/Atoll), [MewNotch](https://github.com/monuk7735/mew-notch), [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) and [NotchDrop](https://github.com/Lakr233/NotchDrop).
Now Playing uses [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) by Jonas van den Berg
(BSD 3-Clause; included in `Vendor/mediaremote-adapter` with its [licence](Vendor/mediaremote-adapter/LICENSE),
which also ships inside the app).

## License

[GPL-3.0](LICENSE). PancakeNotch is free and must stay free.
