---
name: Aether
description: A warm-paper annotation canvas where documents are objects on a desk and every mark becomes a quote.
colors:
  desk: "#f6f3ee"
  canvas: "#ece8e1"
  panel: "#fbf9f6"
  paper: "#fffdfa"
  ink: "#2b2723"
  ink-muted: "#605d5d"
  ink-subtle: "#6f6b6b"
  rule-strong: "#bab6b6"
  hairline: "rgba(60,50,40,.12)"
  hover-wash: "rgba(60,50,40,.07)"
  grid-dot: "rgba(60,50,40,.28)"
  danger: "#ae1800"
  indigo: "#5b5bd6"
  indigo-pressed: "#4a4ac0"
  indigo-wash: "#e6e6fb"
  indigo-text: "#3d3dbd"
  claim: "#f4877e"
  method: "#f2c94c"
  question: "#6fb1ee"
  note-paper: "#fdf0b5"
  figure-stripe-a: "#eae7e7"
  figure-stripe-b: "#f8f4f4"
typography:
  wordmark:
    fontFamily: "Figtree, system-ui, sans-serif"
    fontSize: "18px"
    fontWeight: 700
    letterSpacing: "-0.015em"
  panel-title:
    fontFamily: "Figtree, system-ui, sans-serif"
    fontSize: "20px"
    fontWeight: 700
    letterSpacing: "-0.015em"
  title:
    fontFamily: "Figtree, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 600
  body:
    fontFamily: "Figtree, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.45
  label:
    fontFamily: "Figtree, system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 600
  button:
    fontFamily: "Figtree, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 700
  document-body:
    fontFamily: "Georgia, 'Times New Roman', serif"
    fontSize: "17px"
    fontWeight: 400
    lineHeight: 1.65
rounded:
  highlight: "5px"
  paper: "8px"
  selection: "10px"
  card: "14px"
  tool: "16px"
  panel: "24px"
  pill: "999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "24px"
components:
  button-primary:
    backgroundColor: "{colors.indigo}"
    textColor: "{colors.desk}"
    typography: "{typography.button}"
    rounded: "{rounded.pill}"
    height: "38px"
    padding: "0 14px"
  button-primary-pressed:
    backgroundColor: "{colors.indigo-pressed}"
  button-quiet:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    typography: "{typography.button}"
    rounded: "{rounded.pill}"
    height: "38px"
    padding: "0 12px"
  tool-button:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    rounded: "{rounded.tool}"
    size: "56px"
  tool-button-active:
    backgroundColor: "{colors.indigo}"
    textColor: "{colors.desk}"
  filter-chip:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "5px 12px"
  filter-chip-selected:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.desk}"
  floating-panel:
    backgroundColor: "{colors.panel}"
    rounded: "{rounded.panel}"
    padding: "8px"
  extract-item:
    rounded: "{rounded.card}"
    padding: "12px 14px"
  sticky-note:
    backgroundColor: "{colors.note-paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.card}"
    padding: "12px"
    width: "220px"
  document-card:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    rounded: "{rounded.paper}"
---

<!-- Provenance: extracted from the prototype `Aether.dc.html` (the only visual authority) and updated at M1 with what shipped: tokens live in lib/ui/theme/tokens.dart and are verified by test/ui/contrast_test.dart. Values here were checked against the running Android build. Re-run /impeccable document after the canvas exists to regenerate the sidecar. -->

# Design System: Aether

## Overview

**Creative North Star: "The Reading Desk"**

Aether is a warm desk with paper on it. The room is quiet: a stone-and-cream surface, warm-brown ink, soft shadows like lamplight on card stock. The documents are the brightest, most contrasty things on the screen; the tools are soft, rounded, and floating, and they step back until needed. The single loud voice is indigo, reserved for the active tool, the primary action, and the link line connecting a thought to its source.

The system is tactile and calm, not clinical. Forms are rounded and pill-shaped like river stones, depth is soft ambient lift rather than borders, and nothing competes with the text being read. Marks are the color: the three meanings (coral, amber, blue) only ever appear where the user has made a mark, so color always means "you decided this matters".

The workspace is dense but never cramped: a full-bleed canvas with floating controls, one side panel, and a thin top bar. Pen, finger, and mouse are all first-class, so every control is sized for a fingertip even on desktop.

**Key Characteristics:**
- Warm neutral desk, brightest surface is the paper
- Rounded, pill-and-stone shapes; one 24px panel radius family
- One indigo accent used sparingly; three semantic mark colors reserved for annotations
- Soft layered shadows, no hard borders around floating UI
- A dotted grid that reads as an endless desk
- Serif for the document, sans for everything the user operates

## Colors

A warm paper-and-stone palette with one cool accent. Neutrals lean brown (hue ≈ 40°), never grey-blue, so the cool indigo and the semantic mark colors stand out.

### Primary
- **Lamplit Indigo** (#5b5bd6): the active tool, the primary button, focus rings, link lines, the "Preprint" eyebrow. Pressed state deepens to **Dusk Indigo** (#4a4ac0). The soft **Indigo Wash** (#e6e6fb) with **Indigo Ink** (#3d3dbd) text is used for quiet informational badges (e.g. the page-count badge) and for link quotes in Extract.

### Secondary: the three meanings
Reserved exclusively for annotation. They never appear as UI chrome.
- **Claim Coral** (#f4877e): highlights and swatches for Claim.
- **Method Amber** (#f2c94c): Method.
- **Question Blue** (#6fb1ee): Question.
- **Sticky Yellow** (#fdf0b5): the note paper and the note swatch in Extract.

### Neutral
- **Desk Cream** (#f6f3ee): app background, text color on filled indigo and filled ink.
- **Stone Canvas** (#ece8e1): the canvas surface and unselected chip fill.
- **Panel Ivory** (#fbf9f6): floating panels, toolbars, the Extract panel.
- **Paper White** (#fffdfa): document cards. The brightest surface in the app.
- **Warm Ink** (#2b2723): all primary text, ink strokes, selected chips.
- **Muted Ink** (#605d5d) and **Faint Ink** (#6f6b6b): secondary text, captions. Faint Ink was darkened from the prototype's #7d7979, which measured 4.09:1 on the panel and failed AA for small text.
- **Alarm Red** (#ae1800): destructive actions and errors only. Taken from the prototype's only red (its link hover colour); not a mark colour.
- **Rule Grey** (#bab6b6): table rules inside documents.
- **Hairline** (rgba(60,50,40,.12)): the only divider; between bars and panels.
- **Grid Dot** (rgba(60,50,40,.28) light, rgba(243,242,242,.22) dark): the canvas dot grid. Raised from the prototype's .20 so it still reads around a full-height page.

### Named Rules
**The Meaning-Color Rule.** Coral, amber, and blue appear only on user marks and their Extract swatches. Never on buttons, badges, status, or decoration. If a screen shows one with no mark behind it, it is wrong.

**The One Voice Rule.** Indigo is the only chrome accent, and on any screen it marks at most the active tool, the single primary action, and link lines. Its rarity is how the eye finds the current state.

**The Warm Neutral Rule.** Every neutral carries the brown hue. No pure grey, no pure black, no pure white outside the paper surface.

### Dark theme (final, M1; contrast verified by test)
Dark is a first-class scheme, derived from the warm neutrals rather than inverted. Desk #201e1d, Stone Canvas #2a2827, Panel #2d2b2a, Warm Ink #f3f2f2 (12.6:1 on the panel), Muted Ink #bab6b6 (7.0), Faint Ink #9a9696 (4.8). Indigo lifts to #9d9df2 with dark text #1b1a2e (6.9) on filled controls, and #a5a5f5 as indigo text (6.2). Alarm Red lifts to #ff9783. Document cards stay Paper White (#fffdfa) by default, so figures and scans stay truthful; an optional "dim page" mode is a later setting. The three meaning colours and the sticky note do not change between themes; their text is always the dark #2b2723.

**Meaning swatches are glyph discs.** The three meaning colours alone measure only 1.5 to 2.3:1 against the panel (below the 3:1 needed for a shape), so a swatch is a coloured disc carrying its glyph (circle for Claim, diamond for Method, triangle for Question) in dark ink, which clears 6:1 on every colour. The glyph, not the colour edge, carries the meaning. This is enforced by a test that fails if the colours ever pass alone.

## Typography

**UI Font:** Figtree (400, 500, 600, 700), bundled as an asset; fallback system sans.
**Document Font:** Georgia in the prototype. Georgia is not available on Android or Linux, so the Flutter build bundles an open serif of the same character [PROPOSED: Source Serif 4]. Real PDFs render with their own embedded fonts; this serif is used only for app-authored sample or generated content and for Extract quotes if serif quoting is chosen.

**Character:** A friendly geometric sans for everything you operate, set against a bookish serif for what you read. The pairing is the product's identity: the UI is modern and soft, the document is traditional and respected.

### Hierarchy
- **Panel Title** (700, 20px, -0.015em): "Extract".
- **Wordmark** (700, 18px, -0.015em): "Aether".
- **Title** (600, 14px): document title in the top bar; item titles.
- **Body** (400, 14px, 1.45): Extract item text, empty-state copy.
- **Button** (700, 13px): pill buttons.
- **Label** (600, 12px): chips, handles, counts, tool labels. Prototype uses 10–11px for tool labels and item category labels; the Flutter build raises the floor to 12sp.
- **Document Body** (400, 17px, 1.65, serif): page text in the prototype's sample.

### Named Rules
**The Sans-Operates, Serif-Reads Rule.** Sans for every control and label; serif only for reading content. Never set a button in serif or a paragraph of a document in sans.

**The 12sp Floor Rule.** No text below 12sp, all sizes in sp so they follow system font scale. (Corrects the prototype's 9–11px type.)

## Layout

The app is a full-height column: a 56px top bar (wordmark, divider, document title, page-count badge, then input indicator, Undo, and the primary export action on the right) over a content row. The content row holds the **canvas** (flexible, inset 12px, 24px radius, clipped) and the **Extract panel** (340px, inset 12px, 24px radius). Tools float over the canvas at top-left (16px inset); zoom controls float at bottom-right (16px inset).

Spacing runs on a 4px base with 8, 12, 16, 24 as the working steps. Floating chrome always sits 16px from the canvas edge.

**Responsive behavior (PROPOSED for Flutter, Material 3 window size classes):**
- **Compact (< 600dp, phone):** canvas is full-bleed edge-to-edge with insets. Tools collapse to a bottom toolbar of four primary tools (Mark, Ink, Note, Erase) plus a "more" tray (Link, Select, Pan). Extract becomes a draggable bottom sheet with collapsed / half / full snap points. The top bar reduces to title and overflow.
- **Medium (600–1100dp, tablet):** the prototype layout with a vertical tool rail at top-left and Extract as a collapsible side sheet (default collapsed in portrait, open in landscape).
- **Expanded (> 1100dp, desktop):** the full prototype layout with a user-resizable Extract panel (280–480px), hover tooltips, and visible keyboard shortcut hints.

All touch targets are at least 48×48dp with 8dp between them. The prototype's 28px category dots, 12px swatches and bare "×" glyphs are enlarged to meet this in Flutter, using larger invisible hit areas where the visual should stay small.

## Elevation & Depth

Hybrid: tonal layering for rest state, ambient shadow for floating objects. Surfaces are separated first by tone (Stone Canvas under Panel Ivory under Paper White) and a single hairline; shadows lift anything the user can pick up or that floats over the canvas. Shadows are warm (brown-tinted, never pure black) and diffuse.

### Shadow Vocabulary
- **Float** (`0 2px 16px rgba(60,50,40,.16)`): the tool rail, zoom pill. Panel variant uses `.14`.
- **Paper** (`0 2px 6px rgba(60,50,40,.08), 0 12px 32px rgba(60,50,40,.12)`): document cards. Two layers so the card reads as thick stock.
- **Sticky** (`0 2px 4px rgba(60,50,40,.10), 0 8px 20px rgba(60,50,40,.14)`): notes, lifting them above paper.
- **Handle** (`0 1px 6px rgba(60,50,40,.18)`): the drag-handle tab above a document.
- **Action** (`0 2px 8px rgba(60,50,40,.25)`): the contextual selection button.

### Named Rules
**The Lift-Means-Movable Rule.** Only things the user can pick up (cards, notes, floating tools) cast shadow. Anything fixed to the frame (top bar, panel dividers) is separated by a hairline, not a shadow.

**The Warm Shadow Rule.** Shadows use rgba(60,50,40,·), never black.

## Shapes

Soft and rounded, built from one family. The 24px radius frames anything that is a *region* (canvas, Extract panel, tool rail). 16px rounds tool buttons; 14px rounds cards inside regions (notes, Extract items); 8px keeps documents slightly more squared than the UI so paper reads as paper. Anything that is a *command* is a full pill (999px): top bar buttons, chips, the zoom control, handle tabs, the "Convert" action. Highlights use a 5px radius so they look like marker, not pill. Category swatches in the prototype are squares (12px); category pickers are circles. Flutter adds a distinct glyph per meaning (see Components) so shape also carries information.

Selection uses a dashed 1.5px indigo outline at 10px radius. Link lines and the lasso use round caps and joins.

## Components

### Top Bar
Quiet. 56px, hairline bottom border, no fill beyond Desk Cream. Wordmark, a 2px vertical divider, the document title (ellipsized, never wrapping), an Indigo Wash page-count badge (4px-radius rectangle in the prototype; Flutter uses a pill for consistency). Right side: input-kind indicator, **Undo** (quiet pill, 38px), **Copy as Markdown** (primary pill, 38px; label becomes "Copied" for 1.5s). Flutter grows hit areas to 48dp and adds Redo.

### Buttons
- **Shape:** full pill (999px), 38px visual height, 48dp hit area.
- **Primary:** Lamplit Indigo fill, Desk Cream text, 700 13px, 14px side padding. Pressed: Dusk Indigo.
- **Quiet:** transparent with a 1px hairline border, Warm Ink text; hover/press fills Hover Wash.
- **Focus:** 2px indigo outline, 2px offset, on keyboard focus only.

### Tool Rail
- **Style:** a vertical floating panel (Panel Ivory, 24px radius, 8px padding, Float shadow) holding seven 56×56 tools (Pan, Mark, Ink, Erase, Note, Link, Select), a hairline, then the three meaning swatches.
- **Tool:** 16px radius; 22px stroke icon over a 12sp label. Active: Lamplit Indigo fill with Desk Cream icon and label.
- **Meaning picker:** 28px circles in the prototype (48dp hit area in Flutter); selected shows a 2px Warm Ink ring at 2px offset. Picking a meaning also switches to Mark. Each meaning also carries a glyph (Claim ●, Method ◆, Question ▲) shown in the picker, in Extract, and optionally as a hatching pattern on the page.
- **Phone:** becomes a bottom toolbar (see Layout).

### Zoom Control
A single pill (Panel Ivory, Float shadow) joining −, percent readout, +, and Fit, separated by hairlines. Bottom-right, 16px inset.

### Extract Panel
- **Header:** 20px title with an item count baseline-aligned to its right; below it, wrapped filter chips (All, Claim, Method, Question, Notes).
- **Filter chip:** pill, 12sp 600; unselected Stone Canvas, selected Warm Ink with Desk Cream text.
- **Item:** 14px radius, 12px/14px padding, 4/8px margins. Header row: meaning disc (22px, with its glyph), label, page ("p. 3", muted), delete at the far end (48dp target). The quote is reading content, so it is set in the document serif at 15sp/1.5, up to 6 lines. A free rectangle reads "Image region" in muted sans (a page crop thumbnail is not built yet). Items sit on Desk Cream inside the Ivory panel (tone, not border). Delete is immediate with an Undo snackbar. Notes lines (below) arrive with M4. Linked notes show an indigo-ink quote line "↳ “…”" at 12sp. Hover Wash on hover/press; tap jumps the canvas to the mark.
- **Empty state:** "Highlight or write to start collecting. Everything you mark lands here, quoted and ready to export." Muted Ink, 14sp, 24px/16px padding.

### Document Card
Paper White, 8px radius, Paper shadow, page content at 1:1 (prototype 720×1000 logical px, Flutter uses PDF page proportions). A pill **drag handle** tab floats 10px above its top-left corner ("⠿ Paper · p. 1"), Panel Ivory with Handle shadow, 36px high (48dp hit area), grab cursor on desktop. Dragging the handle moves the card *and its marks together*.

### Highlights
Rounded 5px (screen px, at any zoom) bars in the meaning color at 50% opacity. **As built (M3):** pages are PDF bitmaps with the text baked in, so highlights cannot go beneath the text; they are painted with `BlendMode.multiply` straight after the page's tiles in the same pass, so dark text stays dark and overlapping highlights darken like marker. This deviates from the "paint under text" ideal on purpose (SPEC 5.4); a flat translucent fill remains the fallback if a device misses its frame budget (not yet measured on the Tab S9). The highlight being dragged is drawn a little stronger (62%) in its own layer. Highlights snap to word boxes and wrap across lines with one even row per line; a row is never thinner than 6 pt (a fraction bar or dash still shows), and hit-testing will grow it to 16px when select and erase arrive (M4). A free rectangle (figure or scan, no text) is the same colour with a 1.5px edge in its own colour.

**Jump flash.** Tapping an Extract item moves the canvas to the highlight (keeping a readable zoom, coming in to 100% from far out) and outlines it for 1.4s in Warm Ink, fading; with "remove animations" the outline holds at full strength instead of fading and the move is instant.

### Sticky Note
Sticky Yellow, 14px radius, 220px default width (resizable in Flutter), Sticky shadow. Header: "Note" 10px label in the prototype (12sp in Flutter) and a delete control. Body is a borderless multiline text field, 15sp/1.4. Notes can be dragged by the header.

### Link Line
2.5px Lamplit Indigo curve (quadratic) from the note to the highlight it quotes; a dashed 6/5 version while being drawn. Round caps. A small endpoint dot at the highlight.

### Ink
Warm Ink strokes, 2.5px default width (user-adjustable 1–8), round caps, quadratic smoothing. In Flutter, width varies with stylus pressure when hardware reports it.

### Selection (Lasso)
A dashed 1.5px indigo rounded rectangle around selected marks with a contextual pill action above it (Action shadow). In v1 the prototype's "Convert to text" action is **removed** (handwriting conversion is deferred); the pill hosts Move / Recolor / Delete.

### Canvas Surface
Stone Canvas with a dot grid (Grid Dot, 2.4 px dots, 32 px pitch × zoom) that pans and scales with the view so it reads as an endless desk. When the dots would be closer than 14 px the pitch doubles, so the grid never turns to noise. Pages sit in one column, top to bottom, centred. Zoom range 20%–300%; Fit sizes the content to the viewport.

## Do's and Don'ts

### Do:
- **Do** keep documents the brightest and most contrasty element on screen (Paper White #fffdfa on Stone Canvas #ece8e1).
- **Do** reserve Claim Coral / Method Amber / Question Blue for user marks and their Extract swatches only.
- **Do** make every command a pill and every region a 24px-radius surface.
- **Do** use warm shadows rgba(60,50,40,·) and only on things the user can lift or that float.
- **Do** pair every meaning color with its glyph and text label.
- **Do** keep sans for the UI and serif for the reading material.
- **Do** honor the 12sp type floor and 48dp touch targets everywhere, including hit areas larger than the visual.

### Don't:
- **Don't** introduce a second accent color. Indigo is the only chrome accent.
- **Don't** use pure black, pure grey, or blue-grey neutrals.
- **Don't** draw hard borders around floating panels; separate by tone and shadow.
- **Don't** put meaning colors on buttons, badges, or status UI.
- **Don't** blend highlights with anything but the page tile beneath them; never let a highlight reduce text contrast below AA (fall back to a flat fill on devices where multiply is too slow).
- **Don't** reproduce `Aether Concept.dc.html`'s treatment (Archivo, 2px hard black borders, square corners, red #ec3013 accent, all-caps tracked labels). It is an earlier exploration and was superseded by `Aether.dc.html`.
- **Don't** show a debug-style input indicator as permanent chrome; fold it into a quiet state affordance.
- **Don't** ship the iOS-style bottom-only navigation or Cupertino controls; use Material 3 components themed with these tokens.


## As built (M4)

- **Ink.** Pressure-width ribbon with round caps; width follows a soft curve tuned to real S Pen strokes. The pen size is in screen dp at the time of drawing. A crowded page (over 400 strokes) is drawn from a cached bitmap while panning and zooming.
- **Pen options** float beside the tool rail (above the toolbar on a phone): four colour discs and a size slider for Ink; one switch, "Erase part of a stroke", for Erase.
- **Eraser** shows a 14 dp ring under the pen.
- **Sticky note.** Warm yellow, 14 px radius, Sticky shadow; header "Note" (12sp), a delete control, 15sp text, a resize grip. The header grows below 100% zoom so its controls stay 48 dp on screen. Below 35% zoom a note is a chip.
- **Link.** Indigo curve with a dot on the highlight; a halo and a dashed line while dragging; "Remove link" pill (Alarm Red text) at the middle of a selected link.
- **Selection.** Dashed 1.5 px indigo outline, 10 px radius, faint wash; a pill above it with "N selected", Recolor, Delete. Recolor shows the three meaning discs and/or the four ink colours.
- **Extract notes.** A note tile: a sticky-yellow disc, "Note · p. N", the words in sans 14sp, and "↳ “quote”" lines in indigo ink (12sp, up to three, then "and N more").
