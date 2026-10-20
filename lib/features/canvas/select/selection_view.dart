import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/aether_icon.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../canvas_ui_state.dart';
import '../colour_strip.dart';
import '../engine/view_state.dart';
import '../ink/ink_layer.dart';
import 'ink_hit.dart';
import 'select_tool.dart';
import 'selection.dart';

/// Draws the dashed outline round the selection (DESIGN: 1.5 px indigo, 10 px
/// radius) and the loop or rectangle being drawn.
class SelectionPainter extends CustomPainter {
  SelectionPainter({
    required this.view,
    required this.selection,
    required this.lasso,
    required this.ink,
    required this.tokens,
  }) : super(repaint: Listenable.merge([view, selection, lasso, ink]));

  final ValueListenable<ViewState> view;
  final SelectionState selection;
  final LiveLasso lasso;
  final InkLayer ink;
  final AetherTokens tokens;

  static void dashed(Canvas canvas, Path path, Paint paint, double px) {
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(
          m.extractPath(d, math.min(d + 6 * px, m.length)),
          paint,
        );
        d += 10 * px;
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final v = view.value;
    final px = 1 / v.zoom;
    canvas.save();
    canvas.translate(v.x, v.y);
    canvas.scale(v.zoom);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 1.5 * px
      ..color = tokens.indigo;

    if (!selection.isEmpty) {
      final hit = InkHitTester(ink: ink);
      final b = hit.unionBounds(selection.refs);
      if (b != null) {
        final r = RRect.fromRectAndRadius(
          b.inflate(6 * px),
          Radius.circular(AetherTokens.rSelection * px),
        );
        canvas.drawRRect(
          r,
          Paint()..color = tokens.indigo.withValues(alpha: 0.06),
        );
        dashed(canvas, Path()..addRRect(r), line, px);
      }
    }

    if (lasso.active && lasso.points.isNotEmpty) {
      final path = Path();
      if (lasso.marquee) {
        final rect = lasso.rect;
        if (rect != null) path.addRect(rect);
      } else {
        path.moveTo(lasso.points.first.dx, lasso.points.first.dy);
        for (final p in lasso.points.skip(1)) {
          path.lineTo(p.dx, p.dy);
        }
        path.close();
      }
      canvas.drawPath(
        path,
        Paint()..color = tokens.indigo.withValues(alpha: 0.08),
      );
      dashed(canvas, path, line, px);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(SelectionPainter old) =>
      old.view != view ||
      old.selection != selection ||
      old.lasso != lasso ||
      old.tokens != tokens;
}

/// What the selection's action pill can do.
abstract interface class SelectionActions {
  void recolorInk(int argb);
  void deleteSelection();
}

/// The pill above the selection: how many are selected, Recolor and Delete.
/// (Move is by dragging the selection itself.)
class MarkSelectionOverlay extends StatefulWidget {
  const MarkSelectionOverlay({
    super.key,
    required this.view,
    required this.selection,
    required this.ink,
    required this.actions,
    required this.viewport,
  });

  final ValueNotifier<ViewState> view;
  final SelectionState selection;
  final InkLayer ink;
  final SelectionActions actions;
  final Size Function() viewport;

  @override
  State<MarkSelectionOverlay> createState() => _MarkSelectionOverlayState();
}

class _MarkSelectionOverlayState extends State<MarkSelectionOverlay> {
  bool _recoloring = false;

  @override
  void initState() {
    super.initState();
    widget.selection.addListener(_selectionChanged);
  }

  @override
  void dispose() {
    widget.selection.removeListener(_selectionChanged);
    super.dispose();
  }

  void _selectionChanged() {
    if (_recoloring && widget.selection.isEmpty) {
      setState(() => _recoloring = false);
    }
  }

  static const double _pillH = AetherTokens.minTarget;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.view, widget.selection, widget.ink]),
      builder: (context, _) {
        final sel = widget.selection;
        if (sel.isEmpty) return const SizedBox.shrink();
        final b = InkHitTester(ink: widget.ink).unionBounds(sel.refs);
        if (b == null) return const SizedBox.shrink();
        final v = widget.view.value;
        final tl = v.worldToScreen(b.topLeft);
        final br = v.worldToScreen(b.bottomRight);
        final size = widget.viewport();
        final pill = _pill(context);
        // Above the selection if there is room, else below; kept on screen.

        final ui = ProviderScope.containerOf(context).read(canvasUiProvider);
        // Back, then each strip: its recent colours and the "any colour" button.
        final wanted = _recoloring
            ? AetherTokens.minTarget * (1 + ui.inkColors.recent.length + 1) + 24
            : AetherTokens.minTarget * 2 + 16;
        final width = math.min(wanted, math.max(112.0, size.width - 16));
        var top = tl.dy - _pillH - 14;
        if (top < 8) top = br.dy + 14;
        top = top
            .clamp(8.0, math.max(8.0, size.height - _pillH - 8))
            .toDouble();
        final left = ((tl.dx + br.dx) / 2 - width / 2)
            .clamp(8.0, math.max(8.0, size.width - width - 8))
            .toDouble();
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: width,
              height: _pillH,
              child: pill,
            ),
          ],
        );
      },
    );
  }

  Widget _pill(BuildContext context) {
    final t = context.tokens;
    final sel = widget.selection;
    final hasInk = sel.idsOf(MarkKind.ink).isNotEmpty;
    final canRecolor = hasInk;
    return Material(
      color: t.panel,
      elevation: 4,
      shadowColor: t.shadowColor,
      borderRadius: BorderRadius.circular(AetherTokens.rPill),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: _recoloring
              ? [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => setState(() => _recoloring = false),
                    icon: AetherIcon(AetherIcons.back, color: t.ink),
                  ),
                  Consumer(
                    builder: (context, ref, _) {
                      final ui = ref.watch(canvasUiProvider);
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasInk)
                            ColourStrip(
                              colours: ui.inkColors,
                              prefix: 'Pen',
                              onPick: widget.actions.recolorInk,
                            ),
                        ],
                      );
                    },
                  ),
                ]
              : [
                  if (canRecolor)
                    IconButton(
                      tooltip: 'Colour',
                      onPressed: () => setState(() => _recoloring = true),
                      icon: AetherIcon(AetherIcons.palette, color: t.ink),
                    ),
                  IconButton(
                    tooltip: 'Delete',
                    onPressed: widget.actions.deleteSelection,
                    icon: AetherIcon(AetherIcons.trash, color: t.danger),
                  ),
                ],
        ),
      ),
    );
  }
}

/// A tap-sized helper for the tests: whether a selection could be recolored.
bool canRecolor(SelectionState s) => s.idsOf(MarkKind.ink).isNotEmpty;
