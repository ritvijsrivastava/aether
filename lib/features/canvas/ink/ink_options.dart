import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/aether_icon.dart';
import '../../../ui/widgets/color_disc.dart';
import '../../../ui/widgets/colour_picker.dart';
import '../../../ui/widgets/panel_surface.dart';
import '../canvas_ui_state.dart';

/// The Ink tool's options, all in one card: the colour picker (square, hue,
/// red/green/blue), the saved colours with a plus to keep the current one, and
/// the pen size as a wave with a minus and a plus beside it.
class InkOptions extends ConsumerWidget {
  const InkOptions({super.key});

  /// How much one tap of minus or plus changes the size, in dp.
  static const double step = 0.5;

  static const double width = 248;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(canvasUiProvider);
    final notifier = ref.read(canvasUiProvider.notifier);
    final t = context.tokens;
    final brightness = Theme.of(context).brightness;
    final colours = ui.inkColors;
    final shown = InkPalette.resolve(colours.current, brightness);
    return PanelSurface(
      radius: AetherTokens.rCard,
      padding: const EdgeInsets.all(AetherTokens.s3),
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColourPickerBody(argb: shown, onChanged: notifier.setInkLive),
            const SizedBox(height: AetherTokens.s2),
            Wrap(
              children: [
                for (final c in colours.recent)
                  _SavedSwatch(
                    color: c,
                    selected: c == colours.current,
                    onTap: () => notifier.pickSavedInk(c),
                  ),
                _SaveTile(
                  enabled: colours.current != InkPalette.auto,
                  onTap: notifier.saveInkColour,
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
              colour: Color(shown),
              onChanged: notifier.setInkWidth,
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedSwatch extends StatelessWidget {
  const _SavedSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final int color;
  final bool selected;
  final VoidCallback onTap;

  /// Six to a row in the card.
  static const double tile = 40;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'A saved Pen colour',
      excludeSemantics: true,
      onTap: onTap,
      child: Tooltip(
        message: 'Colour',
        child: InkResponse(
          radius: 22,
          onTap: onTap,
          child: SizedBox(
            width: tile,
            height: tile,
            child: Center(
              child: ColorDisc(color, size: 22, selected: selected),
            ),
          ),
        ),
      ),
    );
  }
}

/// The plus at the end of the saved colours: keeps the current colour.
class _SaveTile extends StatelessWidget {
  const _SaveTile({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      container: true,
      label: 'Save this colour',
      button: enabled,
      onTap: enabled ? onTap : null,
      excludeSemantics: true,
      child: IconButton(
        tooltip: 'Save this colour',
        constraints: BoxConstraints.tight(const Size.square(_SavedSwatch.tile)),
        padding: EdgeInsets.zero,
        onPressed: enabled ? onTap : null,
        icon: AetherIcon(
          AetherIcons.plus,
          size: 20,
          color: enabled ? t.ink : t.inkFaint,
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
    // A very thick tip cannot fit the row, so the wave flattens as it
    // saturates instead of being clipped flat.
    final stroke = math.min(width, 26.0);
    final amp = math.max(1.5, 8.0 - (stroke - 8.0) * 0.22);
    final path = Path();
    final mid = size.height / 2;
    for (var x = 0.0; x <= size.width; x += 1) {
      final y = mid + amp * math.sin(x / size.width * 2 * math.pi);
      x == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(SizeWavePainter old) =>
      old.width != width || old.color != color;
}
