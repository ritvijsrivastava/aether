# Tier 1 plan — bare infinite canvas (M5)

Owner direction (2026-10-20): forget PDFs and notes for now. The product is an
**infinite, non-clamped canvas on a dot grid** that fills the whole screen,
with simple pan and zoom by fingers and ink by stylus. Findings this builds on:
`audit-m4.md`. **No backward compatibility to maintain.**

## Owner decisions captured

1. **Remove the top bar** — both the app's CanvasTopBar and the Android system
   status bar (clock, battery). The complete screen is canvas.
2. **Everything lives inside the canvas** — floating controls only, no chrome.
3. **Drop the palm/pinch logic** — it does not work properly. Simple rules
   instead: stylus writes, one finger pans, two fingers pinch.
4. **Infinite and non-clamped** — remove `ViewState.clamped()` and the
   scene-bounds margin; roam anywhere, draw anywhere.
5. **Default ink colour follows the theme** — white on the dark board, black
   on a light one.

## Out of scope for Tier 1 (kept dormant, not deleted)

- PDF renderer (`lib/features/canvas/pdf/*`) — stays in the tree, unreferenced
  by the canvas screen, for the boards milestone later.
- Palm rejection diagnostics, radial menu, touch log — deleted outright; a
  better input story returns in Tier 2 if needed.
- The op log / CommandBus / HLC stays as-is (undo still reloads marks; that
  rewrite is Tier 2).

## Slices

### S1 — Strip the non-core (≈ half day)
- Delete notes (layer, overlay, tool, menus), links (layer, tool, overlay),
  Extract (controller, panel, Markdown exporter), text highlights
  (`mark_tool`, `highlight_rules`, `domain/text/*`, PDF text service, flash),
  the action strips, radial menu, note menu, selection overlay's highlight
  paths.
- Slim `DocumentSession` to: ink add, eraser commit, undo/redo, view save.
  Remove `NoteSink`, `NoteActions`, `LinkSink`, `MarkSink`, the note timers,
  `_pendingLinks`, keyboard-inset panning.
- Remove TouchStats, touch-log writing, stress-ink dart-define and the
  synthetic-document branch from the production screen (synthetic scenes move
  to test support only).
- Old documents keep their ink: on load, page-space strokes are translated
  into world space by their page's offset (in memory, no migration).
- Library: hide "Import PDF"; add "New board" that creates a document with no
  pages.

### S2 — Full-bleed canvas UI (≈ 2–3 h)
- Remove `CanvasTopBar`, bottom toolbar, Extract sheet, `_WideBody`/`_CompactBody`
  split. One Scaffold body: the canvas, edge to edge.
- Immersive mode: `SystemUiMode.immersiveSticky` (or edge-to-edge + hide
  status bar), so no clock/battery row. Reveal on system swipe.
- Floating controls drawn over the canvas: a small tool rail (Ink, Erase),
  Undo/Redo buttons, zoom pill (−, %, +, fit). All positioned inside the
  canvas; the canvas keeps its full rect underneath.
- Ink options (colour strip + width) stay as the floating panel; the
  auto-hide state machine collapses to one rule: the panel shows while the
  Ink tool is active and hides when the tool changes. No per-stroke hiding.

### S3 — Infinite, non-clamped view (≈ 2 h)
- Delete `ViewState.clamped()` and every call; pan and zoom are free.
- `Scene.bounds` (cards) no longer constrains anything; "fit" computes a
  content rect from ink strokes (plus pages, while they still exist) and fits
  that; with no content, fit = 100% at origin.
- View persistence keeps working (x, y, zoom saved after 600 ms quiet).

### S4 — Simple input model (≈ 3–4 h)
- Rewrite `InputArbiter` down to rules, no palm machinery:
  - **Stylus / inverted stylus**: applies the active tool (Ink draws; Erase
    erases; the eraser end always erases). Pen button still switches to Erase.
  - **One finger**: pans. Never draws (the "finger draws" setting is removed).
  - **Two fingers**: pinch-zoom about their midpoint + pan, plain centroid
    math. No pair windows, resting-hand logic, or drift tracking.
  - **Mouse (desktop)**: left-drag applies the tool; space+drag, middle-drag
    or right-drag pan; wheel pans; Ctrl+wheel zooms. Trackpad pan/zoom stays.
- Delete the pen long-press radial menu, the finger long-press context menu,
  and the tap-target highlight strip. Pen rests are safe: nothing listens.
- Keyboard: tools, undo/redo, zoom, Escape (cancel the live stroke) stay.

### S5 — Theme-aware ink default (≈ 1 h)
- Ink default colour: `onCanvas` from the tokens — white on the dark board,
  black on light. If the owner has not picked a colour themselves, a theme
  change flips the default; once they pick, it sticks (existing palette
  restore logic, simplified).

### S6 — Tests, goldens, measure (≈ half day)
- Trim the suite: notes/links/extract/highlight tests go with their code;
  arbiter tests rewritten for the simple rules; undo/ink/erase/view tests
  stay. Golden set rebuilt for the full-bleed layout.
- Measure on the S9: pan/zoom frame time, stroke latency, 10,000-stroke page
  with the bitmap cache still in place.

## Test and commit rhythm

- One commit per slice, message style `M5-T1 (S1): …`.
- `flutter analyze` and the (trimmed) suite green before each commit.
- Device check after S2 and S6 (profile APK on the Tab S9).

## Risks

- The strip touches ~30 files and most of the suite; the risk is a half-stripped
  screen — mitigated by doing S1 in one pass and running the suite before S2.
- Immersive mode on Android + keyboard-free app is simple (no text fields left
  after the notes go), so no inset handling should remain.
- Old PDF documents open as "boards with ink translated out of their pages";
  their pages are not drawn in Tier 1. Accepted per "forget PDFs".