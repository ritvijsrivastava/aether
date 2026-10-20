import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/theme/tokens.dart';
import 'canvas_ui_state.dart';
import 'engine/canvas_controller.dart';
import 'engine/grid_painter.dart';
import 'erase/erase_tool.dart';
import 'ink/ink_layer.dart';
import 'input/input_arbiter.dart';
import 'input/pen_config.dart';
import 'select/select_tool.dart' show LiveLasso;
import 'select/selection.dart';
import 'select/selection_view.dart';

/// The interactive surface: dot grid, ink, selection, and the pointer and
/// keyboard handling that drives a [CanvasController].
///
/// Everything here repaints from the controller's notifiers; a pan or zoom
/// never rebuilds this widget.
class CanvasView extends StatefulWidget {
  const CanvasView({
    super.key,
    required this.controller,
    required this.tool,
    required this.ink,
    this.liveInk,
    this.eraser,
    this.onDelete,
    this.selection,
    this.lasso,
    this.onPointerDownOnCanvas,
    this.onEscape,
    this.onTool,
    this.pen = const PenConfig(),
    this.onReady,
    this.onUndo,
    this.onRedo,
  });

  final CanvasController controller;
  final CanvasTool tool;

  /// Committed ink and the stroke being drawn.
  final InkLayer? ink;

  /// The stroke being drawn.
  final LiveInk? liveInk;

  /// The ring shown under the pen while erasing.
  final EraserState? eraser;

  /// Delete or Backspace: remove what is selected.
  final VoidCallback? onDelete;

  /// The selected strokes and the loop being drawn round them.
  final SelectionState? selection;
  final LiveLasso? lasso;

  /// Any pointer going down on the canvas (not on a widget above it).
  final VoidCallback? onPointerDownOnCanvas;

  /// Escape: cancel the stroke in progress and clear the selection.
  final VoidCallback? onEscape;

  /// Tool keys.
  final ValueChanged<CanvasTool>? onTool;

  /// Pen button bits and pressure curve for this device.
  final PenConfig pen;

  /// Called once the first layout is known (to restore the last view).
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

  bool get _panTool => widget.tool == CanvasTool.pan;
  @override
  CanvasTool get tool => widget.tool;
  @override
  PenConfig get pen => widget.pen;
  @override
  bool get spaceHeld => _space;

  // --- events ---------------------------------------------------------------

  PointerSample _sample(PointerEvent e) => PointerSample(
    id: e.pointer,
    kind: e.kind,
    position: e.localPosition,
    time: e.timeStamp,
    buttons: e.buttons,
    pressure: _pressure(e),
  );

  /// Pressure from 0 to 1, or null when the device has none to give: only a
  /// pen reports it, and a pen under X11 shows up as a mouse with a constant
  /// pressure, which is not information.
  static double? _pressure(PointerEvent e) {
    final pen =
        e.kind == PointerDeviceKind.stylus ||
        e.kind == PointerDeviceKind.invertedStylus;
    if (!pen || e.pressureMax <= e.pressureMin) return null;
    return ((e.pressure - e.pressureMin) / (e.pressureMax - e.pressureMin))
        .clamp(0.0, 1.0);
  }

  void _updateCursor(Offset p) {
    final MouseCursor c = _space || _panTool
        ? SystemMouseCursors.grab
        : switch (widget.tool) {
            CanvasTool.ink ||
            CanvasTool.erase ||
            CanvasTool.select => SystemMouseCursors.precise,
            _ => SystemMouseCursors.basic,
          };
    if (c != _cursor) setState(() => _cursor = c);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e.logicalKey == LogicalKeyboardKey.space) {
      final down = e is! KeyUpEvent;
      if (down != _space) setState(() => _space = down);
      return KeyEventResult.handled;
    }
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      _arbiter.escape();
      widget.onEscape?.call();
      return KeyEventResult.handled;
    }
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
    if (!ctrl && !HardwareKeyboard.instance.isAltPressed) {
      final label = k.keyLabel.toUpperCase();
      if (widget.onTool != null) {
        for (final t in CanvasTool.values) {
          if (t.key == label) {
            widget.onTool!(t);
            return KeyEventResult.handled;
          }
        }
      }
    }
    if (ctrl && k == LogicalKeyboardKey.keyZ) {
      final redo = HardwareKeyboard.instance.isShiftPressed;
      (redo ? widget.onRedo : widget.onUndo)?.call();
      return KeyEventResult.handled;
    }
    if ((k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) &&
        widget.onDelete != null) {
      widget.onDelete!();
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.keyY) {
      widget.onRedo?.call();
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.digit0) {
      c.fit();
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
        c.viewport = size;
        if (!_ready && !size.isEmpty) {
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
                widget.onPointerDownOnCanvas?.call();
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
                    if (widget.ink != null)
                      RepaintBoundary(
                        child: CustomPaint(
                          painter: InkPainter(
                            view: c.view,
                            ink: widget.ink!,
                            devicePixelRatio: MediaQuery.devicePixelRatioOf(
                              context,
                            ),
                          ),
                        ),
                      ),
                    if (widget.liveInk != null)
                      RepaintBoundary(
                        child: CustomPaint(
                          painter: LiveInkPainter(
                            view: c.view,
                            live: widget.liveInk!,
                          ),
                        ),
                      ),
                    if (widget.selection != null &&
                        widget.lasso != null &&
                        widget.ink != null)
                      RepaintBoundary(
                        child: CustomPaint(
                          painter: SelectionPainter(
                            view: c.view,
                            selection: widget.selection!,
                            lasso: widget.lasso!,
                            ink: widget.ink!,
                            tokens: t,
                          ),
                        ),
                      ),
                    if (widget.eraser != null)
                      RepaintBoundary(
                        child: CustomPaint(
                          painter: EraserPainter(
                            eraser: widget.eraser!,
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
