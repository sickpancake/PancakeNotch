# Changelog

What's new in each release. The release pipeline copies a version's notes into the update window,
so write them for people using the app: short, plain, no code talk.

## Unreleased

- **Number keys switch modules.** With the notch open, press 1–9 to jump to the module with that number on the Modules page, or 0 to go to Home. Typing in a note or a search box still types the number.
- **The timer turns amber in its last minute.** Under a minute left, the ring and time in the notch change from white to amber, so a short timer catches your eye before it ends.
- **Undo Home edits in the notch.** While editing Home in the notch, press ⌘Z to undo a change and ⇧⌘Z to redo it, or use the small undo button beside Done.
- **A reminder to plug in.** With Keep Awake on, a strip under the notch tells you when your battery reaches 20% and again at 10%. Turn it off with **Warn me to plug in** in Keep Awake's settings.
- **Fixed a note losing its last few characters.** Text typed in one fast burst — an expander, macro or dictation — now saves in full.

## 0.5.0

**This is a beta.** PancakeNotch is still being tested, so expect bugs: some things may not work as they should yet. If something goes wrong, please report it on GitHub.

- **Install from a disk image.** Each release now comes as PancakeNotch.dmg: open it and drag PancakeNotch onto Applications.
- **Notes.** A new module for jotting things down for later, right in the notch: the first line is the title and it saves as you type. Pin the notes you need most, undo a delete, and sort by last edited, newest or oldest.
- **Find a note fast.** A search field sits above the Notes list: press ⌘F and type a few words. Only notes with all of them stay, pinned ones first, with the words highlighted. Use the arrows and Return to open a match, and Esc to clear. In Notes' settings, hide the field until you search, search titles only, or keep the search for next time.
- **Count as you write.** Notes shows live word and character counts for the whole note or just the text you select. Turn them off with **Show text counts** in Notes settings.
- **Text files become notes.** Drop a .txt or .md file on the Shelf (or on Notes) and it's kept as a note. In Notes' settings, choose All text to turn dropped text into notes too, or Off to keep everything on the Shelf.
- **Notes on Home and in Learn.** Small, medium and large Notes widgets for Home, and a short hands-on Notes lesson.
- **Run several named timers.** Use **New timer** to start another countdown without stopping the others. The notch shows the one ending soonest and how many others are running; each rings when it ends.
- **Devin in Agents.** Connect Devin (Devin CLI and the Devin app) under Agents settings, and its sessions show up in the notch next to Claude Code, Codex and Cursor: working, needs you or done, with what it's doing right now. Allow once or Deny the commands it wants to run, right from the notch.
- **Screenshots on the Shelf.** Turn on Catch new screenshots in Shelf settings and every new screenshot lands on the Shelf, with a short note under the notch, ready to drag into a chat, AirDrop or convert. It uses the folder your Mac saves screenshots to.
- **Clipboard history on the Shelf.** Turn on **Remember what I copy** in Shelf settings, then open **Clipboard** to reuse, pin, drag out or AirDrop recent copies. Passwords are skipped, and the history clears when PancakeNotch quits.
- **See what a finished agent changed.** When a local agent finishes, Agents shows its branch, how many files and lines changed, and its last commit, on its row, in the peek under the notch and on the Agents Home widget. Rest the pointer on it for Open in your editor, Terminal here and Copy summary. Only changes made while the agent works count, not edits you already had. PancakeNotch asks git when the agent starts and when it stops, on your Mac only.
- **Devin cloud sessions in Agents.** Sessions that run on Devin's servers now show up too, next to your local agents: working, needs you, done or stopped, with their pull request once there is one. Click one to open it in your browser. Connect with a Devin personal access token under Agents settings; it's kept in your Keychain and only sent to Devin. PancakeNotch asks Devin only while a session runs, or when you come back to your Mac.
- **Codex cloud and GitHub's coding agent in Agents.** Turn on Codex cloud or GitHub coding agent under Agents settings, and their cloud tasks show up next to your other agents: working, needs you, done or stopped, with the pull request once there is one. PancakeNotch uses the Codex CLI and the GitHub CLI you're already signed in to, and asks only while a task runs or when you come back to your Mac.
- **Pull request checks.** With GitHub coding agent on, a finished cloud agent's pull request shows whether its checks are running, passed or failed.
- **Quick replies to Devin.** A Devin cloud session waiting for your next message gets Continue and Stop right in the notch.
- **Reduce motion.** A new switch under General › Motion calms PancakeNotch down: fades instead of springs, slides and wiggles, and still sound bars, in the notch and the window. It's also on whenever Reduce motion is on for your whole Mac (Accessibility › Display), which PancakeNotch now follows everywhere, including the peek strip and Home's page scrolling.
- **Paste onto the Shelf.** Press ⌘V in the open Shelf to add what you copied: files, pictures, links and text, just like a drop. Or click **⌘V to paste** at the top of the Shelf. What you pasted is selected, so Delete takes it back off, and ⌘C copies selected items. Turn it off with **Paste with ⌘V** in Shelf settings.
- **Devin in AI Usage.** With Devin cloud connected, AI Usage gets a Devin account showing the ACUs your sessions used today, in 7 days and in 30 days, and the sessions that used the most.
- **Pin Shelf items.** Right-click an item on the Shelf and choose Pin, click the pin beside the back arrow when an item is open, or select it and press P. Pinned items stay at the front, show a small pin and are never cleared by themselves: not after a while, not after you drag them out, and not by Clear all unless you choose that in Shelf settings. Undo right after pinning, and Unpin All in Shelf settings.
- **See what didn't fit beside the notch.** A small **+n** shows how many active modules didn't fit. Open it to see Home, or go straight to a hidden module if you use tabs-only navigation.
- **Peek strips wait while you look.** Rest your pointer on a strip below the notch to keep it open. Click it to open its module.
- **One undo history for Home.** Undo a Home layout change from either the notch or the window editor, even if you made it in the other one.

## 0.4.0 — beta

**This is a beta.** PancakeNotch is still being tested, so expect bugs: some things may not work as they should yet. If something goes wrong, please report it on GitHub.

- **Home.** The Module Menu is now Home: your modules as widgets, all in the open notch at once. Pause a song, start a timer or turn Keep Awake on right there, or click a widget to open its module. There's also a clock, your battery and a number from Statistics.
- **Edit Home in the notch.** Press and hold a widget or gap to move, remove, resize or add widgets. Done, Esc or a click outside finishes; Edit beside Settings opens the full editor.
- **Make it yours.** A new Home page in the PancakeNotch window: drag widgets around (the others make room), pick small, medium or large, add pages (up to three), undo, or start from a ready-made layout. The window's first page is now called Overview.
- **Search for widgets.** A search bar under the Home editor's Widgets heading finds them by name or by a related word, like "music" for Now Playing or "files" for the Shelf. If a match belongs to a module that's off, it says so.
- **Pages when you need them.** The Home editor shows pages with widgets. Use + after the page tabs to add one (up to three); an emptied page disappears.
- **Open on Home.** A new Notch setting, When the notch opens, show, can start the notch on Home instead of the module you used last.
- **Paused music leaves room for Home.** With Last module, the notch opens on Home when your music is paused or nothing is playing. Playing music and things that need you still come first.
- **Learn Home.** A short hands-on lesson shows how Home works.
- **Hold anywhere below Home’s buttons to edit.** The bottom strip and side margins now work too, and holding a widget button won’t press it.
- **A quieter Home editor.** Widget badges, size controls and outlines fade away when its window is inactive, and return when you come back.
- **The whole remove badge works.** Clicking the edge of a widget's − badge removes it, instead of finishing editing.
- **Fixes.** AI Usage's account menu closes when you switch windows, including to the PancakeNotch window, so it no longer keeps the notch open, and Now Playing clears when you close the browser tab that was playing a video.

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
