# Aether: Technical Specification (v1)

Status: **v2 pivot proposed (2026-10-20), section 21; awaiting owner answers (21.7).** Sections 1 to 20 describe v1 as built through M4 (PDF-first); where section 21 conflicts, section 21 wins once approved. Companion documents: `PRODUCT.md` (who and why), `DESIGN.md` (look and components). Decisions marked **[DECIDED]** came from the project owner; **[PROPOSED]** are my recommendations awaiting approval; **[OPEN]** need an answer or a spike.

---

## 1. Goals and non-goals

### 1.1 Goals
0. **[PROPOSED, pivot, see section 21]** Aether is a **general-purpose canvas**: a plain empty board on which you can place PDFs, images, text files, notes, ink and simple shapes, and think freely. PDF annotation is one thing the board does well, not the product.
1. Faithfully reproduce the interaction model of `Aether.dc.html` (infinite canvas, movable document cards, Mark/Ink/Erase/Note/Link/Select/Pan tools, Extract panel, Markdown export) in Flutter. **[DECIDED: port plus UX fixes]**
2. Import and annotate **real PDFs**. **[DECIDED]**
3. Run well on **Android phones and tablets** and **Linux desktop**, with pen, touch, and mouse. **[DECIDED]**
4. **Local-first**: fully functional offline, all data on device, with a data model that can be synced with CRDTs later without a migration. **[DECIDED]**
5. Extreme interactive performance: 60 fps minimum everywhere, 120 fps on 120 Hz hardware, ink that feels immediate.
6. Never lose a mark: continuous autosave, crash-safe storage, full undo/redo.

### 1.2 Non-goals for v1
- Handwriting-to-text conversion **[DECIDED: deferred]**. A recognizer interface is reserved (section 9.6) but unimplemented.
- OCR for scanned PDFs, web articles, slide decks. (Images, Markdown and plain text become supported by the pivot, section 21; Word documents are an open question, 21.7 Q4.)
- A full drawing program: layers, brushes with textures, filters, vector path editing. The drawing set is deliberately small (21.4).
- **Right-to-left and bidirectional text** **[DECIDED: not in v1, 2026-10-19]**. Selection and highlights are built and tested for left-to-right text only. On RTL pages, selection may jump or split words; this goes in the release notes. Revisit after v1.
- Cloud sync, accounts, collaboration (data model is ready; transport is not built).
- Web, iOS, Windows, macOS builds.
- Editing the PDF itself or writing annotations back into the PDF file (export of flattened PDF is v1.1).

### 1.3 Reference hardware
- **Samsung Galaxy Tab S9 + S Pen** (Android tablet, 120 Hz, active stylus with pressure, hover, barrel button). **[DECIDED]**
- **Linux desktop with Wacom-style tablet** (pressure-sensitive pen with eraser end on many models). **[DECIDED]**
- Phone: an **emulator is sufficient for initial testing** **[DECIDED]**; the owner will verify on a real phone later. Until then, phone touch-feel and performance claims are unverified, and acceptance evidence must say "emulator".

---

## 2. Platform and input matrix

| Capability | Android tablet (S Pen) | Android phone | Linux + Wacom | Linux + mouse |
|---|---|---|---|---|
| Draw / mark | Stylus | Stylus if present; else enable "finger draws" | Pen | Mouse (active tool) |
| Pan | Finger drag | Finger drag | Space+drag, middle-drag, scroll wheel / 2-finger scroll | Same |
| Zoom | Pinch | Pinch | Ctrl+wheel, +/- keys, pinch on touchpads | Same |
| Erase | Toolbar tool; S Pen button held; | Toolbar tool | Eraser end (inverted stylus) or tool | Toolbar tool or E |
| Pressure | **Yes, verified (0 to 1, about 500 Hz, plus tilt and hover distance)** | If stylus | **[DECIDED, M0] Yes on native Wayland (0 to 1, 125 Hz); none under X11/XWayland** | No |
| Hover | S Pen hover events | n/a | Pen hover (verify) | Mouse hover |
| Palm rejection | OS + app (section 7.3) | OS + app | n/a | n/a |

**Gate result (M0): Wacom outcome (a) on Wayland, outcome (b) on X11; Wacom has no eraser end events; Tab S9 S Pen outcome (a) with tilt and hover distance. See `docs/spikes/m0.md`.**

**Gate (M0 spike):** before promising pressure ink on Linux, a throwaway app prints raw `PointerEvent` fields (`kind`, `pressure`, `pressureMin/Max`, `tilt`, `buttons`, `device`) for the Wacom on Linux and the S Pen on the Tab S9. Outcomes: (a) pressure + eraser delivered, build as designed; (b) pen arrives as `mouse` with no pressure, ink is constant-width on Linux and the inverted-stylus eraser becomes a toolbar/keyboard action; (c) events are unusable, research a small native plugin (libinput/XInput2) before promising Wacom support. The spec degrades gracefully in all three, so only the Linux ink-quality claim is at risk.

---

## 3. Architecture

### 3.1 Principles
1. **The hot path stays out of the widget tree.** Pointer input, view transform, and the in-progress stroke are driven by `ValueNotifier`/`Listenable` fed straight into `CustomPainter`s (`repaint:`). A pointer-move must never rebuild a widget.
2. **Immutable model, mutable view.** Documents and marks are immutable value objects mutated only by commands. The view transform is a separate fast-changing object.
3. **Everything is an operation.** Every change is a command that produces an operation record. This yields undo/redo, crash-safe persistence, and (later) sync from one mechanism.
4. **Pure Dart core.** Model, geometry, hit-testing, text layout, command stack, and export have no Flutter imports, so they unit-test without a device and could move to an isolate.

### 3.2 Layers and packages (feature-first, one Dart package)
```
lib/
  main.dart, app.dart               bootstrap, ProviderScope, MaterialApp.router
  core/
    geometry/                       Vec, Rect, Matrix helpers, RDP simplification, polygon tests
    spatial/                        uniform-grid index
    id/ hlc/                        UUIDv7, Hybrid Logical Clock
    result/ log/
  domain/                           PURE DART
    model/                          Document, PageRef, Mark (sealed), Link, Category
    commands/                       Command, CommandBus, UndoStack, op log types
    text/                           PageText, Word, Line, selection -> rects
    export/                         MarkdownExporter, JsonExporter
  data/
    db/                             Drift schema, DAOs, migrations
    pdf/                            pdfrx adapter, tile renderer, text extractor
    files/                          app-dir storage, content-addressed PDF store
  features/
    library/                        document list, import flow
    canvas/                         engine (section 5), tools (section 8), overlays
    extract/                        panel, filters, sheet
    settings/
  ui/
    theme/                          tokens from DESIGN.md, ThemeExtension
    adaptive/                       window-size-class scaffold
    widgets/                        pills, chips, tool button, swatches, glyphs
```
**State management: Riverpod** for app/screen state (library, selection of document, filters, settings, extract list, adaptive layout). **[PROPOSED]** The canvas engine owns its own `ChangeNotifier`s/`ValueNotifier`s and is exposed to Riverpod only through coarse providers (e.g. "set of marks changed"), never per-pointer events.

### 3.3 Dependencies (choose and pin at M0; no claim about exact versions here)
| Need | Choice | Notes |
|---|---|---|
| PDF raster + text | `pdfrx` 2.6.x (pdfium) **[DECIDED, M0]**; re-added in M2b. `flutter test` does not run its native-asset hook, so tests use a previously built `libpdfium.so` (or `PDFIUM_PATH`). | Verified on Linux and Android emulator: silent open of owner-password PDFs, tile render 3 to 7 ms, per-char rects, structured reading order (`loadStructuredText`). pdfium binaries are fetched by a build hook on first build (needs network once). See `docs/spikes/m0.md`. |
| Database | `drift` + `drift_dev`/`build_runner`; SQLite via the `sqlite3` 3.x native-assets build | **[DECIDED, M0]** builds and runs on Linux and Android. `sqlite3_flutter_libs` is obsolete under sqlite3 3.x and is not used. |
| State | `riverpod` / `flutter_riverpod` | |
| IDs | `uuid` (v7) | Or tiny in-house UUIDv7. |
| Files/paths | `path_provider`, `file_picker` | Import via system picker; drag-and-drop on Linux (`desktop_drop`). |
| Window mgmt | `window_manager` (Linux) | Min size, title. |
| Icons | `path_drawing` | Draws the prototype's SVG stroke icons from path data; no icon font. |
| Fonts | bundled assets | Figtree + open serif; **no runtime font fetching**. |
| Clipboard | Flutter `Clipboard` | Rich/Markdown via plain text. |
| Share | `share_plus` (Android) | Export file. |
Keep the dependency list short; each package is justified against a hand-rolled alternative.

---

## 4. Data model (CRDT-ready)

### 4.1 Identity and time
- Every entity has a **UUIDv7** id (time-ordered, globally unique, safe to generate offline on any device). Never an incrementing int.
- Every device has a persistent `deviceId`.
- Every change carries a **Hybrid Logical Clock** timestamp `(physicalMs, counter, deviceId)` that is monotonic per device and totally ordered across devices.
- Deletes are **tombstones** (`deletedAt` HLC); rows are never removed during normal operation. Compaction is a later background job.

### 4.2 Coordinate spaces
- **Page space**: PDF points (1/72 in), origin top-left, y down. A page is `width x height` points.
- **Canvas space**: logical px; each card has a `Matrix`-free transform `(x, y)` (position of its top-left; scale fixed at 1.0 in v1; card resize is v1.1).
- **Marks are stored in page space** with a `pageId`, so moving a card changes one number (the card position) and rewrites zero marks. (The prototype shifted every mark when a page moved; that is both slow and a sync-conflict generator.)
- **Free marks** (ink or notes that start off any page) belong to the document's canvas with `pageId = null` and are stored in canvas space.
- `viewport` (pan, zoom) is per-document view state, stored locally, never synced.

### 4.3 Entities
```dart
// domain/model (illustrative; final names settle at M1)
sealed class Mark { Id id; Id docId; Id? pageId; Hlc updatedAt; Hlc? deletedAt; }

class Highlight extends Mark {
  Category category;               // claim | method | question (enum now, user-defined later)
  int startChar, endChar;          // character range in page text (reading order)
  String quote;                    // denormalized text at creation time
  String contextBefore, contextAfter; // ~24 chars each, for re-anchoring
  List<Rect> rects;                // line rects in page space (cache; recomputable)
}
class Ink extends Mark {
  Float32List points;              // x,y,pressure triplets, little-endian
  double width;                    // base width (stroke-time pen width)
  int color;                       // ARGB; default ink
  Rect bounds;                     // cached
}
class Note extends Mark { Offset pos; double width; String text; }   // pos page space or canvas space
class Link extends Mark { Id fromNoteId; Id toHighlightId; }           // many links per note allowed
```
`Category` carries `id`, `name`, `colorValue`, `glyph`. v1 ships three built-ins with stable ids; the schema allows user categories later without migration.

### 4.4 Documents and pages
```
Document { id, title, createdAt, updatedAt, sourceHash, pageCount, hlc }
PageRef  { id, docId, index, width, height, cardX, cardY, hlc }   // card position on canvas
PdfFile  { sourceHash (sha256), path, byteLength, importedAt }     // content-addressed, deduplicated
```
Each PDF page is its own movable card (as in the prototype, which models "Paper p. 1" and "p. 2" as separate cards). Default import lays pages out in a column with 80 px gaps, centred; a "Grid" action to re-flow them is planned.

### 4.5 Operation log (the sync-ready core)
All edits are **operations** appended to an append-only log; entity tables are materialized snapshots of the log for fast reads.
```
Op { opId (UUIDv7), deviceId, hlc, entityId, entityKind, kind: create|setField|delete|restore,
     field?, value? (JSON/binary), txGroupId }   // txGroupId groups one user action
```
- A user action (e.g. "Delete 12 selected marks") is one `txGroupId` so undo is atomic.
- **Undo/redo are new operations** (inverse ops), not log mutation. This keeps the log append-only and mergeable.
- Merge rule v1 (single device): apply in HLC order. Merge rule for later sync: **last-writer-wins per (entity, field)**; tombstones win ties on delete vs edit unless a later `restore` exists. Note body `text` is the one field that will want a real text CRDT later; it is isolated behind a `TextField`-typed value so it can be swapped without touching the rest.
- **[OPEN, later]** Choice of CRDT library/transport is a separate spike at sync time; this spec only guarantees ids, HLCs, tombstones, and the op log exist.

### 4.6 Persistence schema (Drift/SQLite)

**As built (M1):** documents, pages, marks, links and categories share **one `entities` table** (id, kind, indexed `doc_id`/`page_id`/`mark_type`/bounds columns, JSON `fields` and `field_hlcs`, `life_hlc`, `deleted`, `created_hlc`) instead of the separate typed tables listed below, because they share one merge rule (last-writer-wins per field) and one materializer. Typed models (`Document`, `PageRef`, `Highlight`, `Ink`, `Note`, `Link`) are read views over an entity. `ops`, `pdf_files`, `device`, `settings` and `view_states` exist as specified. Ink points are stored base64 inside op values for now; large strokes can move to a blob table later without changing callers. The schema is dumped to `drift_schemas/` and guarded by a migration test.

Tables: `documents`, `page_refs`, `pdf_files`, `categories`, `marks` (one row per mark: `id, doc_id, page_id, kind, category_id, payload BLOB/JSON, bounds_x0..y1, updated_hlc, deleted_hlc`), `links`, `ops` (append-only), `device`, `settings`, `view_state` (local-only), plus an R-tree/indexed bounds columns for fast region queries. Ink payloads are packed binary blobs, not JSON.
- WAL mode; write transactions batched per user action.
- **Autosave** means every command commits its op + snapshot rows in one transaction immediately (sub-millisecond), not on a timer. Ink in progress is held in memory and committed on pointer-up; the partial stroke is also journaled every ~250 ms so a crash loses at most one in-flight stroke's tail.
- Migrations are versioned and tested with fixtures from every prior schema version.

### 4.7 Files
PDFs are copied into the app directory under `pdfs/<sha256>.pdf` on import (so the original can move or disappear and so identical files dedupe). A document references its `sourceHash`. Rendered tiles are a **cache**, never source of truth, and live under the platform cache dir with a size cap.

---

## 5. Canvas engine

### 5.1 Widget structure
```
CanvasScreen
 └─ LayoutBuilder / adaptive scaffold
     ├─ CanvasView (Stack, ClipRRect 24px)
     │   ├─ Listener                          raw pointer events (section 7)
     │   ├─ RepaintBoundary: GridPainter      repaint: viewListenable
     │   ├─ RepaintBoundary: PagesPainter     page tiles + highlights beneath text; repaint: view | tile arrival | highlight change
     │   ├─ RepaintBoundary: InkPainter       committed ink, per-page cached pictures; repaint: view | ink change
     │   ├─ NotesLayer                        positioned widgets inside Transform (only notes in/near viewport are built)
     │   ├─ LinkPainter                       link lines
     │   ├─ RepaintBoundary: LivePainter      in-progress stroke / highlight / lasso / link drag; repaint: liveNotifier only
     │   └─ Overlays: ToolRail, ZoomPill, SelectionActions   (normal widgets, outside the Transform)
     └─ ExtractPanel / bottom sheet
```
Painters share one `ViewTransform` (`Matrix4` + `Listenable`). Each painter applies the canvas transform itself and culls to the visible world-space rect. Overlay widgets are in screen space and never rebuild on pan/zoom.

### 5.2 View transform
- State: `{x, y, zoom}`; range zoom **0.2 to 3.0** (as prototype); `fit()` computes zoom to content bounds with a margin (not the prototype's height-only formula).
- `zoomAt(anchor, factor)` keeps the world point under the anchor fixed (prototype math, kept).
- Wheel/scroll: scroll pans, Ctrl+scroll zooms with `exp(-dy * 0.01)`; trackpad pinch maps to `PointerScaleEvent`/`PointerPanZoom` events.
- **Inertia**: finger-pan release applies a friction fling (`FrictionSimulation`), cancelled by any new touch. **[PROPOSED]**
- Animated moves (jump-to-mark, fit) use a short ease-out; honor system "remove animations" (jump instantly).

### 5.3 Page rendering (PDF)
- A page's content is a **bitmap from pdfium**, rendered in **tiles** (e.g. 512x512 px) at a **level of detail** chosen from `zoom x devicePixelRatio`, quantized to powers of sqrt(2) to limit cache churn.
- Visible tiles at the best available LOD are drawn; missing tiles draw the nearest cached coarser tile (scaled up) immediately, then crossfade when the sharp tile arrives. The user never sees blank paper while scrolling.
- Rendering runs off the UI thread (pdfium in an isolate / the plugin's worker); requests are prioritized by distance from viewport center and **cancelled** when scrolled away. Pan/zoom never waits on a render.
- Cache: LRU, memory cap **[PROPOSED]** 192 MB Android tablet / 128 MB phone / 384 MB Linux, disk-backed thumbnails (about 100 px wide) per page for the far-zoom view and the library.
- When zoom is below about 0.35, draw page thumbnails instead of tiles.
- Page bitmaps are drawn with `FilterQuality.medium` (low while a gesture is active, upgrading when idle).

### 5.4 Highlights
- Painted **beneath** page text? A rasterized PDF page has its text baked in. To keep text full-contrast without a blend layer, highlights are drawn with `BlendMode.multiply` **only against the page's own tile region** inside a single `saveLayer` per page that has visible highlights, OR drawn as a thin translucent fill on top at 50% opacity. **[PROPOSED]** Start with multiply over the tile (matches the prototype's look and keeps text dark); measure; fall back to plain translucent fill on any device where it misses the frame budget. This is a deliberate, measured deviation from the DESIGN.md ideal "paint under text", which is only possible for app-rendered text, not for PDF bitmaps. DESIGN.md will be updated at M3 to say so.
- Highlight rects come from the stored `rects` (page space), with `contextBefore/After` used to re-anchor if the text layer changes.

### 5.5 Ink
- **Capture**: raw points + pressure into a growing `Float32List` in the live buffer; on each frame the `LivePainter` draws the path (quadratic midpoint smoothing as in the prototype, upgraded to variable-width ribbon when pressure varies).
- **Prediction** (Android): extend the live stroke with 1 to 2 extrapolated points (from velocity), drawn lighter and discarded when real points arrive. This hides about one frame of latency.
- **Coalescing**: use all coalesced/historical points per event so fast strokes aren't polygonal.
- **Commit** (pointer-up): simplify with Ramer-Douglas-Peucker at tolerance about 0.15 px / zoom, keep pressure, store, and rebuild that page's ink `Picture` only.
- **Rendering committed ink**: each page keeps a cached `ui.Picture` of its ink; a pan/zoom replays pictures (cheap display lists), culled by page visibility. Editing ink invalidates only the affected page's picture. Pages with extreme ink (above a threshold) are additionally tiled into picture chunks.
- **Latency budget**: input event to first pixel at most 1 frame (about 8 ms at 120 Hz). Flutter on Android has no front-buffer rendering path; if measured latency on the S Pen is unacceptable, the escape hatch is a small platform view/native overlay for the in-progress stroke **[OPEN, only if measurements demand it]**.

### 5.6 Notes layer
Notes are real widgets (editable text fields), positioned inside the canvas `Transform`. Only notes intersecting the viewport (plus margin) are built. At very low zoom (below about 0.35) notes render as non-editable painted chips. Editing: tap a note to focus its field; the field's own focus and IME handling apply. On Android the soft keyboard insets pan the canvas so the note stays visible.

### 5.7 Hit-testing and spatial index
- A **uniform grid** per page (cell about 128 page-points) indexes mark bounds. Queries for erase, link targeting, lasso, tap-to-select, and "marks in viewport" touch only nearby cells: O(local), not O(all marks).
- Ink erase tests segments against the eraser radius `14 / zoom`; v1 erases **whole strokes** by default and offers **partial erase** (splitting a stroke) as a toggle in the eraser options **[PROPOSED]**.
- Highlight hit-test uses line rects with a 10 px tolerance.

---

## 6. PDF pipeline

### 6.1 Import
1. User picks a file (system picker on both platforms, plus drag-and-drop on Linux, plus Android "Open with / Share to Aether" intent).
2. Hash (sha256, streamed, off the UI thread). If a PDF with that hash exists, reuse it and create a new `Document` or open the existing one (ask once: "Open existing" vs "Import as new copy").
3. Copy into the app store, open with pdfium, read page count and sizes.
4. Create `Document` + `PageRef`s (row layout), generate page-1 and per-page thumbnails lazily, and open the canvas immediately; text extraction continues in the background per page.
5. Encrypted/password PDFs: prompt for password; failure shows a plain error. Corrupt or oversized PDFs fail gracefully with a message, never a crash.

### 6.2 Text layer (the highlighting substrate)
- Per page, on first need and then cached to disk, extract characters with their rects (pdfium text page). Build:
  - `Word`: text, char range, rect (union of char rects).
  - `Line`: words grouped by baseline/y-overlap and x-continuity; each line has a rect.
  - `PageText`: ordered words/lines plus a char-index to word lookup. Stored compactly (binary), not re-derived each launch.
- **Reading order** in v1 is the PDF content-stream order refined by line grouping. Multi-column and sidebar layouts may select in a surprising order; **known limitation**, surfaced in release notes. A column-detection pass is a v1.x improvement.
- **Selection from drag**: pointer-down hit-tests to the nearest word (within tolerance), pointer-move extends to the nearest word in reading order, producing a char range; the range converts to per-line rects (merging adjacent words on a line). Dragging across lines yields multiple rects; this fixes the prototype's single-line limitation.
- **Snapping**: highlight rects snap to line top/bottom of the covered words, with consistent height per line.
- **Fallback regions**: where there is no text (scanned page, figure), the Mark tool becomes a free rectangle highlight with an "(image region)" quote placeholder; Extract shows a small page crop thumbnail instead of a quote. **[PROPOSED]**
- **Quote text**: the extracted text is normalized (collapse whitespace, de-hyphenate line-end hyphens, ligatures expanded), keeping the raw range for re-anchoring.

### 6.3 Large documents
Pages beyond the viewport cost nothing: no bitmap, no text (extracted lazily), only `PageRef` rows. A 500-page PDF imports in about a second (open + page sizes); first page is visible immediately.

---

## 7. Input handling

### 7.1 Raw pointers, not gesture recognizers
A single `Listener` wraps the canvas and receives `PointerDown/Move/Up/Cancel/Hover/Signal`. A small **input arbiter** (pure Dart, unit-tested with scripted event sequences) owns the state machine; no `GestureDetector`, `Dismissible`, or `InteractiveViewer` competes for the same pointers. Overlay controls (tool rail, notes' text fields) sit above the `Listener` in the hit-test order and receive their own events.

### 7.2 Pointer kinds and intent **[DECIDED principle: pen marks, finger moves]**
| Kind | Default behavior |
|---|---|
| `stylus` | Applies the active tool. Barrel button held: temporary Erase **[PROPOSED]**. |
| `invertedStylus` (eraser end) | Erase, regardless of active tool; returns to the previous tool on lift. |
| `touch`, 1 finger | Pan. Never draws. Tap on a mark selects/focuses it (see 8). |
| `touch`, 2 fingers | Pinch zoom + pan (centroid). |
| `mouse` | Applies the active tool with the primary button; middle button or Space = pan; wheel = pan; Ctrl+wheel = zoom; secondary button = context menu. |
| `trackpad` | Scroll pans, pinch zooms (via pan-zoom events). |
**[DECIDED]** A finger is for pan, scroll, and zoom, never for marking. A **"Finger draws"** setting exists but is **off by default** and is never switched on automatically; when enabled, single-finger touch applies the active tool and two fingers still pinch/pan. Consequence to be aware of: on a phone with no stylus, marking is only possible after the user turns this setting on (the compact layout shows a one-time hint pointing to it when no stylus has been seen).

### 7.3 Palm rejection
Layered, in priority order:
1. The OS/hardware rejects contacts while the stylus is in hover/contact range. **Verified on the Tab S9: a resting palm produced zero touch events.** This is the primary mechanism; the layers below are a safety net.
2. **Pen-in-range lockout**: while a stylus hover or contact is active, and for **250 ms** after it leaves, new `touch` pointers are ignored (prototype only blocked during contact).
3. **Large-contact rejection**: touch with `radiusMajor` above a threshold (about 28 dp) is ignored.
4. If a touch that started as a pan becomes a stylus-down within 150 ms, the touch gesture is cancelled and not applied.
Everything is configurable via a hidden constants table so it can be tuned on the Tab S9.

### 7.4 Gesture state machine
States: `idle`, `pan`, `pinch`, `draw(tool)`, `dragCard`, `dragNote`, `lasso`, `link`, `marquee`. Transitions are table-driven; every pointer-down resolves to exactly one state; pointer count and kind changes (e.g. second finger arriving during a pan) transition to `pinch` and back, as in the prototype. All math in world space via `ViewTransform.screenToWorld`.

### 7.5 Event rate
Use `PointerEvent` batching: process on the next frame (not per event) for view changes; for ink, consume all events but repaint once per frame. Request the highest available refresh rate on Android (`Display.Mode` high refresh via `flutter_displaymode`-equivalent or manifest flag) **[PROPOSED]** so the S9 runs at 120 Hz.

### 7.6 Keyboard (desktop and tablets with keyboards)
| Key | Action |
|---|---|
| Space (hold) | Temporary Pan |
| H / M / P / E / N / L / S | Pan / Mark / Ink (Pen) / Erase / Note / Link / Select |
| 1 / 2 / 3 | Meaning: Claim / Method / Question |
| Ctrl+Z / Ctrl+Shift+Z or Ctrl+Y | Undo / Redo |
| Ctrl+C | Copy selection (or, with nothing selected, copy Extract as Markdown) |
| Del / Backspace | Delete selection |
| Ctrl+0 / Ctrl+1 / +/- | Fit / 100% / zoom |
| Ctrl+F | Search in Extract (v1.1) |
| Esc | Cancel gesture / clear selection / blur note |
| Ctrl+O / Ctrl+W | Import PDF / back to library |
Shortcuts never fire while a text field has focus (except Ctrl+Z inside it, which edits text). A shortcut cheat sheet opens with `?` and appears in tooltips.

---

## 8. Tools (behavior, with UX fixes called out)

| Tool | Behavior in v1 | Fix over prototype |
|---|---|---|
| **Pan** | Drag to move view. | Fling inertia. |
| **Mark** (highlight) | Drag over text: snaps to words, spans lines, uses selected meaning; tap a word: selects the word; double-tap: sentence **[PROPOSED]**. On release, creates a `Highlight` and it appears in Extract. | Real snapping and multi-line; text-anchored. |
| **Ink** | Freehand with pressure; width 1 to 8 (stroke setting); ink color from a small palette (default Warm Ink). | Pressure, simplification, per-page cache. |
| **Erase** | Hold and drag; removes strokes and highlights touched. Partial erase toggle. Eraser end/button invokes it transiently. | Partial erase option. |
| **Note** | Tap to place; field auto-focuses; drag by header to move; resize from the corner; delete via 48dp control; empty notes are discarded on blur. | Movable, resizable, empty-note cleanup. |
| **Link** | Drag from a note to a highlight (either direction); snaps to the nearest target within 24 dp, with a visible target halo while dragging; a note may link multiple highlights; tap a link line to select and delete it. | Multi-link, snapping, deletable. |
| **Select** (lasso) | Draw around any marks (ink, notes, highlights); selected marks get a dashed outline and an action pill: **Move, Recolor, Delete** (Duplicate later). Tap empty canvas to deselect. Marquee (rectangle) selection with a mouse via Shift+drag. | Selects all mark types, acts on them; "Convert to text" removed. |
| **Drag card** | Drag the handle above a card; marks move with it for free (stored in page space). | O(1) instead of O(marks). |

**Contextual actions**: long-press (touch) or right-click (desktop) on a mark opens a small menu (Change meaning, Add note, Copy quote, Delete).

**Meaning picker**: sticky; choosing a meaning switches to Mark (prototype behavior, kept).

---

## 9. Command system

### 9.1 Commands
`Command` has `apply()`, `inverse()`, and `toOps()`; all state changes go through `CommandBus.run(cmd)`. Examples: `AddHighlight`, `AddInk`, `MoveMarks`, `MoveCard`, `DeleteMarks`, `RecolorHighlights`, `EditNoteText`, `AddLink`.

### 9.2 Grouping and coalescing
- Drags (move, resize) coalesce into one command on pointer-up.
- Note text edits coalesce by time (about 800 ms idle) or by focus loss into one command.
- Lasso actions on N marks are one command.

### 9.3 Undo/redo
Per-document stacks, in memory, rebuilt from the op log on open limited to the last N (about 200) transaction groups. Undo emits inverse ops (log stays append-only). Buttons in the top bar (Undo, Redo) and Ctrl+Z / Ctrl+Shift+Z. A SnackBar offers "Undo" after destructive actions (Delete selection, Delete document).

### 9.4 Deletion model
Delete = tombstone. Deleted documents move to a "Recently deleted" area in the library for 30 days **[PROPOSED]** before the PDF blob is purged (blob purged only if no other document references the hash).

### 9.5 Concurrency and isolates
DB writes run on a background isolate via Drift's isolate support; the UI isolate does optimistic in-memory updates and the write acknowledgement is asynchronous. PDF rendering and text extraction run in worker isolates. No synchronous disk I/O on the UI thread.

### 9.6 Reserved extension point (not built)
`abstract class InkRecognizer { Future<String> recognize(List<Ink> strokes); }` with an Android ML Kit and optional cloud implementation slot, and the Select action pill reserves a space for "Convert". **[DECIDED: deferred]**

---

## 10. Export

- **Copy as Markdown** and **Save .md** **[DECIDED, v1]**: same format as the prototype, extended:
```
# <Document title>

## Claim
- "<quote>" (p. 1)
## Method
- "<quote>" (p. 2)
## Question
- "<quote>" (p. 4)
## Notes
- <note text>  (on "<linked quote>", p. 2)
```
Grouped by meaning (default) or in reading order (option); page numbers included; notes list their linked quotes; ink-only regions are omitted unless the user opts into "include sketches" (v1.1: images).
- **Share** (Android share sheet) and **Save as file** (Linux file dialog).
- **JSON export** of the full document model for backup/portability (v1).
- **Flattened PDF with annotations** is **v1.1**.
- Markdown output is generated by a pure function in `domain/export` with golden-file tests.

---

## 11. Application structure and navigation

### 11.1 Screens
1. **Library** (home): grid/list of documents with first-page thumbnails, title, page count, last opened, and mark count; "Import PDF" is the single primary action (FAB on Android; primary pill on desktop). Search by title. Sort by recent. Swipe/menu: Rename, Delete (to Recently deleted). Empty state: a short invitation to import (copy TBD), no fabricated sample document except an optional "Open sample" bundled PDF **[PROPOSED]**.
2. **Canvas** (document): the main workspace.
3. **Settings**: Finger draws, palm rejection strength, highlight style (multiply / flat / pattern for color blindness), Extract order, theme (Light / Dark / System), dim-page mode, "show input indicator". Low-frequency; one screen.

### 11.2 Navigation rules (Material 3 / Android)
- Predictive Back and system Back always work: Canvas to Library; closes sheets/menus first; never traps.
- Edge-to-edge with insets (status, navigation bars, cutout, IME).
- Library on expanded width may use a navigation rail (Documents, Settings); compact uses a simple app bar. Router: `go_router` **[PROPOSED]** with typed routes.

### 11.3 Adaptive layout (window-size classes)
| Class | Width | Layout |
|---|---|---|
| Compact | under 600 dp | Full-bleed canvas; bottom toolbar (Mark, Ink, Note, Erase, More); Extract = modal/standard bottom sheet with 3 snap points; top bar minimal |
| Medium | 600 to 1100 dp | Tool rail left (vertical); Extract as collapsible side sheet; default open in landscape |
| Expanded | over 1100 dp | As prototype; Extract resizable (280 to 480); hover tooltips; shortcut hints |
Layout is driven by `LayoutBuilder` on the **window**, not device type, so Linux window resizing and Android split-screen/foldables just work. Rotation, resize, and multi-window preserve view state. Minimum Linux window 800x520.

### 11.4 Extract panel behavior
- Header: count + filter chips (All, Claim, Method, Question, Notes); counts per chip.
- List virtualized (`ListView.builder` with `itemExtent` estimation); items grouped optionally by page.
- Tap item: **Jump** (animated pan/zoom to center the mark, at least 90% zoom) and briefly pulse the mark on canvas. Long-press/right-click: menu. Swipe-to-delete on touch with Undo snackbar.
- While marking, the new item animates in and the panel scrolls to it only if the panel is open and the user is not scrolling it.
- Reverse jump: tapping a mark on the canvas highlights and scrolls to its Extract item.
- Screen-reader order: list of marks with "Claim, page 2: <quote>" labels; this is the accessible equivalent of the visual canvas.

---

## 12. Theming and design tokens

- A `ThemeExtension<AetherTokens>` holds all tokens from `DESIGN.md` (colors, radii, shadows, type roles, mark colors with light/dark variants). Material 3 `ColorScheme` is constructed *from* the tokens (primary = Lamplit Indigo, surface = Panel Ivory, etc.) so stock Material components (buttons, chips, sheets, snackbars, dialogs) inherit the brand while following M3 structure.
- Static brand scheme by default. **Dynamic Color (Material You) is off** **[PROPOSED]**: the three meanings and the paper world must not shift with the wallpaper. Offered as an opt-in setting for chrome only.
- Light/Dark/System; dark values finalized and contrast-checked at M1.
- Custom controls (tool rail, zoom pill, handle tab, note) are built with the same tokens and verified against the 48 dp / 12 sp floors.
- Fonts bundled; text uses `TextTheme` roles mapped from DESIGN.md; sizes in sp (Flutter logical px honor the system text scale).
- Motion: durations 120 to 240 ms, standard Material easing for sheets and chips; reduced-motion = instant.

---

## 13. Performance budgets (acceptance criteria)

Measured on Tab S9 (Android, profile mode) and the Linux desktop; failing any is a bug.

| Scenario | Budget |
|---|---|
| Pan/zoom, 1 doc, 20 pages, 2,000 marks | 120 fps target on S9, 60 fps minimum; no frame over 16.6 ms (build) / 8 ms raster at 120 Hz |
| Ink while drawing, page with 10,000 strokes | stable 60 fps; input-to-pixel at most 2 frames at 60 Hz (at most 1 at 120 Hz with prediction) |
| Cold start to library | under 1.5 s Android, under 1.0 s Linux (release) |
| Open a 200-page PDF to first page visible | under 800 ms; no blank page flash during pan (coarse tile shows first) |
| Highlight drag-select on a text page | selection updates every frame; hit-test under 1 ms |
| Commit any single mark | under 5 ms on UI isolate, DB write async |
| Memory, 200-page PDF | at most 400 MB resident Android tablet (tile cache capped) |
| Jank in Extract scroll, 5,000 items | 60 fps |
| App size (Android release APK per-ABI) | under 40 MB (pdfium dominates) |

Engineering practices: profile-mode traces in CI-like runs; `RepaintBoundary` audits; avoid `saveLayer` except where specified; `Picture` caching for static layers; precomputed word/line indexes; no per-frame allocation in painters (reuse `Paint`, `Path`); isolate for heavy work.

---

## 14. Accessibility and inclusion

- Targets at least 48 dp; type at least 12 sp, scaling with system font size (test at 1.3x and 2.0x).
- Meaning is never color-only: glyph + text label everywhere; optional hatch/dot highlight patterns for color blindness.
- Contrast: all text and essential icons at least AA (4.5:1 / 3:1) in both themes; verified by a token contrast test.
- Screen readers (TalkBack on Android, Orca on Linux): library, Extract, tools, and menus are fully labelled; the canvas is announced as a drawing area with the count of marks and a pointer to the Extract list.
- Keyboard-only operation on desktop for everything except freehand ink; visible focus ring (2 px indigo).
- Motion: respect "remove animations".
- Left-handed mode: tool rail and Extract can swap sides **[PROPOSED]**.

---

## 15. Testing strategy

| Layer | What | How |
|---|---|---|
| Unit (pure Dart) | geometry, RDP, spatial index, text selection, command/undo, HLC, markdown export | `flutter test`, property tests for undo (apply then undo = identity) and selection |
| Input arbiter | scripted pointer sequences: pen+touch, palm during pen, pinch to pan transitions, eraser end, mouse middle-drag | pure Dart with fake events |
| Widget | adaptive layouts at compact/medium/expanded, Extract filters, empty states, text scale 2.0 | `testWidgets` |
| Golden | tokens, key components, canvas with fixture marks, light/dark | `matchesGoldenFile` on one pinned platform to avoid font drift |
| Persistence | migrations from every prior schema, op-log replay equals snapshot, crash-resume of ink journal | in-memory + file DB tests |
| Integration | import PDF, mark, restart app, marks present, undo works | `integration_test` on Linux desktop and Android device |
| Performance | scripted pan/zoom/ink on synthetic big docs, frame timings | `flutter drive` timeline summaries, thresholds from section 13 |
| Manual device pass | S Pen on Tab S9 (pressure, hover, button, palm); Wacom on Linux; phone layout | checklist per milestone, with `adb exec-out screencap` and Linux screenshots as evidence |
Fixture PDFs: a text-heavy paper, a two-column paper, a scanned (no text) page, an encrypted PDF, a huge PDF (500 pages), a PDF with unusual fonts (RTL is a v1 non-goal). **Supplied by the owner:** `test/fixtures/mapreduce/mapreduce.pdf` (Dean and Ghemawat, "MapReduce", 13 pages, US Letter 612x792 pt, two-column body with a single-column title block, figures and tables, produced by QuarkXPress). It is flagged as RC4-encrypted with an empty user password (copying allowed, editing not), so it doubles as the "encrypted PDF" case: the importer must open owner-password-only files silently and only prompt when a user password is actually required. It is a third-party paper, so it is a local test fixture and should not be committed or redistributed. Still to generate: a scanned (no text) page, a user-password PDF, a 500-page PDF, and an RTL/unusual-fonts PDF. The sample document remains original content. **[OPEN for the remaining cases]**

---

## 16. Security, privacy, and robustness

- No network permission requested in v1 (Android manifest omits INTERNET). Privacy statement: nothing leaves the device.
- Imported PDFs are untrusted input: parse only via pdfium in a worker isolate; time/size limits; exceptions never crash the app; no JavaScript execution; external links in PDFs are ignored in v1.
- App-private storage for PDFs and DB (Android scoped storage; Linux XDG data dir). Export writes only where the user chooses.
- Crash safety: SQLite WAL, transactional commits, ink journal. A "safe mode" opens the library even if one document's data is corrupt.
- Logging: local, redactable, no document text in logs by default.

---

## 17. Build, tooling, and environments

- Flutter stable (project currently on 3.47.7, Dart ^3.13.5). Lints: `flutter_lints` plus stricter project rules (`prefer_const`, no `print`).
- **Android**: minSdk 24 and targetSdk 36 **[DECIDED, M0]**; release builds split per ABI; R8 enabled; edge-to-edge and predictive-back opt-ins in the manifest; high refresh rate hint.
- **Linux**: GTK3 + clang + cmake + ninja + sqlite dev packages on Fedora; `.desktop` entry, icon, and an optional Flatpak/AppImage later (packaging is **[OPEN]**, not v1-blocking). Verify HiDPI scaling and Wayland and X11 (KDE Plasma on Fedora 44 noted).
- App name `Aether`; application id **`com.ritvijsrivastava.aether`** (reverse of `aether.ritvijsrivastava.com`) **[DECIDED]**, applied to Android `applicationId`/namespace and the Linux `APPLICATION_ID` at M0.
- The web/ios/macos/windows runner folders were **removed** **[DECIDED, done]** (recoverable from git history).
- Distribution is **personal use first** **[DECIDED]**: sideloaded APK and a local Linux build. Play Store/Flathub packaging, signing, and store listings are out of scope for v1; pdfium and font license notices are still bundled in an in-app "About / licenses" page.
- CI: out of scope to set up unless asked, but all checks are runnable via a single `make verify` / script: analyze, test, goldens.

---

## 18. Milestones and acceptance

Each milestone ends with a **review stop** where you try it on the Tab S9 and/or Linux.

| M | Scope | Acceptance |
|---|---|---|
| **M0** Foundations and spikes | Flutter doctor green for Android + Linux; remove unused runners (if approved); pointer-event spike on S Pen and Wacom; pdfrx/pdfium smoke test on both OSes (render a page, extract char rects); Drift smoke test on both; pick minSdk/app id | Written spike report with raw event samples; go/no-go on Linux pressure; PDF render + text rects confirmed on both |
| **M1** Shell, theme, data foundations | Tokens, theme extension, bundled fonts, light/dark, adaptive scaffold (3 classes) with placeholder content, Library with empty state, Drift schema, ids/HLC/op log with tests | Layouts correct at 360, 600, 840, 1280 dp and at 1.3x and 2.0x text scale; dark theme contrast test passes; migrations and op log tests green |
| **M2** Canvas engine | View transform, pan/pinch/wheel/keys, grid, card drag, PDF tile renderer with LOD, import flow, zoom pill, fit | Open a 200-page PDF; pan/zoom at the section 13 budgets on S9 and Linux; no blank pages |
| **M3** Text and marks | Text layer extraction, word/line snapping, multi-line highlights, Extract list with filters, jump, Markdown copy | Drag-select matches expected text on fixture PDFs; Extract matches marks exactly; export golden tests |
| **M3.1** Follow-ups (small, no review stop; **done**, see `docs/m3.1.md`) | Register items R1 to R4: rotated-page correctness, missing fixtures (scanned, rotated), text no longer queues behind tiles, selection perf check | Rotated PDF highlights land on the right words (test); scanned and rotated fixtures exist; text for visible pages is ready before first touch on the S9 |
| **M4** Ink, notes, links, select, undo | Pressure ink, prediction, erase (whole + partial), notes (move/resize), links (multi, snap), lasso + actions, full command stack; **plus register items R5 to R13 and R33** | Undo/redo property tests; ink budgets met; palm rejection verified on S9 |
| **M4.1** Fix pass (**proposed**) | Owner fixes F1, F2, F6 to F10 on the existing canvas; no data model change (R38, R39, R43 to R47) | Each fix has a test; palm test on S9 passes; owner re-checks the ten items |
| **M4.2** Boards (**proposed**) | Data model pivot (21.2): Board, Source, Card; migration of existing documents; Library lists boards; New board; Add menu; paste (text and image); free text blocks; z-order, resize, duplicate for every card (R40, R42, R47) | Existing documents open unchanged as boards; blank board works; kill -9 safe; **review stop** |
| **M4.3** More import types (**proposed**) | Image, Markdown, plain text cards; text cards share the text-layer and highlight pipeline; drag-and-drop on Linux, share-to on Android (R41) | Highlight and Extract work on a Markdown card; image cards take ink and notes |
| **M4.4** Drawing basics (**proposed**) | Shapes (line, arrow, rectangle, ellipse), hold-to-straighten, fill and stroke colour, marker (translucent) stroke, shape text label (21.4) | Draw a diagram without leaving the app; shapes obey undo, select, move, recolor; **review stop** |
| **M5** Persistence and library | Autosave, crash recovery, reopen, library (thumbnails, search, rename, recently deleted), JSON backup, share/save; **plus register items R14 to R19** | Kill -9 mid-stroke loses at most the tail of one stroke; round-trip export/import identical |
| **M6** Polish, accessibility, release | Screen-reader pass, keyboard pass, motion, empty/error states, settings, perf profiling, release builds (APK split + Linux bundle); **plus register items R20 to R32 and R34 to R37 (R22 closed)** | All budgets in section 13; a11y checklist; no analyzer warnings; release artifacts install and run on both |

**Stop rules (updated by the pivot):** after M2 (canvas feel), after M4 (pen feel; **done, plus the ten fixes F1 to F10**), after M4.2 (do boards feel right?) and after M4.4 (is the drawing set enough?) I stop for your hands-on review before building on top.


### 18.1 Carry-forward register (added after M3)

Everything an earlier milestone report or this spec marked "later", "unverified", "not exercised" or "known limitation", with the milestone that now owns it. Nothing may stay in a report's "known gaps" without a row here. An item is closed only when its "done when" is true and the report says so.

| ID | Item | Came from | Owner | Done when |
|---|---|---|---|---|
| R1 | Rotated pages: highlight rects use pdfrx's rotation handling with no test | M3 | M3.1 **(closed)** | Boxes sit on the rendered ink for /Rotate 0, 90, 180, 270 and a CropBox not at the origin (`page_text_rotation_test.dart`). Sideways and upside-down text is R32 |
| R2 | Fixtures still missing: scanned (no text) page, rotated page, unusual fonts (SPEC 15; RTL dropped with R22) | M0, §19.10 | M3.1 **(closed, except unusual fonts → M6 with R20)** | `tool/make_test_pdfs.py` writes `rotated.pdf` and `scanned.pdf`; both used by tests |
| R3 | Text extraction can queue behind tile renders after a big zoom (one pdfium worker) | M3 | M3.1 **(closed)** | Measured on the S9: cold extraction 14 ms/page, no mark ever waited (also right after a zoom tap and right after a flick). Overlay now shows extract time and any wait; text is also warmed when the Mark tool is chosen. No tile gating needed: at most 2 tile renders are ever queued ahead of a text request |
| R4 | Drag-select hit-test under 1 ms and mark commit under 5 ms on the UI isolate (§13) never measured | M3 | M3.1 **(closed)** | Dense 3,000-word page: wordAt 1.4 µs, wordNear 0.5 µs, a full-page drag update 0.34 ms, whole-page selection 1.2 ms, sentence 2.2 ms; addHighlight 0.03 ms (`selection_perf_test.dart`, document session test) |
| R5 | Eraser end (`invertedStylus`) never observed on Linux; treated as a toolbar tool | M0 | M4 **(code done; hardware check at the M4 review)** | The eraser end and the barrel button resolve to Erase for a stroke (tested). Owner confirms on the Wacom under Wayland that the pen's eraser end, if it reports, erases |
| R6 | Barrel-button bits differ per device (Wacom 4/2, S Pen 2) and are not visible while hovering on Wacom | M0 | M4 **(closed)** | `PenButtonMap` table per platform; bit 4 on a pen is no longer read as the middle mouse button (a bug found by the test); tested for both devices |
| R7 | X11 gives no pressure or stylus kind; Wayland does | M0 | M4 **(closed)** | A pen with a fixed pressure range reports none and draws at constant width (tested) |
| R8 | Pressure curve (soft default; real strokes peak 0.1 to 0.6) and 500 Hz batching (every sample consumed) | M0 | M4 **(closed)** | `PressureCurve` is configurable and was retuned from real S9 strokes (median 0.12, max about 0.25); every sample of a 160-sample stroke reaches the tool (tested) |
| R9 | Pinch with two real fingers and pen input were never exercised on the S9 (only `adb input`) | M2 | M4 **(owner, at the review stop)** | Done by hand; checklist in `docs/m4.md`. (The database shows the owner has already drawn and erased by hand.) |
| R10 | Extract shows only highlights; Notes filter, "↳" linked quote lines and the Markdown "## Notes" section are not built | M3, §10 | M4 **(closed)** | Notes in Extract (filter, order, linked quotes, jump, delete) and in Markdown, with golden files |
| R11 | Highlight hit-test with a 16 px minimum height (select, erase, tap to focus) | M3 | M4 **(closed)** | `HighlightIndex`: 10 px reach and 16 px minimum height at any zoom; tap-select and the eraser use it |
| R12 | Highlight meanings Claim/Method/Question and glyphs are "assumed approved" | §20 | M4 **(owner, at the review stop)** | Owner confirms, or says what to change |
| R13 | Undo for ink, notes, links and lasso actions groups correctly (one gesture = one step) | §9 | M4 **(closed)** | Random sessions of 40 edits across every mark type retrace exactly through undo and redo, in storage and on the page, with no link ever left dangling (12 seeds); a mutation check confirmed the test catches a missing link delete |
| R14 | Undo history is in memory and not rebuilt from the log on launch | M1, M2 | M5 | Reopen restores the last ~200 transaction groups as undoable |
| R15 | Highlights store `contextBefore/After` but nothing re-anchors them | M3, §5.4 | M5 | On open, a highlight whose quote no longer matches its text range is re-anchored by context or flagged; test with a changed text layer |
| R16 | Library shows no mark count and "date added" instead of "last opened" (§11.1) | §11.1 | M5 | Both shown and tested |
| R17 | Cached page text is not removed when a PDF is purged | M3 | M5 | Purging a PDF also deletes `text/<hash>/`; test |
| R18 | Android file picker, Linux file dialog and Linux drag and drop never driven by hand | M2 | M5 | Owner (or hand test on a device) imports through each; noted in the M5 report |
| R19 | A password-protected PDF asks again after the app restarts (password cache is per session) | M2 | M5 | Decision recorded: keep (and say so in the empty/error copy) or store in the platform keystore |
| R20 | Column-aware reading order for odd layouts (content-stream order is right for the two fixtures) | M0, M3, §20 | M6 | Implemented, or written into the release notes as a known limitation with an example |
| R21 | Free-rectangle highlights show "Image region" in Extract; a page-crop thumbnail was proposed (6.2) | M3 | M6 | Thumbnail shown in Extract and in the screen-reader label, or the proposal is dropped in writing |
| R22 | Right-to-left text is not handled specially | M3 | **Closed (owner decision)** | Declared a v1 non-goal in 1.2; release notes say so. No fixture or code needed |
| R32 | Text that reads sideways or upside down on screen (e.g. the arXiv margin stamp, pages rotated without turning their text) is split into one-character words and lines; boxes are correct | M3.1 | M6 | Words and lines grouped in the text's own direction, with the matching highlight rows; or listed in the release notes with an example |
| R33 | Ink input-to-pixel latency never measured with a real pen: `adb input` events are synthetic (sample age at frame start read 11 to 16 ms, which says little). Spec budget: at most 1 frame (8 ms at 120 Hz) with prediction | M4 | M4 **(owner, at the review stop)** | Owner draws with the S Pen and reads the overlay line "ink sample age"; over about 8 ms average means building the native overlay escape hatch (about 1 day) |
| R34 | Moving a large selection of ink rebuilds that page's ink picture on every pointer event | M4 | M6 | Measured with 1,000 selected strokes on the S9; fixed (preview as a transform) if it misses 60 fps |
| R35 | A page with 10,000 strokes records its picture once on first paint: a one-time pause of about 0.4 s on the S9 (the bitmap cache fixed steady-state frames: raster 47 ms to 1.5 ms) | M4 | M6 | Recording is chunked or moved off the first frame; or accepted in writing |
| R36 | Soft-keyboard behaviour of notes (the canvas pans to keep the note visible) was only tested with a hardware keyboard | M4 | M6 | Checked with the on-screen keyboard on the S9 and on a phone |
| R37 | Pen pressure curve has no setting yet (`PenConfig` is code only) | M4 | M6 | A "pen pressure" choice in Settings (soft, medium, firm) |
| R38 | **F1** Erase all: one action to clear ink (and optionally everything) | owner 2026-10-20 | M4.1 | Erase panel has "Clear all ink" with a scope choice (21.7); one undo step; confirm only if it cannot be undone |
| R39 | **F2** Any ink colour; the last 5 used are kept | owner | M4.1 | Colour picker (hue/lightness plus hex) in the pen panel; 5 recents persist across launches |
| R40 | **F3** Create a board with no PDF | owner | M4.2 | "New board" in Library opens an empty canvas; "Add" menu places content |
| R41 | **F4** Import images, Markdown, plain text (Word: not in v1) | owner | M4.3 | Each lands as a movable card; text cards support highlights and Extract |
| R42 | **F5** Select text anywhere, copy, paste onto canvas as a text block | owner | M4.2 (paste) and M4.3 (copy from text cards) | Ctrl+V / long-press Paste creates a text card at the pointer; clipboard image creates an image card |
| R43 | **F6** Re-highlighting the same text with the same meaning is not allowed | owner | M4.1 | Same range and meaning: no new mark, the existing one flashes. Overlap rules in 21.5 |
| R44 | **F7** Pen-friendly highlight menu (after highlighting, and on tapping a highlight): Add note, Change meaning, Copy, Delete; no long-press needed | owner | M4.1 | Vertical action strip beside the highlight; works with pen, finger and mouse |
| R45 | **F8** Ink and Erase option panels horizontal and collapsible | owner | M4.1 | Horizontal strip; double-tap the tool to hide or reopen; state remembered per tool |
| R46 | **F9** Resting palm must not block finger gestures | owner | M4.1 | Palm contact is classified and ignored on its own; pan and pinch with other fingers keep working (measured on the S9; test with synthetic contact sizes) |
| R47 | **F10** A pen tap on a note must not close or edit it; pen can select, move, reorder (bring forward/back) | owner | M4.1 (pen select/move) and M4.2 (z-order for all items) | Pen never types; edit with finger tap or keyboard (21.7) |
| R23 | Multiply blend cost on the S9 measured only with 8 highlights; flat-fill fallback undecided | M3 | M6 | Measured on a page with many highlights; keep multiply or switch by setting, written down |
| R24 | Predictive back enabled but never exercised on a device | M1 | M6 | Back from Canvas, sheets and menus checked on the S9 |
| R25 | Linux minimum window size (800x520) never resized by hand; HiDPI and Wayland checks | M1, §17 | M6 | Done and noted in the M6 report |
| R26 | Real phone never used (emulator only, by owner decision) | M1, §20 | M6 | Owner runs the phone checklist; phone layout and "finger draws" hint verified |
| R27 | Bundled original sample document ("Open sample") assumed yes, not built | §11.1, §20 | M6 | Built, labelled as a sample, or dropped by the owner |
| R28 | Source Serif 4 and Figtree licences to confirm when bundling (§19.7); dark theme values unconfirmed (§19.8) | M1 | M6 | Licence files shipped; owner confirms dark theme |
| R29 | First build downloads pdfium through a native-assets hook; release builds and offline builds not checked | M0 | M6 | Release APK and Linux bundle build from a clean cache with the documented steps |
| R30 | §13 budgets never run as a set: 200-page open under 800 ms, cold start, memory, Extract scroll with 5,000 items | M2, §13 | M6 | Table of measured values on S9 and Linux in the M6 report |
| R31 | Highlight style (multiply / flat / pattern) and Extract order settings | M3, §11.3 | M6 | Both in Settings, persisted, tested |

Deferred past v1 on purpose (unchanged): handwriting conversion, OCR, flattened PDF export, card resize, Ctrl+F in Extract, "include sketches", sync, accounts, non-PDF sources.

---

### M2 decisions (owner, 2026-10-19)
- Review stop after **2a** (engine on synthetic pages) before any PDF code.
- Panning is **clamped**: the viewport may roam up to one screen beyond the cards, never further (`ViewState.clamped`).
- Imported pages land **in one column, top to bottom**, 80 px apart, centred on a shared vertical axis. (Changed from "one row, left to right" after hands-on review of 2a: a column reads like a document and makes the dot grid visible on both sides.)
- Import paths in M2 (all built): file picker on both platforms (GTK dialog on Linux, a native streaming picker on Android), Linux drag and drop, and Android "Open with / Share to Aether". Importing a file already in the library opens the existing document. A password-protected PDF prompts, and the password is remembered in memory for the session only.
- "Fit" fits the page nearest the centre of the screen (not the whole document, which is meaningless for a 500-page row); Ctrl+0 is the same, Ctrl+1 is 100%.
- The drag handle keeps a constant screen size at any zoom and is hidden when its card is under 90 px wide.

## 19. Known shortcomings and risks (carried over, ranked)

1. **Linux pen fidelity** (pressure, eraser end, hover) is unverified. Mitigated by the M0 spike and graceful degradation.
2. **Ink latency on Android** without a front-buffer path. Prediction and a slim live layer are the plan; native overlay is the escape hatch.
3. **PDF text quality**: reading order in multi-column and math-heavy documents; scanned PDFs have no text. Fallbacks defined; OCR deferred.
4. **Highlight blend over bitmap pages**: multiply requires a layer per page with highlights; measured, with a flat-fill fallback.
5. **pdfium plugin maturity** on Linux/Android (render speed, memory, text API stability): validated at M0; fallback is direct FFI to pdfium.
6. **Scope**: real PDF import plus pen-quality canvas plus CRDT-ready storage is a lot. The milestone stops are there to prevent building a large wrong thing.
7. **Georgia/Source Serif substitution** and Figtree licensing: both open-licensed (OFL) but should be confirmed when bundling.
8. **Dynamic color/dark mode** values are proposals; DESIGN.md dark theme is unconfirmed.
9. **Sync-readiness is a promise about the schema, not a tested feature.** Until a second device exists, merge behavior is unproven; keep the op-log tests strict.
10. **Fixture PDFs**: a two-column paper, a 166-page math paper, encrypted, 200 and 500 page files exist; scanned and rotated do not (register R2).

---

## 20. Decisions log and remaining open items

### Resolved by the owner
1. Phone: emulator is enough for initial testing; real-device verification comes later.
2. App id: `com.ritvijsrivastava.aether` (from aether.ritvijsrivastava.com).
3. Unused runner folders (web, ios, macos, windows): deleted.
4. Finger = pan, scroll, zoom. Stylus/mouse mark. "Finger draws" is opt-in.
5. Dark mode: document pages stay white (optional dim-page setting).
6. PDF export with annotations: **recommended and adopted as v1.1**, not v1. Reasoning: Markdown, JSON, and share already cover getting data out; flattening needs either re-rasterizing pages (lossy, large) or writing PDF annotation objects (a separate, fiddly pdfium task), which would delay the pen-feel milestones that matter most. Revisit after M5.
7. Distribution: personal use first; revisit later.

### Still open
- Highlight meanings fixed at Claim/Method/Question with glyphs circle/diamond/triangle (assumed approved unless you object).
- Bundle an original sample document? (assumed yes, generated by me, clearly labelled as a sample).
- Fixture PDFs for testing (I will generate simple ones; real-world papers from you would be better).
- Column-aware reading order: M3 on the two real papers showed content-stream order is right for ordinary two-column text; scheduled as register R20 (M6) for odd layouts.


### M3 decisions (built, 2026-10-19)
- **Text layer stores characters, not words.** The disk cache keeps each page's code points and char boxes (`<root>/text/<pdf hash>/<page>.axt`, versioned binary); words and lines are rebuilt on load in a few ms, so the grouping rules can improve without invalidating the cache. SPEC 6.2 said to store `Word`/`Line`; this is the deliberate change.
- **Marks work in page space on the page where the drag started**; leaving the page keeps extending on it.
- **Tap a word** highlights it at once; **a second tap within 350 ms and 24 dp** replaces that word with its sentence as one undoable step. Sentences end at `. ! ?` before a capital, digit or opening quote, except abbreviations, initials and numbered items, and at heading or paragraph breaks and column jumps.
- **Pointer-down grabs the nearest word within 10 dp**; otherwise (or on a page with no text) the drag is a free rectangle with the quote "(image region)". A rectangle under 4 pt is a slip and makes nothing.
- **Extract order is reading order** (page, then text position; rectangles after the text on their page). Markdown copy is grouped by meaning (Claim, Method, Question), the reading-order layout exists in the exporter and is pinned by golden files; a setting for it is M6.
- **Escape** drops a mark in progress. **Ctrl+C** with nothing selected copies the Extract list as Markdown.
- Highlight painting: see DESIGN.md "Highlights" (multiply in the page pass).

---

## 21. Pivot: Aether is a general canvas (proposed 2026-10-20)

Owner direction: *"a plain empty blackboard; we can do whatever we want here."* PDFs, images and text are things you put on it. Nothing below is built until the owner answers 21.7.

### 21.1 Principles
1. **The board is the unit.** The Library lists boards. A board starts empty; a PDF is imported into a board (new or existing), never required.
2. **Everything on a board is an item with a position.** Items are movable, resizable (cards: proportionally), orderable (z-order), duplicable, deletable, selectable with the same Select tool.
3. **Annotation is generic.** Ink, notes and links work over any item, or over empty canvas. Highlights need text, so they work on items that have a text layer (PDF pages, Markdown and text cards, text blocks).
4. **Small drawing set, done well.** Enough to sketch a diagram. No layers, no brushes with textures.
5. **Keep what is built.** The PDF pipeline, text layer, Extract, ink, notes, links, select and the command stack stay; the pivot changes ownership and adds item kinds.

### 21.2 Data model changes
```
Board  { id, title, createdAt, updatedAt, hlc }                  // was Document
Source { id, boardId, kind: pdf | image | markdown | text, fileHash, title, hlc }   // was PdfFile reference
Card   { id, boardId, sourceId?, kind, pageIndex?, x, y, width, height, z, hlc }    // was PageRef; also text blocks and shapes
```
- Existing **Document → Board** with one **Source** and its **PageRef → Card**; migration is one-way and tested on the real database from the S9.
- **Marks** gain `boardId` (replacing `docId`) and an optional `cardId` (replacing `pageId`). Anchored marks keep **card space** coordinates (so they move with the card); free marks stay in canvas space.
- **Highlights** keep their text anchors but anchor to a card with a text layer.
- **Z-order** is a per-board fractional index (CRDT-friendly), so reordering is one field change.
- **Shapes and text blocks** are cards (kind `shape`, `textBlock`) with their style in a JSON field; they need no source file.
- The op log is unchanged; `docId` columns keep their names in storage for one release to avoid a destructive migration, with a mapping layer.

### 21.3 Add menu (the single entry for content)
"Add" (pill beside the tool rail; also right-click, long-press on empty canvas, Ctrl+V, drag-and-drop, and Android share-to): **File** (PDF, image, Markdown, text), **Paste**, **Text**, **Note**, **Shape**. Dropping or pasting places the item at the pointer, or at the view centre when there is none.

### 21.4 Drawing set (M4.4)
- Ink with any colour (full picker; **last 5 used** shown first), width 1 to 24, and a **marker** variant (wide, translucent, flat ends).
- Shapes: line, arrow, rectangle, ellipse, with stroke colour, optional fill, width; optional label text. Drawn by drag, edited by Select (move, resize handles, recolor).
- Hold still at the end of a stroke: straighten to a line or snap to a shape **[PROPOSED, can cut]**.
- Text block: free text on the canvas, no note chrome; font size choice (3 steps).
- Not included: layers, gradients, brushes, blend modes, path editing, image editing.

### 21.5 Behaviour fixes (M4.1)
- **F1 Erase all.** The Erase panel has "Clear all ink". Scope per Q5. One undo step. Not a confirm dialog when undo is available (a snackbar with Undo).
- **F2 Colours.** Picker with hue strip, lightness/saturation square and hex field; recents row holds the last 5 distinct colours used by any ink stroke; stored in settings; shared across boards.
- **F6 Duplicate highlights.** Creating a highlight whose range equals an existing live highlight of the **same meaning** does nothing visible except flash the existing one. A **different meaning** over the same range changes the meaning of the existing one (one undo step). A partly overlapping range of the same meaning **merges** into one highlight covering the union (Q7). Different meanings may overlap partially and are shown stacked.
- **F7 Highlight action strip.** A vertical strip of icon buttons (48 dp): Add note, Change meaning, Copy, Delete. It appears beside the highlight right after creating it (dismissed by tapping elsewhere or after a pen stroke), and when a highlight is tapped with Mark, Select or Pan tools. Long-press and right-click keep working as shortcuts. Pen, finger and mouse behave the same.
- **F8 Tool option panels.** Ink and Erase options open as a **horizontal strip** anchored to the toolbar edge (top of the canvas on wide screens; above the bottom bar on phones). **Double-tap the tool** (or press its key twice) collapses or reopens it; collapsed state is remembered per tool, and the strip collapses itself after the first stroke when "auto-hide" is on (Q8).
- **F9 Palm.** A touch is a **palm** if its contact is large (`radiusMajor` above a threshold measured on the S9), or it lands within 300 ms and 60 mm of a pen down or hover, and it has not moved. A palm is ignored **individually**: it must never cancel, block or capture other fingers. Pan and pinch work with two other fingers while a palm rests. Measured on the S9 with a real palm before acceptance.
- **F10 Notes with the pen.** The pen never edits text (no handwriting-to-text in v1). With the pen, on a note: **tap selects** (does not close or open it), **drag moves**, and the selection pill offers Bring forward, Send back, Delete. Finger tap, a mouse click, or Enter on a selected note opens it for typing. A note being edited closes only when focus is lost by a deliberate tap elsewhere with a finger or mouse, not by a pen tap.

### 21.6 Library and screens
- Library: "New board" is the primary action; "Import PDF" becomes "Add file" and creates a board per file, or adds to an open one. Cards show a **board preview** (rendered thumbnail of the board), item count, last opened.
- Canvas screen: Extract panel remains, listing highlights and notes of the board; for boards with no highlights it is hidden by default.
- Export: whole board or selection as **PNG**; Markdown export unchanged; PDF flatten stays v1.1.

### 21.7 Owner decisions (2026-10-20) and open questions

**Decided:**
- **Pen on notes:** pen **double-tap** opens a note for typing (keyboard), in addition to finger tap, mouse click and Enter. A pen single tap only selects. An empty note must **not vanish** on a pen tap: an empty note is discarded only when it loses focus after having been opened for typing and left empty, never on selection.
- **Overlapping highlights of the same colour merge into one.**
- **Colour is free and replaces fixed meanings.** Ink and marker (highlighter) take **any colour**. Highlights on text use the same marker colours. The **Extract panel collects by colour**: a row of colour chips (one per colour in use, with counts) filters the list; items are grouped by colour. Each of Ink and Marker remembers its **own** last used colour and its **own last 5 colours** (not shared); choosing the tool restores its last colour.
- Everything else in 21.5 stands as proposed (auto-collapse panels after first stroke, board wording, auto-convert existing documents, one shared Extract panel across PDFs, M4.1 first).

**Consequences of free colour (to confirm, Q-A to Q-C):**
- **Colours carry no names** (decided). The built-in Claim / Method / Question meanings (R12) become three **default swatches** with no name shown. Markdown export groups by colour in order of first use, headed by an automatic label (nearest basic colour name, e.g. "Coral", "Blue"); never user-set. Existing highlights keep their colour; the old meaning id stays in storage unused.
- Existing highlights keep their colour and name; the data model stores a colour value, with the meaning id kept as an optional label. No data loss.

**Resolved (2026-10-20, second round):**
- **Word files:** not in v1 (export to PDF first). Revisit in v1.1.
- **Erase all:** "Clear ink on this page/card" and "Clear all ink on board" (both undoable by snackbar, no dialog); "Clear board" (everything) is separate, behind a confirm.
- **Renaming colours:** out of v1.
- **Extract and shapes:** shapes and text blocks do not appear in Extract; only highlights and notes.
- **Markdown export order:** by colour, in order of first use.

**Still open:** none. Next step: owner says "go" for M4.1.
