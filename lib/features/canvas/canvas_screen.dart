import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, HardwareKeyboard;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/geometry/box.dart';
import '../../data/pdf/page_text_service.dart';
import '../../domain/export/markdown_exporter.dart';
import '../../domain/model/models.dart';
import '../../domain/marks/colour_name.dart';
import '../../ui/widgets/color_disc.dart';
import '../../ui/widgets/colour_picker.dart';
import '../../ui/adaptive/window_class.dart';
import '../library/import/password_dialog.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/panel_surface.dart';
import '../extract/extract_controller.dart';
import '../extract/extract_panel.dart';
import 'canvas_top_bar.dart';
import 'canvas_ui_state.dart';
import 'canvas_view.dart';
import 'document_session.dart';
import 'erase/erase_options.dart';
import 'erase/erase_tool.dart';
import 'ink/ink_layer.dart';
import 'ink/ink_stress.dart';
import 'ink/ink_tool.dart';
import 'input/pen_config.dart';
import 'input/tool_gestures.dart';
import 'links/link_remove_overlay.dart';
import 'links/link_tool.dart';
import 'links/links_layer.dart';
import 'marks/flash.dart';
import 'select/mark_hit.dart';
import 'select/select_tool.dart';
import 'select/selection.dart';
import 'select/selection_view.dart';
import 'notes/note_tool.dart';
import 'notes/notes_overlay.dart';
import 'marks/highlight_actions.dart';
import 'tool_panel.dart';
import 'marks/mark_layers.dart';
import 'marks/mark_tool.dart';
import 'engine/canvas_controller.dart';
import 'engine/page_surface.dart';
import 'engine/scene.dart';
import 'engine/view_state.dart';
import 'pdf/pdf_page_surface.dart';
import 'pdf/pdf_source.dart';
import 'pdf/pdfium_tile_renderer.dart';
import 'perf_hud.dart';
import 'tool_palette.dart';
import 'zoom_pill.dart';

/// Test documents that need no PDF: `/doc/synthetic-30`, `/doc/synthetic-500`.
/// Numbered placeholder pages of mixed sizes, for judging the engine.
const String syntheticPrefix = 'synthetic-';

int? syntheticCount(String docId) => docId.startsWith(syntheticPrefix)
    ? int.tryParse(docId.substring(syntheticPrefix.length))
    : null;

Scene syntheticScene(int pages) {
  const letter = Size(612, 792),
      landscape = Size(792, 612),
      a4 = Size(595, 842);
  return Scene.column([
    for (var i = 0; i < pages; i++)
      i % 11 == 10 ? landscape : (i % 7 == 6 ? a4 : letter),
  ]);
}

enum _Load { ready, opening, failed }

/// The document workspace. Layout adapts to the window class:
/// compact = full-bleed canvas + bottom toolbar + Extract sheet;
/// medium/expanded = tool rail + side Extract panel.
class CanvasScreen extends ConsumerStatefulWidget {
  const CanvasScreen({super.key, required this.docId});
  final String docId;

  @override
  ConsumerState<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends ConsumerState<CanvasScreen>
    with TickerProviderStateMixin {
  late final CanvasController _controller;
  PageSurface _surface = SyntheticPageSurface();
  OpenedPdf? _pdf;
  DocumentSession? _session;
  final ValueNotifier<LiveMark?> _live = ValueNotifier(null);
  MarkToolController? _markTool;
  final LiveInk _liveInk = LiveInk();
  final EraserState _eraser = EraserState();
  final LiveLink _liveLink = LiveLink();
  final SelectionState _selection = SelectionState();
  final HighlightFocus _hlFocus = HighlightFocus();
  late final HighlightActions _hlActions = _HighlightStripActions(this);
  late final EraseClearActions _eraseClear = _EraseClear(this);
  final LiveLasso _lasso = LiveLasso();
  Listenable? _layerChanges;
  double _lastKeyboardInset = 0;
  PageTextService? _textService;
  late final FlashController _flash = FlashController(this);
  ExtractController? _extract;
  bool _copied = false;
  Timer? _copiedTimer;
  StreamSubscription<void>? _history;
  _Load _load = _Load.ready;
  String? _error;
  String? _title;
  int _pages = 0;

  int? get _synthetic => syntheticCount(widget.docId);

  @override
  void initState() {
    super.initState();
    final n = _synthetic;
    _controller = CanvasController(
      scene: n == null ? const Scene([]) : syntheticScene(n),
    )..attach(this);
    if (n == null) {
      _load = _Load.opening;
      _openDocument();
    } else {
      _title = 'Synthetic test, $n pages';
      _pages = n;
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _load = _Load.failed;
      _error = message;
    });
  }

  Future<void> _openDocument() async {
    try {
      await _openDocumentUnguarded();
    } catch (e, st) {
      // Whatever went wrong, say so instead of sitting on "Opening…".
      debugPrint('Opening ${widget.docId} failed: $e\n$st');
      _fail('This document could not be opened.');
    }
  }

  Future<void> _openDocumentUnguarded() async {
    final session = DocumentSession(
      docId: widget.docId,
      store: ref.read(opStoreProvider),
      db: ref.read(databaseProvider),
      controller: _controller,
      clock: ref.read(hlcClockProvider),
      ids: ref.read(idGeneratorProvider),
    );
    _session = session;
    if (!await session.load()) {
      return _fail('This document is no longer in your library.');
    }
    final doc = session.document!;
    final path = ref.read(pdfStorageProvider).pdfPath(doc.sourceHash);
    if (!File(path).existsSync()) {
      return _fail('The PDF for this document is missing from this device.');
    }

    // A password entered earlier this session (for example while importing)
    // is tried first, so the user is not asked twice in a row.
    var prompts = 0;
    final attempt = ref
        .read(pdfPasswordsProvider)
        .attempt(
          doc.sourceHash,
          () => !mounted
              ? Future.value(null)
              : showPdfPasswordDialog(
                  context,
                  fileName: doc.title,
                  retry: prompts++ > 0,
                ),
        );
    final OpenedPdf pdf;
    try {
      pdf = await openPdfFile(path, password: attempt.provide);
      attempt.accepted();
    } on PdfOpenException catch (e) {
      return _fail(e.message);
    }
    if (!mounted) {
      await pdf.dispose();
      return;
    }
    _pdf = pdf;
    _surface = PdfPageSurface(
      pageSizes: session.pageSizes(),
      renderer: PdfiumTileRenderer(pdf.document),
      cacheBytes: tileCacheBytesFor(
        isDesktop: Platform.isLinux,
        shortestSideDp: MediaQuery.sizeOf(context).shortestSide,
      ),
    );
    final textService = PageTextService(
      docKey: doc.sourceHash,
      extractor: PdfrxTextExtractor(pdf.document),
      cache: PageTextCache(ref.read(pdfStorageProvider).textDir),
    );
    _textService = textService;
    final tool = MarkToolController(
      view: _controller.view,
      scene: _controller.scene,
      live: _live,
      color: () => ref.read(canvasUiProvider).markColor,
      text: textService,
      sink: session,
    );
    _markTool = tool;
    _extract = ExtractController(
      highlights: session.highlights,
      scene: _controller.scene,
      onJump: _jumpTo,
      onDelete: (h) => session.deleteHighlight(h.id),
      onUndo: session.undo,
      notes: session.notes,
      links: session.links,
      onJumpNote: _jumpToNote,
      onDeleteNote: (n) => session.deleteNote(n.id),
    );
    final inkTool = InkToolController(
      view: _controller.view,
      scene: _controller.scene,
      live: _liveInk,
      widthDp: () => ref.read(canvasUiProvider).inkWidth,
      color: () => ref.read(canvasUiProvider).inkColor,
      sink: session,
      predict: defaultTargetPlatform == TargetPlatform.android,
    );
    _controller.tools = ToolRouter({
      CanvasTool.mark: MarkHandler(tool),
      CanvasTool.ink: inkTool,
      CanvasTool.select: SelectToolController(
        view: _controller.view,
        scene: _controller.scene,
        selection: _selection,
        live: _lasso,
        ink: session.ink,
        highlights: session.highlights,
        notes: session.notes,
        shift: () => HardwareKeyboard.instance.isShiftPressed,
        sink: session,
      ),
      CanvasTool.link: LinkToolController(
        view: _controller.view,
        scene: _controller.scene,
        notes: session.notes,
        highlights: session.highlights,
        links: session.links,
        live: _liveLink,
        sink: session,
      ),
      CanvasTool.note: NoteToolController(
        view: _controller.view,
        scene: _controller.scene,
        sink: session,
      ),
      CanvasTool.erase: EraseToolController(
        view: _controller.view,
        scene: _controller.scene,
        ink: session.ink,
        highlights: session.highlights,
        eraser: _eraser,
        partial: () => ref.read(canvasUiProvider).erasePartial,
        sink: session,
      ),
    });
    _controller.view.addListener(_warmText);
    session.onHighlightTouched = (h) => _hlFocus.show(h.id);
    session.onGestureDone = (t) => ref
        .read(canvasUiProvider.notifier)
        .gestureDone(
          t,
          autoHide: ref.read(settingsProvider).value?.autoHideToolPanel ?? true,
        );
    _selection.addListener(_selectionToStrip);
    // Marks that go away (deleted, undone) leave the selection.
    _layerChanges = Listenable.merge([
      session.highlights,
      session.ink,
      session.notes,
    ])..addListener(_pruneSelection);
    _history = session.bus.changes.listen((_) {
      if (mounted) setState(() {});
    });
    if (stressInkEnabled && session.controller.scene.value.cards.isNotEmpty) {
      // Measuring only: strokes held in memory, never saved.
      session.ink.replaceAll([
        ...session.ink.all,
        ...stressStrokes(
          session.controller.scene.value.cards.first.id,
          stressInkCount,
        ),
      ]);
    }
    setState(() {
      _load = _Load.ready;
      _title = doc.title;
      _pages = doc.pageCount;
    });
  }

  /// Extract item tapped: bring the highlight into view and point at it.
  void _jumpTo(Highlight h) {
    final card = _controller.scene.value.byId(h.pageId ?? '');
    if (card == null || !mounted) return;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final b = h.bounds;
    _controller.reveal(
      Rect.fromLTRB(
        card.rect.left + b.x0,
        card.rect.top + b.y0,
        card.rect.left + b.x1,
        card.rect.top + b.y1,
      ),
      animate: !reduce,
    );
    _flash
      ..reduceMotion = reduce
      ..show(Flash(card.id, h.rects, h.color));
    _extract?.collapseRequests.value++;
  }

  static String _copiedMessage(int highlights, int notes) {
    final h = highlights == 1 ? '1 highlight' : '$highlights highlights';
    final n = notes == 1 ? '1 note' : '$notes notes';
    if (notes == 0) return 'Copied $h as Markdown.';
    if (highlights == 0) return 'Copied $n as Markdown.';
    return 'Copied $h and $n as Markdown.';
  }

  /// Ctrl+C: the selected quotes and notes as text; with nothing selected (or
  /// only ink), the whole Extract list as Markdown.
  Future<void> _copyKey() async {
    final s = _session;
    if (s != null && !_selection.isEmpty) {
      final parts = <String>[];
      final highlights = [
        for (final id in _selection.idsOf(MarkKind.highlight))
          ?s.highlights.byId(id),
      ];
      // In reading order: by page, then by place in the text.
      final order = {
        for (final c in _controller.scene.value.cards) c.id: c.index,
      };
      highlights.sort((a, b) {
        final pa = order[a.pageId] ?? 1 << 30, pb = order[b.pageId] ?? 1 << 30;
        return pa != pb ? pa.compareTo(pb) : a.startChar.compareTo(b.startChar);
      });
      for (final h in highlights) {
        parts.add(h.startChar < 0 ? '(image region)' : h.quote);
      }
      for (final id in _selection.idsOf(MarkKind.note)) {
        final n = s.notes.byId(id);
        if (n != null && n.text.trim().isNotEmpty) parts.add(n.text.trim());
      }
      if (parts.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: parts.join('\n\n')));
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                parts.length == 1
                    ? 'Copied 1 item.'
                    : 'Copied ${parts.length} items.',
              ),
            ),
          );
        return;
      }
    }
    await _copyMarkdown();
  }

  /// Copy as Markdown: the whole Extract list, grouped by meaning.
  Future<void> _copyMarkdown() async {
    final items = _extract?.items(ExtractFilter.all) ?? const [];
    final noteItems = _extract?.noteItems() ?? const [];
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (items.isEmpty && noteItems.isEmpty) {
      messenger
        ?..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Nothing to copy yet.')));
      return;
    }
    await Clipboard.setData(
      ClipboardData(
        text: MarkdownExporter.export(
          _title ?? 'Document',
          items,
          notes: noteItems,
        ),
      ),
    );
    if (!mounted) return;
    messenger
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(_copiedMessage(items.length, noteItems.length))),
      );
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  /// The soft keyboard came up while a note is being edited: pan so the note
  /// stays in the part of the canvas the keyboard leaves free.
  void _revealEditingNote() {
    final session = _session;
    if (session == null || !mounted) return;
    final id = session.notes.editingId;
    final n = id == null ? null : session.notes.byId(id);
    if (n == null) return;
    final o = NotesOverlay.worldOrigin(n, _controller.scene.value);
    if (o == null) return;
    _controller.reveal(
      o & Size(n.width, n.height),
      animate: !MediaQuery.disableAnimationsOf(context),
    );
  }

  void _pruneSelection() {
    final s = _session;
    if (s == null) return;
    _selection.prune(
      (r) => switch (r.kind) {
        MarkKind.highlight => s.highlights.byId(r.id) != null,
        MarkKind.ink => s.ink.byId(r.id) != null,
        MarkKind.note => s.notes.byId(r.id) != null,
      },
    );
  }

  /// Delete or Backspace: remove what is selected, with Undo offered.
  void _deleteSelection(DocumentSession session) {
    if (!_selection.isEmpty) {
      final n = _selection.count;
      session.deleteMarks(_selection.refs);
      _selection.clear();
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(n == 1 ? 'Deleted 1 mark' : 'Deleted $n marks'),
            action: SnackBarAction(label: 'Undo', onPressed: session.undo),
          ),
        );
      return;
    }
    final id = session.links.selectedId;
    if (id != null) session.deleteLink(id);
  }

  /// Right-click, or a long press with a finger: a menu for the mark under it.
  Future<void> _showContextMenu(Offset local, Offset global) async {
    final session = _session;
    if (session == null || !mounted) return;
    final v = _controller.view.value;
    final world = v.screenToWorld(local);
    final hit = MarkHitTester(
      scene: _controller.scene.value,
      ink: session.ink,
      highlights: session.highlights,
      notes: session.notes,
    );
    final target = hit.markAt(world, v.zoom);
    if (target != null) _selection.set([target]);
    final highlight = target?.kind == MarkKind.highlight
        ? session.highlights.byId(target!.id)
        : null;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(global.dx, global.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        if (highlight != null) ...[
          for (final c in ref.read(canvasUiProvider).markColors.recent)
            CheckedPopupMenuItem<String>(
              value: 'colour:$c',
              checked: highlight.color == c,
              child: Row(
                children: [
                  ColorDisc(c, size: 18),
                  const SizedBox(width: 8),
                  Text(colourName(c)),
                ],
              ),
            ),
          const PopupMenuItem(
            value: 'colour:other',
            child: Text('Other colour…'),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'note', child: Text('Add note')),
          const PopupMenuItem(value: 'copy', child: Text('Copy quote')),
        ] else if (target == null)
          const PopupMenuItem(value: 'note-here', child: Text('Add note here')),
        if (target != null)
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
    if (choice == null || !mounted) return;
    if (choice == 'colour:other') {
      final c = await showColourPicker(
        context,
        initial: highlight?.color ?? Swatch.coral,
      );
      if (c != null) session.recolorMarks([target!], highlightColor: c);
    } else if (choice.startsWith('colour:')) {
      session.recolorMarks([
        target!,
      ], highlightColor: int.parse(choice.substring(7)));
    } else if (choice == 'delete') {
      _deleteSelection(session);
    } else if (choice == 'copy' && highlight != null) {
      await _copyQuote(highlight);
    } else if (choice == 'note' && highlight != null) {
      _noteForHighlight(highlight);
    } else if (choice == 'note-here') {
      final card = hit.scene.cards.where((c) => c.rect.contains(world));
      final page = card.isEmpty ? null : card.last;
      final at = page == null ? world : world - page.rect.topLeft;
      session.beginNote(pageId: page?.id, x: at.dx, y: at.dy);
    }
  }

  /// A tool key: picks the tool; its own key again folds its options away or
  /// brings them back.
  void _pickToolByKey(CanvasTool t) {
    final n = ref.read(canvasUiProvider.notifier);
    if (ref.read(canvasUiProvider).tool == t && t.hasPanel) {
      n.togglePanel(t);
    } else {
      n.setTool(t);
    }
  }

  /// The page most in view: what "this page" means for the clear buttons.
  String? _pageInView() {
    final cards = _controller.scene.value.cards;
    if (cards.isEmpty) return null;
    final v = _controller.view.value;
    final size = _controller.viewport;
    final seen = Rect.fromPoints(
      v.screenToWorld(Offset.zero),
      v.screenToWorld(Offset(size.width, size.height)),
    );
    String? best;
    var bestArea = 0.0;
    for (final c in cards) {
      final i = c.rect.intersect(seen);
      final area = i.width <= 0 || i.height <= 0 ? 0.0 : i.width * i.height;
      if (area > bestArea) {
        bestArea = area;
        best = c.id;
      }
    }
    return best;
  }

  void _clearInk({required bool pageOnly}) {
    final session = _session;
    if (session == null) return;
    final page = pageOnly ? _pageInView() : null;
    final strokes = pageOnly
        ? (page == null ? const [] : session.ink.forPage(page))
        : session.ink.all.toList();
    if (strokes.isEmpty) {
      _say(pageOnly ? 'No ink on this page.' : 'No ink to clear.');
      return;
    }
    session.deleteMarks([for (final s in strokes) MarkRef(MarkKind.ink, s.id)]);
    _undoMessage(
      strokes.length == 1
          ? 'Cleared 1 stroke'
          : 'Cleared ${strokes.length} strokes',
    );
  }

  Future<void> _clearBoard() async {
    final session = _session;
    if (session == null) return;
    final refs = [
      for (final h in session.highlights.all) MarkRef(MarkKind.highlight, h.id),
      for (final i in session.ink.all) MarkRef(MarkKind.ink, i.id),
      for (final n in session.notes.all) MarkRef(MarkKind.note, n.id),
    ];
    if (refs.isEmpty) {
      _say('The board is already clear.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear the board?'),
        content: Text(
          'This removes all ${refs.length} marks: ink, highlights and notes. '
          'You can undo it right after.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.tokens.danger,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear board'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _selection.clear();
    _hlFocus.clear();
    session.deleteMarks(refs);
    _undoMessage('Board cleared');
  }

  void _say(String message) => ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  void _undoMessage(String message) {
    final session = _session;
    if (session == null) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: SnackBarAction(label: 'Undo', onPressed: session.undo),
        ),
      );
  }

  Future<void> _copyQuote(Highlight h) async {
    await Clipboard.setData(ClipboardData(text: h.quote));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Copied the quote.')));
  }

  /// A new note beside the highlight, linked to it once it has words.
  void _noteForHighlight(Highlight h) {
    final session = _session;
    final card = _controller.scene.value.byId(h.pageId ?? '');
    if (session == null || card == null) return;
    // Beside the highlight's last line, in the page's margin.
    final b = h.bounds;
    session.beginNote(
      pageId: card.id,
      x: b.x1 + 24,
      y: b.y0,
      linkToHighlight: h.id,
    );
  }

  /// A single highlight selected (Select tool) gets the action strip too.
  void _selectionToStrip() {
    final s = _session;
    if (s == null ||
        _selection.count != 1 ||
        ref.read(canvasUiProvider).tool != CanvasTool.select) {
      return;
    }
    final r = _selection.refs.single;
    if (r.kind == MarkKind.highlight && s.highlights.byId(r.id) != null) {
      _hlFocus.show(r.id);
    }
  }

  /// A tap with the Pan tool: a highlight under it gets the action strip,
  /// anything else dismisses it.
  void _onCanvasTap(Offset local) {
    final session = _session;
    if (session == null) return;
    final v = _controller.view.value;
    final hit = MarkHitTester(
      scene: _controller.scene.value,
      ink: session.ink,
      highlights: session.highlights,
      notes: session.notes,
    ).markAt(v.screenToWorld(local), v.zoom);
    if (hit != null && hit.kind == MarkKind.highlight) {
      _hlFocus.show(hit.id);
    } else {
      _hlFocus.clear();
    }
  }

  /// Extract note tapped: bring the note into view and outline it.
  void _jumpToNote(Note n) {
    final o = NotesOverlay.worldOrigin(n, _controller.scene.value);
    if (o == null || !mounted) return;
    final reduce = MediaQuery.disableAnimationsOf(context);
    _controller.reveal(o & Size(n.width, n.height), animate: !reduce);
    if (n.pageId != null) {
      _flash
        ..reduceMotion = reduce
        ..show(
          Flash(n.pageId!, [
            Box(n.x, n.y, n.x + n.width, n.y + n.height),
          ], Swatch.amber),
        );
    }
    _extract?.collapseRequests.value++;
  }

  void _warmText() => _markTool?.warmVisible(viewport: _controller.viewport);

  /// First layout is known: restore the remembered view, or show page one.
  Future<void> _onReady() async {
    final saved = await _session?.savedView();
    if (!mounted) return;
    saved != null ? _controller.setView(saved) : _controller.fitFirst();
    _warmText();
  }

  @override
  void dispose() {
    _controller.view.removeListener(_warmText);
    _controller.tools = null;
    _markTool?.dispose();
    _liveInk.dispose();
    _eraser.dispose();
    _liveLink.dispose();
    _layerChanges?.removeListener(_pruneSelection);
    _selection.dispose();
    _hlFocus.dispose();
    _lasso.dispose();
    _live.dispose();
    _flash.dispose();
    _copiedTimer?.cancel();
    _extract?.collapseRequests.dispose();
    _history?.cancel();
    _session?.dispose();
    final surface = _surface;
    if (surface is PdfPageSurface) surface.dispose();
    _pdf?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final cls = WindowClass.of(size.width);
    final ui = ref.watch(canvasUiProvider);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    if (keyboard != _lastKeyboardInset) {
      final grew = keyboard > _lastKeyboardInset;
      _lastKeyboardInset = keyboard;
      if (grew) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _revealEditingNote(),
        );
      }
    }
    // Choosing the Mark tool is the moment its text is about to be needed.
    ref.listen(canvasUiProvider.select((u) => u.tool), (_, tool) {
      if (tool != CanvasTool.link) _session?.links.select(null);
      if (tool != CanvasTool.select) _selection.clear();
      _hlFocus.clear();
      if (tool == CanvasTool.mark) _warmText();
    });
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final landscape = size.width > size.height;
    final extractOpen =
        ui.extractOpen ?? (cls == WindowClass.expanded || landscape);

    // Fit and zoom aim at the area the floating controls leave free.
    _controller.insets = cls == WindowClass.compact
        ? const EdgeInsets.only(top: 64, bottom: 84)
        : EdgeInsets.fromLTRB(
            settings.leftHanded ? 0 : 88,
            24, // room for the drag handle above the page
            settings.leftHanded ? 88 : 0,
            56, // room for the zoom pill
          );

    final title = _title ?? 'Document';
    final pages = _pages;
    final session = _session;

    final canvasView = CanvasView(
      controller: _controller,
      surface: _surface,
      tool: ui.tool,
      highlights: session?.highlights,
      live: _live,
      flash: _flash,
      ink: session?.ink,
      liveInk: _liveInk,
      eraser: _eraser,
      links: session?.links,
      notes: session?.notes,
      liveLink: _liveLink,
      onDelete: session == null ? null : () => _deleteSelection(session),
      selection: _selection,
      lasso: _lasso,
      onContextMenu: session == null ? null : _showContextMenu,
      onTap: session == null ? null : _onCanvasTap,
      onPointerDownOnCanvas: _hlFocus.clear,
      onTool: _pickToolByKey,
      onEscape: () {
        _hlFocus.clear();
        _selection.clear();
        _session?.links.select(null);
      },
      overlay: session == null
          ? null
          : Stack(
              fit: StackFit.expand,
              children: [
                NotesOverlay(
                  view: _controller.view,
                  scene: _controller.scene,
                  notes: session.notes,
                  actions: session,
                  viewport: () => _controller.viewport,
                  interactive:
                      ui.tool == CanvasTool.pan ||
                      ui.tool == CanvasTool.mark ||
                      ui.tool == CanvasTool.note,
                ),
                MarkSelectionOverlay(
                  view: _controller.view,
                  scene: _controller.scene,
                  selection: _selection,
                  ink: session.ink,
                  highlights: session.highlights,
                  notes: session.notes,
                  actions: _SelectionActions(this),
                  viewport: () => _controller.viewport,
                ),
                HighlightActionStrip(
                  view: _controller.view,
                  scene: _controller.scene,
                  highlights: session.highlights,
                  focus: _hlFocus,
                  actions: _hlActions,
                  viewport: () => _controller.viewport,
                ),
                LinkRemoveOverlay(
                  view: _controller.view,
                  scene: _controller.scene,
                  links: session.links,
                  notes: session.notes,
                  highlights: session.highlights,
                  onRemove: session.deleteLink,
                ),
              ],
            ),
      pen: PenConfig.forPlatform(defaultTargetPlatform),
      fingerDraws: settings.fingerDraws,
      onReady: _onReady,
      onUndo: session?.undo,
      onRedo: session?.redo,
      onCopy: _copyKey,
    );
    final canvas = Stack(
      fit: StackFit.expand,
      children: [
        canvasView,
        if (settings.perfHud)
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: AetherTokens.s2),
              child: PerfHud(
                extra: () => [
                  _surface.stats,
                  _textService?.stats,
                  _markTool?.stats,
                  _liveInk.stats,
                ].whereType<String>().join('\n'),
              ),
            ),
          ),
        if (_load != _Load.ready)
          Center(
            child: _StatusCard(
              opening: _load == _Load.opening,
              message: _error,
            ),
          ),
      ],
    );

    return Scaffold(
      body: Column(
        children: [
          CanvasTopBar(
            windowClass: cls,
            title: title,
            pageCount: pages,
            extractVisible: extractOpen,
            canUndo: session?.bus.canUndo ?? false,
            canRedo: session?.bus.canRedo ?? false,
            onUndo: session?.undo,
            onRedo: session?.redo,
            onCopy: _copyMarkdown,
            copied: _copied,
          ),
          Expanded(
            child: cls == WindowClass.compact
                ? _CompactBody(
                    controller: _controller,
                    canvas: canvas,
                    extract: _extract,
                    onClear: _eraseClear,
                  )
                : _WideBody(
                    controller: _controller,
                    canvas: canvas,
                    extract: _extract,
                    onClear: _eraseClear,
                    expanded: cls == WindowClass.expanded,
                    extractOpen: extractOpen,
                    leftHanded: settings.leftHanded,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Shown over the canvas while a document opens, or if it cannot be opened.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.opening, this.message});
  final bool opening;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return PanelSurface(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Text(
          opening
              ? 'Opening…'
              : (message ?? 'This document could not be opened.'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Figtree',
            fontSize: 14,
            color: t.ink,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

class _Zoom extends StatelessWidget {
  const _Zoom(this.controller);
  final CanvasController controller;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ViewState>(
    valueListenable: controller.view,
    builder: (context, v, _) => ZoomPill(
      zoom: v.zoom,
      onZoomOut: () => controller.zoomBy(0.8),
      onZoomIn: () => controller.zoomBy(1.25),
      onFit: controller.fitPage,
    ),
  );
}

class _WideBody extends ConsumerWidget {
  const _WideBody({
    required this.controller,
    required this.canvas,
    required this.extract,
    required this.expanded,
    required this.extractOpen,
    required this.leftHanded,
    this.onClear,
  });

  final CanvasController controller;
  final Widget canvas;
  final ExtractController? extract;
  final bool expanded, extractOpen, leftHanded;
  final EraseClearActions? onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(canvasUiProvider);
    final width = MediaQuery.sizeOf(context).width;
    // Never let the panel starve the canvas on a narrow window.
    final panelW = math.min(ui.extractWidth, math.max(240.0, width * .45));

    final stage = ClipRRect(
      borderRadius: BorderRadius.circular(AetherTokens.rPanel),
      child: Stack(
        children: [
          Positioned.fill(child: canvas),
          Positioned(
            left: leftHanded ? null : AetherTokens.s4,
            right: leftHanded ? AetherTokens.s4 : null,
            top: AetherTokens.s4,
            bottom: AetherTokens.s4,
            child: const Align(
              alignment: Alignment.topCenter,
              child: ToolRail(),
            ),
          ),
          if (ui.tool.hasPanel)
            Positioned(
              // Next to the rail, along the top: one place for every tool.
              left: leftHanded ? null : 96,
              right: leftHanded ? 96 : null,
              top: AetherTokens.s4,
              child: ToolPanel(onClear: onClear),
            ),
          Positioned(
            right: leftHanded ? null : AetherTokens.s4,
            left: leftHanded ? AetherTokens.s4 : null,
            bottom: AetherTokens.s4,
            child: _Zoom(controller),
          ),
        ],
      ),
    );

    final panel = AnimatedContainer(
      duration: AetherTokens.medium,
      curve: Curves.easeOutCubic,
      width: extractOpen ? panelW : 0,
      child: extractOpen
          ? OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: panelW,
              maxWidth: panelW,
              child: PanelSurface(child: ExtractPanel(source: extract)),
            )
          : null,
    );

    final handle = expanded && extractOpen
        ? MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) => ref
                  .read(canvasUiProvider.notifier)
                  .setExtractWidth(
                    ui.extractWidth + (leftHanded ? d.delta.dx : -d.delta.dx),
                  ),
              child: const SizedBox(
                width: AetherTokens.s3,
                height: double.infinity,
              ),
            ),
          )
        : const SizedBox(width: AetherTokens.s3);

    final children = leftHanded
        ? [panel, handle, Expanded(child: stage)]
        : [Expanded(child: stage), handle, panel];

    return Padding(
      padding: const EdgeInsets.all(AetherTokens.s3),
      child: Row(children: children),
    );
  }
}

class _CompactBody extends ConsumerWidget {
  const _CompactBody({
    required this.controller,
    required this.canvas,
    required this.extract,
    this.onClear,
  });
  final CanvasController controller;
  final Widget canvas;
  final ExtractController? extract;
  final EraseClearActions? onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(canvasUiProvider);
    final open = ui.extractOpen ?? false;
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: canvas),
              Positioned(
                top: AetherTokens.s3,
                right: AetherTokens.s3,
                child: _Zoom(controller),
              ),
              if (ui.tool.hasPanel)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 88,
                  child: Center(
                    child: ToolPanel(compact: true, onClear: onClear),
                  ),
                ),
              _ExtractSheet(open: open, source: extract),
            ],
          ),
        ),
        const BottomToolbar(),
      ],
    );
  }
}

/// Draggable Extract sheet with collapsed, half and full snap points.
class _ExtractSheet extends StatefulWidget {
  const _ExtractSheet({required this.open, required this.source});
  final bool open;
  final ExtractController? source;

  @override
  State<_ExtractSheet> createState() => _ExtractSheetState();
}

class _ExtractSheetState extends State<_ExtractSheet> {
  final DraggableScrollableController _sheet = DraggableScrollableController();
  double _peek = .1;

  @override
  void initState() {
    super.initState();
    widget.source?.collapseRequests.addListener(_collapse);
  }

  @override
  void didUpdateWidget(_ExtractSheet old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) {
      old.source?.collapseRequests.removeListener(_collapse);
      widget.source?.collapseRequests.addListener(_collapse);
    }
  }

  @override
  void dispose() {
    widget.source?.collapseRequests.removeListener(_collapse);
    _sheet.dispose();
    super.dispose();
  }

  /// A jump from Extract: get out of the way so the highlight can be seen.
  void _collapse() {
    if (!_sheet.isAttached) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _sheet.jumpTo(_peek);
    } else {
      _sheet.animateTo(
        _peek,
        duration: AetherTokens.medium,
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return LayoutBuilder(
      builder: (context, box) {
        // A peek tall enough for the drag handle and the title row, and short
        // enough that the filter chips below stay cleanly hidden.
        final peek = _peek = (68 / box.maxHeight).clamp(.08, .3);
        return DraggableScrollableSheet(
          controller: _sheet,
          initialChildSize: widget.open ? .5 : peek,
          minChildSize: peek,
          maxChildSize: .92,
          snap: true,
          snapSizes: [peek, .5, .92],
          builder: (context, controller) => DecoratedBox(
            decoration: BoxDecoration(
              color: t.panel,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AetherTokens.rPanel),
              ),
              boxShadow: t.float,
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AetherTokens.rPanel),
              ),
              child: ExtractPanel(
                source: widget.source,
                scrollController: controller,
                header: Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10),
                    decoration: BoxDecoration(
                      color: t.inkFaint,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The selection pill's actions, run against the open document.
class _EraseClear implements EraseClearActions {
  _EraseClear(this.state);
  final _CanvasScreenState state;

  @override
  void clearPageInk() => state._clearInk(pageOnly: true);

  @override
  void clearAllInk() => state._clearInk(pageOnly: false);

  @override
  void clearBoard() => state._clearBoard();
}

class _HighlightStripActions implements HighlightActions {
  _HighlightStripActions(this.state);
  final _CanvasScreenState state;

  @override
  void addNote(Highlight h) {
    state._hlFocus.clear();
    state._noteForHighlight(h);
  }

  @override
  void recolor(Highlight h, int color) => state._session?.recolorMarks([
    MarkRef(MarkKind.highlight, h.id),
  ], highlightColor: color);

  @override
  void copyQuote(Highlight h) => state._copyQuote(h);

  @override
  void delete(Highlight h) {
    final session = state._session;
    if (session == null) return;
    state._hlFocus.clear();
    session.deleteMarks([MarkRef(MarkKind.highlight, h.id)]);
    ScaffoldMessenger.maybeOf(state.context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Highlight deleted'),
          action: SnackBarAction(label: 'Undo', onPressed: session.undo),
        ),
      );
  }
}

class _SelectionActions implements SelectionActions {
  _SelectionActions(this.state);
  final _CanvasScreenState state;

  @override
  void recolorHighlight(int argb) {
    final s = state._session;
    if (s != null) s.recolorMarks(state._selection.refs, highlightColor: argb);
  }

  @override
  void recolorInk(int argb) {
    final s = state._session;
    if (s != null) s.recolorMarks(state._selection.refs, inkColor: argb);
  }

  @override
  void deleteSelection() {
    final s = state._session;
    if (s != null) state._deleteSelection(s);
  }
}
