# PancakeNotch 🥞

A free, open-source app that turns your MacBook's notch into a Dynamic Island.
Built to be **light**: under 50 MB of memory when idle, under 100 MB at peak, ~0% CPU when nothing is happening — and we test for it.

> **Status: beta.** Get it from the [website](https://sickpancake.github.io/PancakeNotch/) or [Releases](../../releases). Feedback and bug reports are very welcome.

## What it does

- **Now Playing** — album art and sound bars beside the notch; open it to pause, skip, scrub, shuffle and repeat, for any app that plays.
- **Shelf** — drag files onto the notch to park them; drag them out, share them or AirDrop them later.
- **Agents** — follow Claude Code and Codex threads, plus Cursor after Connect. See who is working, needs you, or finished; answer permission requests from the notch after Connect.
- **AI Usage** — choose between accounts, check plan limits, and see tokens and estimated API value for today, 7 days, or 30 days. Both AI modules are optional and read files already on your Mac.
- **Module Menu** — tabs for your favorite modules, a menu with all of them, or a two-finger swipe.
- **The PancakeNotch window** — settings, favorites, statistics (listening, usage, and the app's own memory use), short hands-on lessons, and a Help page with quick fixes.

Later: battery, calendar, timers, AirPods/Bluetooth, and more.

## Requirements

- A MacBook with a notch (14″/16″ MacBook Pro M1 Pro/Max or later, MacBook Air M2 or later)
- macOS 15 Sequoia or later

## Installing

PancakeNotch isn't notarized by Apple (that needs a paid developer account), so macOS will warn you the first time:

1. Download `PancakeNotch.zip` from the [website](https://sickpancake.github.io/PancakeNotch/) or [Releases](../../releases), unzip it, and move **PancakeNotch.app** to **Applications**.
2. Open it. macOS will say it can't verify the developer — click **Done**.
3. Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to PancakeNotch.
4. Confirm. You only need to do this once. After that, PancakeNotch checks for updates once a day and asks before installing one.

Stuck? The **Help** page in the PancakeNotch window has quick fixes, and the [help site](https://sickpancake.github.io/PancakeNotch/help/) has more.

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

No analytics, no accounts, no telemetry. Everything stays on your Mac. The only network request is the once-a-day update check, which sends nothing about you and can be turned off in **General**.

## Thanks

Inspired by [boring.notch](https://github.com/TheBoredTeam/boring.notch), [Atoll](https://github.com/Ebullioscopic/Atoll), [MewNotch](https://github.com/monuk7735/mew-notch), [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) and [NotchDrop](https://github.com/Lakr233/NotchDrop).
Now Playing uses [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) by Jonas van den Berg
(BSD 3-Clause; included in `Vendor/mediaremote-adapter` with its [licence](Vendor/mediaremote-adapter/LICENSE),
which also ships inside the app).
Updates use [Sparkle](https://sparkle-project.org) (MIT).

## License

[GPL-3.0](LICENSE). PancakeNotch is free and must stay free.
