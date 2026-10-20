import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/aether_icon.dart';
import '../../../ui/widgets/panel_surface.dart';
import '../canvas_ui_state.dart';
import '../colour_strip.dart';

/// The Ink tool's options, kept small: the pen's saved colours (and a button
/// for any other) in a 3-wide grid, then the pen size as a wave drawn at the
/// current thickness with a minus and a plus beside it.
class InkOptions extends ConsumerWidget {
  const InkOptions({super.key});

  /// How much one tap of minus or plus changes the size, in dp.
  static const double step = 0.5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(canvasUiProvider);
    final notifier = ref.read(canvasUiProvider.notifier);
    final t = context.tokens;
    final colours = ui.inkColors;
    const tile = AetherTokens.minTarget;
    return PanelSurface(
      radius: AetherTokens.rCard,
      padding: const EdgeInsets.all(AetherTokens.s2),
      child: SizedBox(
        width: tile * 3,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                for (final c in colours.recent)
                  ColourSwatch(
                    tile: tile,
                    color: c,
                    selected: c == colours.current,
                    label: 'A Pen colour',
                    onTap: () => notifier.setInkColor(c),
                  ),
                AnyColourButton(
                  tile: tile,
                  label: 'Other Pen colour',
                  current: colours.current,
                  saved: colours.recent,
                  onPick: notifier.setInkColor,
                ),
              ],
            ),
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(vertical: AetherTokens.s1),
              color: t.hairline,
            ),
            _SizeRow(
              width: ui.inkWidth,
              colour: Color(
                InkPalette.resolve(ui.inkColor, Theme.of(context).brightness),
              ),
              onChanged: notifier.setInkWidth,
            ),
          ],
        ),
      ),
    );
  }
}

class _SizeRow extends StatelessWidget {
  const _SizeRow({
    required this.width,
    required this.colour,
    required this.onChanged,
  });
  final double width;
  final Color colour;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      container: true,
      label: 'Pen size ${width.toStringAsFixed(1)}',
      value: width.toStringAsFixed(1),
      increasedValue: (width + InkOptions.step).toStringAsFixed(1),
      decreasedValue: (width - InkOptions.step).toStringAsFixed(1),
      onIncrease: () => onChanged(width + InkOptions.step),
      onDecrease: () => onChanged(width - InkOptions.step),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Thinner',
            visualDensity: VisualDensity.compact,
            onPressed: width <= InkPalette.minWidth
                ? null
                : () => onChanged(width - InkOptions.step),
            icon: AetherIcon(
              AetherIcons.minus,
              size: 18,
              color: width <= InkPalette.minWidth ? t.inkFaint : t.ink,
            ),
          ),
          Expanded(
            child: ExcludeSemantics(
              child: CustomPaint(
                size: const Size.fromHeight(32),
                painter: SizeWavePainter(width: width, color: colour),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Thicker',
            visualDensity: VisualDensity.compact,
            onPressed: width >= InkPalette.maxWidth
                ? null
                : () => onChanged(width + InkOptions.step),
            icon: AetherIcon(
              AetherIcons.plus,
              size: 18,
              color: width >= InkPalette.maxWidth ? t.inkFaint : t.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// A sine wave stroked at the pen's size: what the line will look like.
class SizeWavePainter extends CustomPainter {
  SizeWavePainter({required this.width, required this.color});
  final double width;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    final mid = size.height / 2;
    const amp = 8.0;
    for (var x = 0.0; x <= size.width; x += 1) {
      final y = mid + amp * math.sin(x / size.width * 2 * math.pi);
      x == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = width
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(SizeWavePainter old) =>
      old.width != width || old.color != color;
}
