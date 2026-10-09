# 0011 — Notch states and interaction

**Status:** Accepted (2026-10-09)

## States
1. **Closed** — exactly the hardware notch; solid black; invisible.
2. **Compact** — notch grows left/right "ears" (e.g. album art + visualizer while music plays).
3. **Expanded** — full panel.

Spring animations morph between states. Each module supplies its own compact and expanded views.
Transient events may temporarily take over Compact, then restore the previous content.

## Interaction
- Hover ~150 ms → expand; mouse leaves → collapse after ~300 ms.
- Click → expand.
- Two-finger horizontal swipe while expanded → switch module.
- Dragging a file toward the notch → open directly to Shelf.
- Full-screen apps → hidden unless hovered.
- Optional trackpad haptic on expand.
- Delays and haptics configurable.
