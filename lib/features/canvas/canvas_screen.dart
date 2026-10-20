import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, defaultTargetPlatform;
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/panel_surface.dart';
import '../../ui/adaptive/window_class.dart';
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
import 'input/tool_gestures.dart' show ToolRouter;
import 'engine/canvas_controller.dart';
import 'engine/page_surface.dart';
import 'engine/scene.dart';
import 'engine/view_state.dart';
import 'perf_hud.dart';
import 'select/select_tool.dart';
import 'select/selection.dart';
import 'select/selection_view.dart' show MarkSelectionOverlay, SelectionActions;
import 'tool_panel.dart';
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

/// The board workspace. Layout adapts to the window class:
/// compact = full-bleed canvas + bottom toolbar; medium/expanded = tool rail.
class CanvasScreen extends ConsumerStatefulWidget {
  const CanvasScreen({super.key, required this.docId});
  final String docId;

  @override
  ConsumerState<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends ConsumerState<CanvasScreen>
    with TickerProviderStateMixin {
  late final CanvasController _controller;
  final PageSurface _surface = SyntheticPageSurface();
  DocumentSession? _session;
  final LiveInk _liveInk = LiveInk();
  final EraserState _eraser = EraserState();
  final SelectionState _selection = SelectionState();
  final LiveLasso _lasso = LiveLasso();
  Listenable? _layerChanges;
  late final EraseClearActions _eraseClear = _EraseClear(this);
  StreamSubscription<void>? _history;
  _Load _load = _Load.ready;
  String? _error;
  String? _title;

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
      CanvasTool.ink: inkTool,
      CanvasTool.select: SelectToolController(
        view: _controller.view,
        selection: _selection,
        live: _lasso,
        ink: session.ink,
        shift: () => HardwareKeyboard.instance.isShiftPressed,
        sink: session,
      ),
      CanvasTool.erase: EraseToolController(
        view: _controller.view,
        ink: session.ink,
        eraser: _eraser,
        partial: () => ref.read(canvasUiProvider).erasePartial,
        sink: session,
      ),
    });
    session.onGestureDone = (t) => ref
        .read(canvasUiProvider.notifier)
        .gestureDone(
          t,
          autoHide: ref.read(settingsProvider).value?.autoHideToolPanel ?? true,
        );
    _selection.addListener(_deleteSelection);
    // Strokes that go away (deleted, undone) leave the selection.
    _layerChanges = Listenable.merge([session.ink])
      ..addListener(_pruneSelection);
    _history = session.bus.changes.listen((_) {
      if (mounted) setState(() {});
    });
    if (stressInkEnabled && _controller.scene.value.cards.isNotEmpty) {
      // Measuring only: strokes held in memory, never saved.
      session.ink.replaceAll([
        ...session.ink.all,
        ...stressStrokes(
          _controller.scene.value.cards.first.id,
          stressInkCount,
        ),
      ]);
    }
    if (mounted) {
      setState(() {
        _load = _Load.ready;
        _title = session.document?.title ?? 'Board';
      });
    }
  }

  void _pruneSelection() {
    final s = _session;
    if (s == null) return;
    _selection.prune((r) => s.ink.byId(r.id) != null);
  }

  /// Delete or Backspace: remove the selected strokes, with Undo offered.
  void _deleteSelection() {
    final session = _session;
    if (session == null || _selection.isEmpty) return;
    final n = _selection.count;
    session.deleteMarks(_selection.refs);
    _selection.clear();
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(n == 1 ? 'Deleted 1 stroke' : 'Deleted $n strokes'),
          action: SnackBarAction(label: 'Undo', onPressed: session.undo),
        ),
      );
  }

  /// All ink on the board, one undo step.
  void _clearAllInk() {
    final session = _session;
    if (session == null) return;
    final strokes = session.ink.all.toList();
    if (strokes.isEmpty) {
      _say('No ink to clear.');
      return;
    }
    session.deleteMarks([for (final s in strokes) MarkRef(MarkKind.ink, s.id)]);
    _say('');
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            strokes.length == 1
                ? 'Cleared 1 stroke'
                : 'Cleared ${strokes.length} strokes',
          ),
          action: SnackBarAction(label: 'Undo', onPressed: session.undo),
        ),
      );
  }

  void _say(String message) => ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

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

  /// First layout is known: restore the remembered view, or fit the content.
  Future<void> _onReady() async {
    final saved = await _session?.savedView();
    if (!mounted) return;
    saved != null ? _controller.setView(saved) : _controller.fitFirst();
  }

  @override
  void dispose() {
    _controller.tools = null;
    _liveInk.dispose();
    _eraser.dispose();
    _layerChanges?.removeListener(_pruneSelection);
    _selection.removeListener(_deleteSelection);
    _selection.dispose();
    _lasso.dispose();
    _history?.cancel();
    _session?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final cls = WindowClass.of(size.width);
    final ui = ref.watch(canvasUiProvider);
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();

    // Fit and zoom aim at the area the floating controls leave free.
    _controller.insets = cls == WindowClass.compact
        ? const EdgeInsets.only(top: 8, bottom: 84)
        : EdgeInsets.fromLTRB(
            settings.leftHanded ? 0 : 88,
            8,
            settings.leftHanded ? 88 : 0,
            56, // room for the zoom pill
          );

    final title = _title ?? 'Board';
    final session = _session;

    final canvasView = CanvasView(
      controller: _controller,
      surface: _surface,
      tool: ui.tool,
      ink: session?.ink,
      liveInk: _liveInk,
      eraser: _eraser,
      onDelete: session == null ? null : _deleteSelection,
      selection: _selection,
      lasso: _lasso,
      onPointerDownOnCanvas: () {
        // The Select tool manages its own selection.
        if (ui.tool != CanvasTool.select) _selection.clear();
        ref
            .read(canvasUiProvider.notifier)
            .canvasPressed(
              autoHide:
                  ref.read(settingsProvider).value?.autoHideToolPanel ?? true,
            );
      },
      onEscape: _selection.clear,
      onTool: _pickToolByKey,
      pen: PenConfig.forPlatform(defaultTargetPlatform),
      fingerDraws: settings.fingerDraws,
      onReady: _onReady,
      onUndo: session?.undo,
      onRedo: session?.redo,
    );
    final canvas = Stack(
      fit: StackFit.expand,
      children: [
        canvasView,
        if (session != null)
          MarkSelectionOverlay(
            view: _controller.view,
            selection: _selection,
            ink: session.ink,
            actions: _SelectionActions(this),
            viewport: () => _controller.viewport,
          ),
        if (settings.perfHud)
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: AetherTokens.s2),
              child: PerfHud(
                extra: () => [
                  _surface.stats,
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
            canUndo: session?.bus.canUndo ?? false,
            canRedo: session?.bus.canRedo ?? false,
            onUndo: session?.undo,
            onRedo: session?.redo,
          ),
          Expanded(
            child: cls == WindowClass.compact
                ? _CompactBody(
                    controller: _controller,
                    canvas: canvas,
                    onClear: _eraseClear,
                  )
                : _WideBody(
                    controller: _controller,
                    canvas: canvas,
                    leftHanded: settings.leftHanded,
                    onClear: _eraseClear,
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
    required this.leftHanded,
    this.onClear,
  });

  final CanvasController controller;
  final Widget canvas;
  final bool leftHanded;
  final EraseClearActions? onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(canvasUiProvider);

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
              // A column hanging from the rail, level with its tool button.
              left: leftHanded ? null : 96,
              right: leftHanded ? 96 : null,
              top: AetherTokens.s4 + 2 + ui.tool.panelIndex * 60,
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

    return Padding(
      padding: const EdgeInsets.all(AetherTokens.s3),
      child: Row(children: [Expanded(child: stage)]),
    );
  }
}

class _CompactBody extends ConsumerWidget {
  const _CompactBody({
    required this.controller,
    required this.canvas,
    this.onClear,
  });
  final CanvasController controller;
  final Widget canvas;
  final EraseClearActions? onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(canvasUiProvider);
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
            ],
          ),
        ),
        const BottomToolbar(),
      ],
    );
  }
}

/// The selection pill's actions, run against the open document.
class _SelectionActions implements SelectionActions {
  _SelectionActions(this.state);
  final _CanvasScreenState state;

  @override
  void recolorInk(int argb) {
    final s = state._session;
    if (s != null) s.recolorMarks(state._selection.refs, inkColor: argb);
  }

  @override
  void deleteSelection() {
    final s = state._session;
    if (s != null) state._deleteSelection();
  }
}

/// The Erase panel's clear button, run against the open document.
class _EraseClear implements EraseClearActions {
  _EraseClear(this.state);
  final _CanvasScreenState state;

  @override
  void clearAllInk() => state._clearAllInk();
}
