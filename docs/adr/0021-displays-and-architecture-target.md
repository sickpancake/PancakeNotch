# 0021 — Displays and CPU architecture

**Status:** Accepted (2026-10-09)

## Decision
- Notch UI only on the built-in display. Lid closed / no built-in display → app idles
  (no window, ~0 CPU). Fake notch later (ADR-0008).
- Build for **Apple Silicon (arm64) only** — every notched Mac is Apple Silicon.
