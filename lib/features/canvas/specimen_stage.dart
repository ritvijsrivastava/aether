import 'package:flutter/material.dart';

import '../../domain/model/models.dart';
import '../../ui/theme/theme.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/dot_grid.dart';
import '../../ui/widgets/meaning_disc.dart';

/// PLACEHOLDER until the canvas engine lands in M2.
///
/// A static specimen that shows the desk, a paper card with one highlight of
/// each meaning, and a sticky note, so the shell can be judged against the
/// real surfaces. The text is a fictional sample; none of this is product
/// content and none of it is interactive.
class SpecimenStage extends StatelessWidget {
  const SpecimenStage({super.key, this.leftInset = 0, this.topInset = 0});

  /// Space reserved for the floating tool rail.
  final double leftInset;
  final double topInset;

  static const double _worldW = 980, _worldH = 1060;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ColoredBox(
      color: t.canvas,
      child: LayoutBuilder(
        builder: (context, box) {
          final availW = (box.maxWidth - leftInset - 24).clamp(
            1.0,
            double.infinity,
          );
          final availH = (box.maxHeight - topInset - 40).clamp(
            1.0,
            double.infinity,
          );
          final scale =
              (availW / _worldW < availH / _worldH
                      ? availW / _worldW
                      : availH / _worldH)
                  .clamp(.2, 1.0);
          final w = _worldW * scale, h = _worldH * scale;
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: DotGridPainter(color: t.gridDot)),
              ),
              Positioned(
                left: leftInset + (availW - w) / 2 + 12,
                top: topInset + 40,
                width: w,
                height: h,
                child: ExcludeSemantics(
                  child: FittedBox(
                    fit: BoxFit.contain,
                    alignment: Alignment.topLeft,
                    child: const SizedBox(
                      width: _worldW,
                      height: _worldH,
                      child: _Specimen(),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Specimen extends StatelessWidget {
  const _Specimen();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink = AetherText(AetherTokens.onMark);
    final page = AetherText(const Color(0xFF2B2723));
    TextSpan mark(Meaning m, String s) => TextSpan(
      text: s,
      style: TextStyle(backgroundColor: meaningColor(m).withValues(alpha: .5)),
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          top: 0,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: t.panel,
              borderRadius: BorderRadius.circular(AetherTokens.rPill),
              boxShadow: t.handle,
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomPaint(
                  size: const Size(12, 16),
                  painter: _GripPainter(t.inkMuted),
                ),
                const SizedBox(width: 8),
                Text('Paper · p. 1', style: AetherText(t.ink).label),
              ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: 46,
          width: 720,
          child: Container(
            padding: const EdgeInsets.all(64),
            decoration: BoxDecoration(
              color: t.paper,
              borderRadius: BorderRadius.circular(AetherTokens.rPaper),
              boxShadow: t.paperShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Preprint · Under review',
                  style: AetherText(const Color(0xFF3D3DBD)).label,
                ),
                const SizedBox(height: 14),
                Text(
                  'Selective Recall: Sparse Attention Under Distribution Shift',
                  style: page.panelTitle.copyWith(fontSize: 34, height: 1.12),
                ),
                const SizedBox(height: 12),
                Text(
                  'A. Moreau, K. Tanaka, R. Okafor',
                  style: AetherText(const Color(0xFF605D5D)).body,
                ),
                const SizedBox(height: 28),
                Text('Abstract', style: page.label),
                const SizedBox(height: 6),
                Text.rich(
                  TextSpan(
                    style: page.documentBody,
                    children: [
                      const TextSpan(
                        text: 'We study how sparse attention mechanisms degrade when test data departs from the training distribution. Our central claim is that ',
                      ),
                      mark(
                        Meaning.claim,
                        'sparsity patterns learned on in-distribution data fail to transfer',
                      ),
                      const TextSpan(text: ', and that a lightweight '),
                      mark(Meaning.method, 're-routing step'),
                      const TextSpan(
                        text: ' recovers most of the lost accuracy. ',
                      ),
                      mark(
                        Meaning.question,
                        'Whether the estimate stays stable at 128k tokens',
                      ),
                      const TextSpan(text: ' remains open.'),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text('1 Introduction', style: page.panelTitle),
                const SizedBox(height: 6),
                Text(
                  'Attention layers dominate the cost of long-context models. '
                  'Sparse variants reduce this cost by letting each token attend '
                  'to a small subset of positions.',
                  style: page.documentBody,
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 760,
          top: 560,
          width: Note.defaultWidth,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AetherTokens.notePaper,
              borderRadius: BorderRadius.circular(AetherTokens.rCard),
              boxShadow: t.sticky,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Note',
                  style: ink.label.copyWith(color: const Color(0xFF605D5D)),
                ),
                const SizedBox(height: 4),
                Text(
                  'Compare against the fixed-rule baseline in the appendix.',
                  style: ink.body.copyWith(fontSize: 15, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GripPainter extends CustomPainter {
  _GripPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    for (var r = 0; r < 3; r++) {
      for (var c = 0; c < 2; c++) {
        canvas.drawCircle(Offset(2.5 + c * 7, 2.5 + r * 5.5), 1.4, p);
      }
    }
  }

  @override
  bool shouldRepaint(_GripPainter o) => o.color != color;
}
