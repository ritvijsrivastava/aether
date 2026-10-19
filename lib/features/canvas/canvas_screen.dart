import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/pdf/page_text_service.dart';
import '../../domain/export/markdown_exporter.dart';
import '../../domain/model/models.dart';
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
import 'ink/ink_options.dart';
import 'ink/ink_tool.dart';
import 'input/pen_config.dart';
import 'input/tool_gestures.dart';
import 'links/link_remove_overlay.dart';
import 'links/link_tool.dart';
import 'links/links_layer.dart';
import 'marks/flash.dart';
import 'notes/note_tool.dart';
import 'notes/notes_overlay.dart';
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
      meaning: () => ref.read(canvasUiProvider).meaning,
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
    _history = session.bus.changes.listen((_) {
      if (mounted) setState(() {});
    });
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
      ..show(Flash(card.id, h.rects, h.meaning));
    _extract?.collapseRequests.value++;
  }

  /// Copy as Markdown: the whole Extract list, grouped by meaning.
  Future<void> _copyMarkdown() async {
    final items = _extract?.items(ExtractFilter.all) ?? const [];
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (items.isEmpty) {
      messenger
        ?..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Nothing to copy yet.')));
      return;
    }
    await Clipboard.setData(
      ClipboardData(text: MarkdownExporter.export(_title ?? 'Document', items)),
    );
    if (!mounted) return;
    messenger
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            items.length == 1
                ? 'Copied 1 highlight as Markdown.'
                : 'Copied ${items.length} highlights as Markdown.',
          ),
        ),
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

  /// Delete or Backspace: remove what is selected (a link, for now).
  void _deleteSelection(DocumentSession session) {
    final id = session.links.selectedId;
    if (id != null) session.deleteLink(id);
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
      onCopy: _copyMarkdown,
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
                  )
                : _WideBody(
                    controller: _controller,
                    canvas: canvas,
                    extract: _extract,
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
  });

  final CanvasController controller;
  final Widget canvas;
  final ExtractController? extract;
  final bool expanded, extractOpen, leftHanded;

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
          if (ui.tool == CanvasTool.ink)
            Positioned(
              // Beside the rail, level with the Ink button.
              left: leftHanded ? null : 96,
              right: leftHanded ? 96 : null,
              top: AetherTokens.s4 + 2 * 60,
              child: const InkOptions(),
            ),
          if (ui.tool == CanvasTool.erase)
            Positioned(
              left: leftHanded ? null : 96,
              right: leftHanded ? 96 : null,
              top: AetherTokens.s4 + 3 * 60,
              child: const EraseOptions(),
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
  });
  final CanvasController controller;
  final Widget canvas;
  final ExtractController? extract;

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
              if (ui.tool == CanvasTool.mark)
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 88,
                  child: Center(child: MeaningStrip()),
                ),
              if (ui.tool == CanvasTool.erase)
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 88,
                  child: Center(child: EraseOptions()),
                ),
              if (ui.tool == CanvasTool.ink)
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 88,
                  child: Center(child: InkOptions(sliderWidth: 80)),
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
