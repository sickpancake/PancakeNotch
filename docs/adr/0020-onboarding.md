# 0020 — Onboarding

**Status:** Accepted (2026-10-09)

## Decision
Short notch-styled first-run flow:
1. Welcome + preview of the notch expanding.
2. **Notch check** — verify the notch window appears and expands correctly on this Mac.
3. Now Playing check ("play a song to test"); on failure shows the ADR-0012 placeholder and why.
4. Launch at login toggle.
5. Automatic updates toggle.

If a check fails, the user is directed to the **Help** section. Automation permission is requested
later, only if the music fallback is needed.
