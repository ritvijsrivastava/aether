# Aether M4 audit — findings (2026-10-20)

Full audit of the canvas core after M4 + M4.1b. Verdict: the engine parts that
make it *feel* broken are architectural, not bugs. Ranked by how much they
explain "nothing works as intended".

## A. Core contradictions — the canvas is not actually a canvas

1. **Two coordinate spaces for ink.** A stroke that starts on a page is stored
   in *page space* (`pageId` + local coords); a stroke that starts off-page is
   stored in *canvas space* (`pageId: null`). Eraser, select-move, hit-testing
   and undo each special-case both. Drag a page: page-space strokes move with
   it, canvas-space strokes stay behind. Built for "PDF document with pages";
   wrong for a board.
2. **The view is clamped, not infinite.** `ViewState.clamped()` pins the
   viewport to the pages' bounding box plus one screen of margin. You cannot
   roam into empty space and draw there, and canvas-space ink never grows the
   bounds. "Infinite canvas" and a clamped view cannot both be true.
3. **Undo/redo reloads the world.** Every undo step runs `_reloadAll()`: the
   whole scene is rebuilt and every mark (including base64 stroke points) is
   re-parsed from the DB. Slow with many strokes, wipes live state, and is why
   rapid undo feels broken.
4. **`DocumentSession` is a god object.** 8 sink interfaces, ~850 lines, 8
   hand-written copies of optimistic-update-plus-rollback. One shared
   apply/undo abstraction would delete ~200 lines and the inconsistency.
5. **The screen rebuilds on every saved op.** `bus.changes.listen(setState)`
   rebuilds the whole workspace (CanvasView, overlays, panels) just to refresh
   the Undo button's enabled state.

## B. Features countering each other (interaction bugs, verified in code)

1. **Pen long-press kills strokes.** `_watchLongPress` in `canvas_view.dart`
   fires after 500 ms of a still pen in any tool except Pan. Rest the nib half
   a second while writing → the stroke is cancelled and the radial menu pops.
   Deliberating or drawing dots fights the radial menu.
2. **Auto-hide fights the ink workflow.** `gestureDone` collapses the Ink
   panel after every stroke, but ink is the tool where you change colour/width
   between strokes. With `pressTool` toggling this becomes a hide/show loop.
   The collapse state machine lives in three entry points (`setTool` opens,
   `canvasPressed` collapses, `pressTool` toggles) with different rules for
   keys vs buttons.
3. **Notes route pointers through four mechanisms**: the `interactive` flag,
   `_BodyCover` (manual 500 ms Timer), the pen `Listener` inside the
   TextField, and `onTapOutside`'s stylus exception. Plus three separate
   long-press implementations app-wide.
4. **Selection is cleared in three places** (tool-change listener,
   `onPointerDownOnCanvas`, prune listener) — consistent today, fragile
   tomorrow.
5. **Diagnostics woven into the hot path**: `TouchStats` records and notifies
   from inside the arbiter for every pointer event; the touch-log timer writes
   a file every second; synthetic-doc scaffolding and the stress-ink
   dart-define live in the production screen.

## C. Dead code and orphans

1. `reorderNotes` — removed (its buttons were cut in F15; only tests used it).
2. Notes: `notes/*` (layer, overlay 683 lines, tool, menu), `NoteSink`,
   `NoteActions`, `_pendingLinks`, note timers, keyboard-inset panning.
3. Links: `links/*` (layer, tool, remove overlay), `unlinkNote`/`deleteLink`,
   link re-pointing in `_swapHighlights`.
4. Extract: `extract/*` (controller + panel), `ExtractFilter`/`extractOpen`/
   `extractWidth` in UI state, Markdown exporter, Copy-as-Markdown, `_copied`.
5. Text highlights: `domain/text/*` (page text, selection, codec ~1,000
   lines), `mark_tool.dart`, `highlight_rules.dart`, the PDF text service,
   `flash.dart`, highlight paths in the selection overlay.

## D. What is solid — keep through any rebuild

1. `InputArbiter`: pure, heavily tested, correct structure.
2. `CanvasController` / `ViewState` / painters: notify-without-rebuild design.
3. `CommandBus`: append-only undo with HLC ops — sync-ready, no rewrites.
4. Ink geometry (simplify, stroke building) and the bitmap cache.
5. `PenConfig` pressure curve, tuned from real S Pen strokes.

## E. Cut lines (agreed direction, 2026-10-20)

- **Tier 1**: delete notes, links, Extract, Markdown export, text highlights,
  and the PDF text pipeline. Full-bleed infinite canvas, simple pan/zoom,
  stylus ink with theme-aware default colour. See `m5-tier1-plan.md`.
- **Tier 2**: rebuild the core — one world space, bounds that grow with
  content, undo that applies inverse ops in memory, slim session.
- **Tier 3 (later)**: PDF pages return as optional cards on the board
  (SPEC §21), reusing the kept renderer.

The PDF *renderer* (`pdf/*`, ~1,400 lines) is kept dormant in Tier 1 so boards
can show PDF cards later without rebuilding it.