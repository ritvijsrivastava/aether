import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/theme/tokens.dart';
import 'canvas_ui_state.dart';
import 'engine/canvas_controller.dart';
import 'engine/page_surface.dart';
import 'engine/painters.dart';
import 'input/input_arbiter.dart';

/// The interactive surface: grid, cards, drag handles, and the pointer and
/// keyboard handling that drives a [CanvasController].
///
/// Everything here repaints from the controller's notifiers; a pan or zoom
/// never rebuilds this widget.
class CanvasView extends StatefulWidget {
  const CanvasView({
    super.key,
    required this.controller,
    required this.surface,
    required this.tool,
    this.fingerDraws = false,
    this.onReady,
    this.onUndo,
    this.onRedo,
  });

  final CanvasController controller;
  final PageSurface surface;
  final CanvasTool tool;
  final bool fingerDraws;

  /// Called once the first non-empty layout is known (to fit the first page).
  final VoidCallback? onReady;

  /// Ctrl+Z and Ctrl+Shift+Z / Ctrl+Y. Null when there is no history.
  final VoidCallback? onUndo, onRedo;

  @override
  State<CanvasView> createState() => _CanvasViewState();
}

class _CanvasViewState extends State<CanvasView> implements ArbiterContext {
  late final InputArbiter _arbiter = InputArbiter(widget.controller, this);
  final FocusNode _focus = FocusNode(debugLabel: 'canvas');
  bool _space = false;
  bool _ready = false;
  MouseCursor _cursor = SystemMouseCursors.basic;

  // --- ArbiterContext -------------------------------------------------------

  @override
  bool get panTool => widget.tool == CanvasTool.pan;
  @override
  bool get spaceHeld => _space;
  @override
  bool get fingerDraws => widget.fingerDraws;

  @override
  String? handleAt(Offset screen) {
    final v = widget.controller.view.value;
    final size = widget.controller.viewport;
    final cards = widget.controller.scene.value
        .visible(v.worldRect(size))
        .toList();
    // Topmost (last drawn) first.
    for (final c in cards.reversed) {
      if (HandleLayout.hitRect(c, v)?.contains(screen) ?? false) return c.id;
    }
    return null;
  }

  // --- events ---------------------------------------------------------------

  PointerSample _sample(PointerEvent e) => PointerSample(
    id: e.pointer,
    kind: e.kind,
    position: e.localPosition,
    time: e.timeStamp,
    buttons: e.buttons,
    radiusMajor: e.radiusMajor,
  );

  void _updateCursor(Offset p) {
    final MouseCursor c = _space || panTool
        ? SystemMouseCursors.grab
        : handleAt(p) != null
        ? SystemMouseCursors.grab
        : SystemMouseCursors.basic;
    if (c != _cursor) setState(() => _cursor = c);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e.logicalKey == LogicalKeyboardKey.space) {
      final down = e is! KeyUpEvent;
      if (down != _space) setState(() => _space = down);
      return KeyEventResult.handled;
    }
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final c = widget.controller;
    final ctrl =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.equal ||
        k == LogicalKeyboardKey.add ||
        k == LogicalKeyboardKey.numpadAdd) {
      c.zoomBy(1.25);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.minus ||
        k == LogicalKeyboardKey.numpadSubtract) {
      c.zoomBy(0.8);
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.keyZ) {
      final redo = HardwareKeyboard.instance.isShiftPressed;
      (redo ? widget.onRedo : widget.onUndo)?.call();
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.keyY) {
      widget.onRedo?.call();
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.digit0) {
      c.fitPage();
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.digit1) {
      c.zoomTo(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = widget.controller;
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        if (c.viewport != size) {
          c.viewport = size;
          // Re-clamp for the new size (window resize, rotation) next frame.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            // An untouched first fit follows the screen size (see
            // CanvasController.refitOnResize); anything else is just re-clamped.
            c.refitOnResize ? c.fitFirst() : c.setView(c.view.value);
          });
        }
        if (!_ready && !size.isEmpty && !c.scene.value.isEmpty) {
          _ready = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onReady?.call();
          });
        }
        return Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: MouseRegion(
            cursor: _cursor,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) {
                _focus.requestFocus();
                _arbiter.down(_sample(e));
              },
              onPointerMove: (e) => _arbiter.move(_sample(e)),
              onPointerUp: (e) => _arbiter.up(_sample(e)),
              onPointerCancel: (e) => _arbiter.cancel(_sample(e)),
              onPointerHover: (e) {
                _arbiter.hover(_sample(e));
                _updateCursor(e.localPosition);
              },
              onPointerSignal: (e) {
                if (e is PointerScrollEvent) {
                  _arbiter.scroll(
                    e.localPosition,
                    e.scrollDelta,
                    ctrl: HardwareKeyboard.instance.isControlPressed,
                  );
                }
              },
              onPointerPanZoomStart: (_) => _arbiter.panZoomStart(),
              onPointerPanZoomUpdate: (e) =>
                  _arbiter.panZoomUpdate(e.localPosition, e.localPan, e.scale),
              onPointerPanZoomEnd: (_) => _arbiter.panZoomEnd(),
              child: ColoredBox(
                color: t.canvas,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    RepaintBoundary(
                      child: CustomPaint(
                        painter: GridPainter(view: c.view, color: t.gridDot),
                      ),
                    ),
                    RepaintBoundary(
                      child: CustomPaint(
                        painter: CardsPainter(
                          view: c.view,
                          scene: c.scene,
                          surface: widget.surface,
                          tokens: t,
                          devicePixelRatio: MediaQuery.devicePixelRatioOf(
                            context,
                          ),
                        ),
                      ),
                    ),
                    RepaintBoundary(
                      child: CustomPaint(
                        painter: HandlesPainter(
                          view: c.view,
                          scene: c.scene,
                          tokens: t,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
