# Product

<!-- impeccable:product-schema 1 -->

<!-- Provenance: facts marked [confirmed] came from the user in session or from the design project files. Facts marked [assumed] are inferred from those files and need the owner's confirmation. -->

## Platform

android

Aether ships as one Flutter codebase to **Android (phone and tablet)** and **Linux desktop**. Web, iOS, and Windows are out of scope for now [confirmed]. The product speaks one design language (Material 3 structure, themed with the Aether brand) on both targets; Linux gets desktop affordances (keyboard, pointer hover, resizable panels) on top of the same components. Android's platform rules (Material structure, 48dp targets, sp type, system Back, edge-to-edge insets) are the governing native reference.

## Stack

Flutter / Dart, one codebase [confirmed]. Reference hardware [confirmed]: a Samsung Galaxy Tab S9 with S Pen (Android tablet and stylus), and a Linux desktop with a Wacom-style pen tablet. A phone is a target form factor but no reference phone is named yet [open].

Selected by the project owner; not delegated.

## Users

[assumed] Students, researchers, and analysts who read dense documents (papers, reports, contracts, slide decks) with a stylus, finger, or mouse, and who need to turn what they read into something they can use: quotes sorted by meaning, with their own notes attached. Primary situation: a long reading session on a tablet with a pen, then a review pass on a desktop or phone.

The job: read a document, mark what matters (a claim, a method, an open question), think on the page in handwriting and notes, then pull everything marked out as quoted, linked, exportable text.

## Product Purpose

Aether is a document annotation canvas. Documents float as cards on an endless surface; the user marks them up; every mark becomes a quoted, filterable item in an Extract panel that exports as Markdown. Success is a reader finishing a document with a clean, trustworthy digest of their own thinking and never having lost a mark.

## Positioning

"The paper is an object, not a page." [from Aether Concept.dc.html]

Documents are movable cards on an infinite canvas, not pages in a scrolling viewer. Annotations travel with their document, so papers can be laid out side by side like a desk. Highlights carry a *meaning* (claim, method, question), not just a color, so marking is simultaneously collecting. A neighboring PDF annotator that only offers a page viewer with colored highlighters cannot truthfully claim this.

## Operating Context

- Input is mixed by design: pen marks, finger moves, mouse works throughout. Pen and finger are distinguished by pointer kind; palm contact while the pen is down is rejected [confirmed from prototype and concept].
- Documents are imported PDFs [confirmed: real PDF import in v1]. The concept also names web articles, slide decks, and scans with OCR; these are **not** in v1 [assumed deferral].
- Everything is local-first [confirmed]: documents and annotations live on the device and work offline. Sync is a possible later step built on CRDTs [confirmed as direction, not v1 scope].
- Sessions are long and interruption-prone (app switches, S Pen detach/attach, battery). A mark must survive a crash.

## Capabilities and Constraints

In v1 [confirmed unless marked]:

- Import a PDF as a card; arrange multiple pages/documents freely on an infinite canvas with pan and pinch/wheel zoom.
- Highlight text snapped to words and lines, across multiple lines, in three meanings: Claim, Method, Question.
- Freehand ink with pen pressure where the hardware supplies it; erase.
- Sticky notes with typed text; link a note to a highlight; a note can link to multiple highlights [assumed UX fix].
- Selection (lasso) to move, delete, or recolor marks.
- Full undo and redo.
- Extract panel: all marks as quoted items, filter by meaning and by notes, tap to jump, delete, copy as Markdown.
- Local persistence with autosave; a document library.

Explicitly **deferred**: handwriting-to-text conversion [confirmed], right-to-left and bidirectional text [confirmed, 2026-10-19], OCR for scanned PDFs, non-PDF sources, cloud sync, accounts, collaboration.

Constraints:

- No network is required for any v1 feature. No account.
- Text selection quality depends on the PDF having a text layer. Scanned PDFs fall back to free-region highlights with no quoted text.
- Linux pen pressure and eraser-end reporting through Flutter's GTK embedder is **unverified**; it is a gated spike before ink behavior is promised on Linux [open].

Terminology: *canvas* (the infinite surface), *card* (a document page on the canvas), *mark* (any highlight or note), *meaning* (Claim/Method/Question), *Extract* (the panel of collected marks), *link* (note-to-highlight connection).

## Brand Commitments

- Name: **Aether** [confirmed]. Wordmark set in the UI face at bold weight.
- The three meanings are named Claim, Method, Question [confirmed from prototype].
- Voice is plain, direct, and short: "Highlight or write to start collecting." No filler, no exclamation marks [assumed from prototype copy].
- Visual authority is `Aether.dc.html` (the user named it as the implementation target). `Aether Concept.dc.html` is an earlier, different visual treatment (see DESIGN.md) and is **not** binding.

## Evidence on Hand

- Design project "Document Annotation Canvas" at claude.ai/design/p/bcb0b0b5-3f16-4a35-98c8-51d387b4a686 containing `Aether.dc.html` (interactive prototype), `Aether Concept.dc.html` (flow and concept board), and `support.js` (prototype runtime, not product code).
- Sample content in the prototype is a fictional paper, "Selective Recall: Sparse Attention Under Distribution Shift". It is placeholder, not product content.
- **Absent, and must not be fabricated:** real users, testimonials, usage data, benchmarks, pricing, license, store listing, a logo mark beyond the wordmark.

## Product Principles

1. **The paper is an object.** Cards move, sit side by side, and carry their marks with them. Never reduce the product to a scrolling page viewer.
2. **The pen marks, the finger moves.** Input kind decides intent. A hand resting on the screen must never create a mark; a finger must never be required to leave drawing mode to pan.
3. **Marking is collecting.** Every highlight and note immediately appears, quoted, in Extract. There is no separate "export prep" step.
4. **Never lose a mark.** Autosave continuously; every action is undoable; destructive actions are recoverable rather than confirmed away.
5. **Local first, yours.** Works fully offline, stores plain exportable data, and keeps a data model that can sync later without migration.

## Accessibility & Inclusion

[assumed, to confirm] Target WCAG 2.2 AA for text and controls. Meaning must never be carried by color alone: the three meanings also carry a shape and a text label, with an optional pattern fill for highlights. Touch targets are at least 48dp. Text respects the system font scale (sp). Every tool and control has an accessible label; the canvas exposes the Extract list to screen readers as the accessible representation of marks. Respect the system "remove animations" setting.
