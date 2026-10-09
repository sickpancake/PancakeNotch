# 0023 — Testing and CI

**Status:** Accepted (2026-10-09)

## Decision
- GitHub Actions on macOS runners for every change: build, unit tests (geometry, state machine,
  Shelf, statistics).
- Hidden **simulated-notch mode** (CI VMs have no notch). CI launches the app in this mode, waits
  ~30 s, measures physical footprint, and **fails if idle > 50 MB**.
- Per release: manual peak-memory checklist on a real notched Mac (music playing, 20 shelf
  items, companion window open) must be < 100 MB.
