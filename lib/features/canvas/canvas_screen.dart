import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, defaultTargetPlatform;
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../ui/theme/theme.dart' show AetherText;
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/panel_surface.dart';
import '../../ui/adaptive/window_class.dart';
import 'canvas_pill.dart';
import 'canvas_ui_state.dart';
import 'canvas_view.dart';
import 'document_session.dart';
import 'erase/erase_options.dart';
import 'erase/erase_tool.dart';
import 'ink/ink_layer.dart';
import 'ink/ink_tool.dart';
import 'input/pen_config.dart';
import 'input/tool_gestures.dart' show ToolRouter;
import 'engine/canvas_controller.dart';
import 'engine/view_state.dart';
import 'perf_hud.dart';
import 'select/select_tool.dart';
import 'select/selection.dart';
import 'select/selection_view.dart' show MarkSelectionOverlay, SelectionActions;
import 'tool_panel.dart';
import 'tool_palette.dart';
import 'zoom_pill.dart';

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
  DocumentSession? _session;
  final LiveInk _liveInk = LiveInk();
  final EraserState _eraser = EraserState();
  final SelectionState _selection = SelectionState();
  final ValueNotifier<String?> _toast = ValueNotifier(null);
  Timer? _toastTimer;
  final LiveLasso _lasso = LiveLasso();
  Listenable? _layerChanges;
  late final EraseClearActions _eraseClear = _EraseClear(this);
  StreamSubscription<void>? _history;
  _Load _load = _Load.ready;
  String? _error;
  String? _title;

  @override
  void initState() {
    super.initState();
    _controller = CanvasController()..attach(this);
    _load = _Load.opening;
    _openDocument();
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
      live: _liveInk,
      widthDp: () => ref.read(canvasUiProvider).inkWidth,
      color: () => InkPalette.resolve(
        ref.read(canvasUiProvider).inkColor,
        Theme.of(context).brightness,
      ),
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
    _selection.addListener(_deleteSelection);
    // Strokes that go away (deleted, undone) leave the selection.
    _layerChanges = Listenable.merge([session.ink])
      ..addListener(_pruneSelection);
    _history = session.bus.changes.listen((_) {
      if (mounted) setState(() {});
    });
    _controller.contentBounds = () {
      final b = session.ink.bounds;
      return b == null ? null : Rect.fromLTRB(b.x0, b.y0, b.x1, b.y1);
    };
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

  /// A short notice under the name pill. It fades by itself; there is
  /// nothing to dismiss (Undo lives in the pill).
  void _say(String message) {
    _toastTimer?.cancel();
    _toast.value = message;
    _toastTimer = Timer(const Duration(milliseconds: 1400), () {
      _toast.value = null;
    });
  }

  /// Delete or Backspace: remove the selected strokes.
  void _deleteSelection() {
    final session = _session;
    if (session == null || _selection.isEmpty) return;
    final n = _selection.count;
    session.deleteMarks(_selection.refs);
    _selection.clear();
    _say(n == 1 ? 'Deleted 1 stroke' : 'Deleted $n strokes');
  }

  /// Everything on the board, after asking; one undo step.
  Future<void> _clearAll() async {
    final session = _session;
    if (session == null) return;
    final strokes = session.ink.all.toList();
    if (strokes.isEmpty) {
      _say('The board is already clear');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all?'),
        content: Text(
          strokes.length == 1
              ? 'This removes the 1 stroke on the board. You can undo it.'
              : 'This removes all ${strokes.length} strokes on the board. '
                    'You can undo it.',
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
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _selection.clear();
    session.deleteMarks([
      for (final s in session.ink.all) MarkRef(MarkKind.ink, s.id),
    ]);
    _say('Board cleared');
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

  /// First layout is known: restore the remembered view, or fit the content.
  Future<void> _onReady() async {
    final saved = await _session?.savedView();
    if (!mounted) return;
    saved != null
        ? _controller.setView(saved)
        : _controller.fit(animate: false);
  }

  @override
  void dispose() {
    _controller.tools = null;
    _liveInk.dispose();
    _eraser.dispose();
    _layerChanges?.removeListener(_pruneSelection);
    _selection.removeListener(_deleteSelection);
    _selection.dispose();
    _toastTimer?.cancel();
    _toast.dispose();
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
        ? const EdgeInsets.only(top: 64, bottom: 88)
        : EdgeInsets.fromLTRB(
            settings.leftHanded ? 0 : ToolRail.width + 24,
            64, // room for the name pill
            settings.leftHanded ? ToolRail.width + 24 : 0,
            24,
          );

    final title = _title ?? 'Board';
    final session = _session;

    final canvasView = CanvasView(
      controller: _controller,
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
      },
      onEscape: _selection.clear,
      onTool: _pickToolByKey,
      pen: PenConfig.forPlatform(defaultTargetPlatform),
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
        Positioned(
          top: 64,
          left: 0,
          right: 0,
          child: IgnorePointer(child: Center(child: _Toast(_toast))),
        ),
        if (settings.perfHud)
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: AetherTokens.s2),
              child: PerfHud(
                extra: () => [_liveInk.stats].whereType<String>().join('\n'),
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

    final pill = CanvasPill(
      title: title,
      canUndo: session?.bus.canUndo ?? false,
      canRedo: session?.bus.canRedo ?? false,
      onUndo: session?.undo,
      onRedo: session?.redo,
    );
    return Scaffold(
      body: cls == WindowClass.compact
          ? _CompactBody(
              controller: _controller,
              canvas: canvas,
              pill: pill,
              onClear: _eraseClear,
            )
          : _WideBody(
              controller: _controller,
              canvas: canvas,
              pill: pill,
              leftHanded: settings.leftHanded,
              onClear: _eraseClear,
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
      onFit: controller.fit,
    ),
  );
}

class _WideBody extends ConsumerWidget {
  const _WideBody({
    required this.controller,
    required this.canvas,
    required this.pill,
    required this.leftHanded,
    this.onClear,
  });

  final CanvasController controller;
  final Widget canvas, pill;
  final bool leftHanded;
  final EraseClearActions? onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(canvasUiProvider);
    return Stack(
      children: [
        Positioned.fill(child: canvas),
        Positioned(
          top: AetherTokens.s3,
          left: 0,
          right: 0,
          child: Center(child: pill),
        ),
        Positioned(
          left: leftHanded ? null : AetherTokens.s3,
          right: leftHanded ? AetherTokens.s3 : null,
          top: AetherTokens.s3,
          bottom: AetherTokens.s3,
          child: const Align(alignment: Alignment.topCenter, child: ToolRail()),
        ),
        if (ui.tool.hasPanel)
          Positioned(
            // Beside the rail, level with its tool button.
            left: leftHanded ? null : ToolRail.width + AetherTokens.s3 * 2,
            right: leftHanded ? ToolRail.width + AetherTokens.s3 * 2 : null,
            top: ToolRail.panelTop(ui.tool),
            child: ToolPanel(onClear: onClear),
          ),
        Positioned(
          right: leftHanded ? null : AetherTokens.s3,
          left: leftHanded ? AetherTokens.s3 : null,
          top: AetherTokens.s3,
          child: _Zoom(controller),
        ),
      ],
    );
  }
}

class _CompactBody extends ConsumerWidget {
  const _CompactBody({
    required this.controller,
    required this.canvas,
    required this.pill,
    this.onClear,
  });
  final CanvasController controller;
  final Widget canvas, pill;
  final EraseClearActions? onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(canvasUiProvider);
    return Stack(
      children: [
        Positioned.fill(child: canvas),
        Positioned(top: AetherTokens.s3, left: AetherTokens.s3, child: pill),
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
            child: Center(child: ToolPanel(onClear: onClear)),
          ),
        const Positioned(left: 0, right: 0, bottom: 0, child: BottomToolbar()),
      ],
    );
  }
}

/// A one-line notice that fades in and out.
class _Toast extends StatelessWidget {
  const _Toast(this.message);
  final ValueNotifier<String?> message;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ValueListenableBuilder<String?>(
      valueListenable: message,
      builder: (context, m, _) => AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: m == null ? 0 : 1,
        child: m == null
            ? const SizedBox.shrink()
            : PanelSurface(
                radius: AetherTokens.rPill,
                padding: const EdgeInsets.symmetric(
                  horizontal: AetherTokens.s3,
                  vertical: AetherTokens.s2,
                ),
                child: Text(m, style: AetherText(t.ink).label),
              ),
      ),
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
    if (s != null) {
      s.recolorMarks(
        state._selection.refs,
        inkColor: InkPalette.resolve(argb, Theme.of(state.context).brightness),
      );
    }
  }

  @override
  void deleteSelection() {
    final s = state._session;
    if (s != null) state._deleteSelection();
  }
}

/// The Erase panel's Clear all row, run against the open document.
class _EraseClear implements EraseClearActions {
  _EraseClear(this.state);
  final _CanvasScreenState state;

  @override
  void clearAll() => state._clearAll();
}
