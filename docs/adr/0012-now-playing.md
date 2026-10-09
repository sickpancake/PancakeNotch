# 0012 — Now Playing source strategy

**Status:** Accepted (2026-10-09)

## Decision
1. Primary: `ungive/mediaremote-adapter` (BSD-3), pinned version. Runs as a `/usr/bin/perl`
   child process; **its memory counts toward our budget** (ADR-0006).
2. Fallback: AppleScript / ScriptingBridge for Music.app and Spotify (Automation permission
   requested only when the fallback is actually needed).
3. If both fail: the notch still opens normally; the Now Playing area shows a **blurred
   placeholder with a short status message** (e.g. "Music not connected").

## Known limitations
On macOS 27, transport commands only reach the system's "elected" now-playing app
(mediaremote-adapter issue #41). Accepted.

## Risk
Apple may close the `com.apple.perl` loophole at any time; the fallback and placeholder exist for that.
