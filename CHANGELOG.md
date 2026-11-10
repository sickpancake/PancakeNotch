# Changelog

What's new in each release. The release pipeline copies a version's notes into the update window,
so write them for people using the app: short, plain, no code talk.

## Unreleased

## 0.3.1 — beta

**This is a beta.** PancakeNotch is still being tested, so expect bugs: some things may not work as they should yet. If something goes wrong, please report it on GitHub.

- **Peek at an agent.** Rest the pointer on an agent in the Agents list and its row opens a little to show its whole name, everything it's doing, and the app it runs in (like "Claude Code in T3 Code"), before you click into it.
- **Listening and watching, kept apart.** Statistics has a new Media section with a Listening | Watching switch: your music, podcasts and audiobooks on one side, videos and streams (like YouTube or Twitch in your browser) on the other, each with time per day and its top songs or videos, artists or channels, and apps, side by side. Plays from before the update are sorted too, and apps show by name.
- **No more ads in your music.** Spotify ads no longer count as songs in Statistics.
- **What shows beside the notch.** A new Help section explains which modules get the two spots beside the notch and why, and the Modules page now shows where each one goes, including the Timer's second spot.

## 0.3.0 — beta

**This is a beta.** PancakeNotch is still being tested, so expect bugs: some things may not work as they should yet. If something goes wrong, please report it on GitHub.

- **Timer and Stopwatch.** A timer and a stopwatch with laps, like the ones on your phone, right in the notch. Start a quick time or set your own on the wheels; the time left shows beside the notch with a ring that drains. When it ends, a sound plays and the notch opens on Done (or, if you prefer, just a small strip slides out under it). It keeps time while your Mac sleeps or the app is closed.
- **Keep Awake.** Keep your Mac from falling asleep for 30 minutes to 4 hours, or until you stop it, right from the notch or the menu bar. It also turns on by itself while an AI agent works or the Shelf converts a file, and stops 2 minutes after. A coffee cup beside the notch shows it's on. By default the screen stays on (so it won't lock by itself); choose Can sleep to let it dim and lock while your Mac keeps working. It stops when the battery gets low and comes back on when you plug in; you can have it keep going instead.
- **Your AI limits, ready again.** AI Usage can briefly show the account, plan and limit that reset under the notch, with a small ring that fills back up. It is on by default, with a switch and a practice example in the module settings.
- **Convert files.** Drop files on the new Convert area while you drag them to the notch, and turn them into another format in one click: pictures to JPEG, PNG, HEIC, TIFF or PDF, PDFs to pictures or text, sound to M4A, WAV and more, videos to MP4, MOV, their sound or a short GIF, and text to PDF. Several pictures and PDFs can become one PDF. It stays light: anything too big for the memory limit says so instead.
- **The notch opens on what you point at.** Clicking or hovering a spot beside the notch, or a strip under it, opens that module. Something waiting for you, like an agent that needs an answer or a finished timer, comes first and always gets a spot beside the notch. If you switch away from the music, your choice stays put when the next song starts.
- **Open on click only.** A new setting in Notch makes the notch open only when you click it, not when the pointer passes over it.
- **Safer Allow.** Allow in the notch now only approves what it fully shows: commands appear whole, and file changes show a Review button with every changed line and where the file really is. PancakeNotch also reads media, agent and Shelf files more carefully.
- **Fixes.** A strip under the notch no longer brings up the last module you used beside it, the notch opens early for drags from Finder and the Dock, helpers stay under the right conversation, the Shelf works from the keyboard (arrow keys, Tab, choosing items to remove), Convert says honestly when the Shelf is full, AI Usage totals update when the day changes, and VoiceOver reads commands with their real line breaks.

## 0.2.0 — beta

**This is a beta.** PancakeNotch is still being tested, so expect bugs: some things may not work as they should yet. If something goes wrong, please report it on GitHub.

- **Agents.** Follow your Claude Code, Codex and Cursor conversations from the notch: working, needs you, done or stopped, with Allow once / Deny right in the notch when the whole request fits. Helpers sit in a dropdown under the conversation that started them, including helpers started from T3 Code.
- **AI Usage.** See how much of each plan's limits is left, plus tokens and their estimated API value for today, 7 days or 30 days. A small gauge beside the closed notch can show the account and limit you choose. Your history stays on your Mac.
- **Your agents, your way.** Name agents by their conversation title, your last message or the Git branch. Choose which tools show, how long finished agents stay, and whether to show helpers and what each agent is doing.
- **Try them safely.** New hands-on lessons with practice agents and accounts, plus Help for both.
- **Smoother everywhere.** Gentle fades on buttons and switches, numbers that roll instead of jumping, and many small alignment fixes.
- **Full screen.** The notch hides only while a video really fills the screen, and the top edge of the screen no longer makes it flicker.
- **Fixes.** Dragging from Finder opens the notch again, the notch closes properly when you leave while it opens, the Shelf keeps long names readable, and the app window is easier to find your way around.
- **Safer.** PancakeNotch reads other apps' files more carefully and keeps its own data private to your Mac account.

## 0.1.0 — first beta

- **The notch, put to work.** Hover the notch to open it; it closes when you move away.
- **Now Playing.** See and control what's playing in Music, Spotify or your browser, with album art and sound bars beside the notch.
- **Shelf.** Drop files, text and links on the notch to keep them handy, then drag them out, share them or AirDrop them.
- **Module Menu.** Switch between modules, pick favorites and choose which sit beside the notch.
- **Learn.** Short hands-on lessons, and a welcome that checks the notch and your music work on this Mac.
- **Statistics.** Your listening and notch use, plus the app's own memory and CPU, kept only on your Mac.
- **Help.** Quick fixes for common problems, right in the app.
- **Automatic updates.** PancakeNotch checks once a day and asks before installing.
