# 0013 — Shelf

**Status:** Accepted (2026-10-09)

## Decision
- Stores **references** (bookmarks) to files, not copies.
- Persists across relaunch; items whose files are moved or deleted are removed automatically.
- Thumbnails generated lazily via QuickLook, small, cached under a size cap.
- Actions: drag out, AirDrop, Share, Open, Reveal in Finder, Remove, Clear all.
- Limit: 20 items, with a warning when full.
