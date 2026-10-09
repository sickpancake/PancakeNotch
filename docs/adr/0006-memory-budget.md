# 0006 — Memory and CPU budget

**Status:** Accepted (2026-10-09)

## Decision
- < 50 MB physical footprint idle; < 100 MB peak (notch expanded, artwork shown, shelf populated).
- ~0% CPU idle; event-driven, no polling loops.
- Measured with `footprint` / Activity Monitor; a release check fails builds over budget.

## Consequences
Modules must be lazily created and release resources when not visible.
