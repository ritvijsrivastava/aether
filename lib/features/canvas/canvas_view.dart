import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/theme/tokens.dart';
import 'canvas_ui_state.dart';
import 'engine/canvas_controller.dart';
import 'engine/page_surface.dart';
import 'engine/painters.dart';
import 'erase/erase_tool.dart';
import 'ink/ink_layer.dart';
import 'marks/flash.dart';
import 'notes/notes_layer.dart';
import 'select/select_tool.dart';
import 'select/selection.dart';
import 'select/selection_view.dart';
import 'marks/mark_layers.dart';
import 'input/input_arbiter.dart';
import 'input/pen_config.dart';
import 'links/links_layer.dart';

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
    this.highlights,
    this.live,
    this.flash,
    this.ink,
    this.liveInk,
    this.eraser,
    this.overlay,
    this.links,
    this.notes,
    this.liveLink,
    this.onDelete,
    this.selection,
    this.lasso,
    this.onContextMenu,
    this.onTap,
    this.onPointerDownOnCanvas,
    this.touchStats,
    this.onEscape,
    this.onTool,
    this.pen = const PenConfig(),
    this.fingerDraws = false,
    this.onReady,
    this.onUndo,
    this.onRedo,
    this.onCopy,
  });

  final CanvasController controller;
  final PageSurface surface;
  final CanvasTool tool;

  /// The document's highlights and the one being dragged; null in the
  /// synthetic test documents.
  final HighlightLayer? highlights;
  final ValueNotifier<LiveMark?>? live;

  /// The outline shown on a highlight after jumping to it from Extract.
  final FlashController? flash;

  /// Committed ink and the stroke being drawn; null in the synthetic test
  /// documents.
  final InkLayer? ink;
  final LiveInk? liveInk;

  /// The ring shown under the pen while erasing.
  final EraserState? eraser;

  /// Widgets drawn above the canvas and handling their own pointers (notes).
  final Widget? overlay;

  /// Link lines and the one being dragged out, drawn under the notes.
  final LinksLayer? links;
  final NotesLayer? notes;
  final LiveLink? liveLink;

  /// Delete or Backspace: remove what is selected.
  final VoidCallback? onDelete;

  /// The selected marks and the loop being drawn round them.
  final SelectionState? selection;
  final LiveLasso? lasso;

  /// A right-click, or a long press with a finger, at a canvas position (local
  /// and global).
  final void Function(Offset local, Offset global)? onContextMenu;

  /// A tap (a short press that does not move) with the Pan tool, at a canvas
  /// position.
  final ValueChanged<Offset>? onTap;

  /// What touch contacts have looked like (shown in the performance overlay).
  final TouchStats? touchStats;

  /// Any pointer going down on the canvas (not on a widget above it).
  final VoidCallback? onPointerDownOnCanvas;

  /// Escape: clear what is selected.
  final VoidCallback? onEscape;

  /// Tool keys (H M P E N L S).
  final ValueChanged<CanvasTool>? onTool;

  /// Pen button bits and pressure curve for this device.
  final PenConfig pen;
  final bool fingerDraws;

  /// Called once the first non-empty layout is known (to fit the first page).
  final VoidCallback? onReady;

  /// Ctrl+Z and Ctrl+Shift+Z / Ctrl+Y. Null when there is no history.
  final VoidCallback? onUndo, onRedo;

  /// Ctrl+C: with nothing selected, copy the Extract list as Markdown.
  final VoidCallback? onCopy;

  @override
  State<CanvasView> createState() => _CanvasViewState();
}

class _CanvasViewState extends State<CanvasView> implements ArbiterContext {
  late final InputArbiter _arbiter = InputArbiter(
    widget.controller,
    this,
    stats: widget.touchStats,
  );
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
        : handleAt(p) != null
        ? SystemMouseCursors.grab
        : switch (widget.tool) {
            CanvasTool.mark => SystemMouseCursors.text,
            CanvasTool.ink ||
            CanvasTool.erase ||
            CanvasTool.link ||
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
    if (ctrl && k == LogicalKeyboardKey.keyC && widget.onCopy != null) {
      widget.onCopy!();
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

  // --- tap (Pan tool) --------------------------------------------------------

  int? _tapPointer;
  Offset _tapStart = Offset.zero;
  Timer? _tapTimer;

  void _watchTap(PointerDownEvent e) {
    // A second pointer is a pinch, not a tap.
    if (_tapPointer != null) {
      _tapPointer = null;
      return;
    }
    if (widget.onTap == null || !_panTool) return;
    _tapPointer = e.pointer;
    _tapStart = e.localPosition;
    _tapTimer?.cancel();
    _tapTimer = Timer(const Duration(milliseconds: 400), () {
      _tapPointer = null;
    });
  }

  void _tapMoved(PointerMoveEvent e) {
    if (e.pointer == _tapPointer &&
        (e.localPosition - _tapStart).distance > 8) {
      _tapPointer = null;
    }
  }

  void _tapUp(PointerUpEvent e) {
    if (e.pointer != _tapPointer) return;
    _tapPointer = null;
    _tapTimer?.cancel();
    widget.onTap?.call(e.localPosition);
  }

  // --- long press (a finger): the context menu ----------------------------------

  Timer? _longPress;
  int? _longPressPointer;
  Offset _longPressStart = Offset.zero;
  static const Duration _longPressTime = Duration(milliseconds: 500);
  static const double _longPressSlop = 10;

  void _watchLongPress(PointerDownEvent e) {
    if (widget.onContextMenu == null) return;
    // A second finger is a pinch: not a long press.
    if (_longPressPointer != null) {
      _stopLongPress(_longPressPointer!);
      return;
    }
    if (e.kind != PointerDeviceKind.touch) return;
    _longPressPointer = e.pointer;
    _longPressStart = e.localPosition;
    final global = e.position;
    _longPress = Timer(_longPressTime, () {
      _longPress = null;
      _longPressPointer = null;
      widget.onContextMenu?.call(_longPressStart, global);
    });
  }

  void _longPressMoved(PointerMoveEvent e) {
    if (e.pointer == _longPressPointer &&
        (e.localPosition - _longPressStart).distance > _longPressSlop) {
      _stopLongPress(e.pointer);
    }
  }

  void _stopLongPress(int pointer) {
    if (pointer != _longPressPointer) return;
    _longPress?.cancel();
    _longPress = null;
    _longPressPointer = null;
  }

  @override
  void dispose() {
    _tapTimer?.cancel();
    _longPress?.cancel();
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
        final surface = Focus(
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
                _watchTap(e);
                if (e.kind == PointerDeviceKind.mouse &&
                    e.buttons & kSecondaryButton != 0 &&
                    widget.onContextMenu != null) {
                  widget.onContextMenu!(e.localPosition, e.position);
                  return;
                }
                _watchLongPress(e);
                _arbiter.down(_sample(e));
              },
              onPointerMove: (e) {
                _tapMoved(e);
                _longPressMoved(e);
                _arbiter.move(_sample(e));
              },
              onPointerUp: (e) {
                _tapUp(e);
                _stopLongPress(e.pointer);
                _arbiter.up(_sample(e));
              },
              onPointerCancel: (e) {
                if (e.pointer == _tapPointer) _tapPointer = null;
                _stopLongPress(e.pointer);
                _arbiter.cancel(_sample(e));
              },
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
                          highlights: widget.highlights,
                        ),
                      ),
                    ),
                    if (widget.flash != null)
                      RepaintBoundary(
                        child: CustomPaint(
                          painter: FlashPainter(
                            view: c.view,
                            scene: c.scene,
                            flash: widget.flash!,
                            tokens: t,
                          ),
                        ),
                      ),
                    if (widget.live != null)
                      RepaintBoundary(
                        child: CustomPaint(
                          painter: LiveMarkPainter(
                            view: c.view,
                            scene: c.scene,
                            live: widget.live!,
                          ),
                        ),
                      ),
                    if (widget.ink != null)
                      RepaintBoundary(
                        child: CustomPaint(
                          painter: InkPainter(
                            view: c.view,
                            scene: c.scene,
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
                            scene: c.scene,
                            live: widget.liveInk!,
                          ),
                        ),
                      ),
                    if (widget.links != null &&
                        widget.notes != null &&
                        widget.highlights != null)
                      RepaintBoundary(
                        child: CustomPaint(
                          painter: LinksPainter(
                            view: c.view,
                            scene: c.scene,
                            links: widget.links!,
                            notes: widget.notes!,
                            highlights: widget.highlights!,
                            tokens: t,
                          ),
                        ),
                      ),
                    if (widget.selection != null &&
                        widget.lasso != null &&
                        widget.ink != null &&
                        widget.highlights != null &&
                        widget.notes != null)
                      RepaintBoundary(
                        child: CustomPaint(
                          painter: SelectionPainter(
                            view: c.view,
                            scene: c.scene,
                            selection: widget.selection!,
                            lasso: widget.lasso!,
                            ink: widget.ink!,
                            highlights: widget.highlights!,
                            notes: widget.notes!,
                            tokens: t,
                          ),
                        ),
                      ),
                    if (widget.liveLink != null)
                      RepaintBoundary(
                        child: CustomPaint(
                          painter: LiveLinkPainter(
                            view: c.view,
                            live: widget.liveLink!,
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
        // Overlay widgets (the notes) sit above the pointer handling, as
        // siblings of it, so a touch on one never reaches the canvas gestures.
        if (widget.overlay == null) return surface;
        return Stack(
          fit: StackFit.expand,
          children: [surface, widget.overlay!],
        );
      },
    );
  }
}
