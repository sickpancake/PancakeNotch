# 0018 — Statistics

**Status:** Accepted (2026-10-09)

## Decision
v1 categories:
- **Listening** — time listened, top songs / artists / source apps, plays per day.
- **Usage** — notch opens, most-used modules, files shelved / AirDropped.
- **App health** — live and historical RAM / CPU of PancakeNotch itself.

Stored locally in SQLite (system `libsqlite3`, no wrapper dependency); 90-day retention;
"Clear statistics" button. Designed to be **extensible**: modules can contribute their own stats
categories later.
