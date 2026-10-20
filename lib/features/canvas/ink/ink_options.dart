import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/theme/theme.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/panel_surface.dart';
import '../canvas_ui_state.dart';
import '../colour_strip.dart';

/// The Ink tool's options: the pen's last five colours, any other colour,
/// and the pen size.
class InkOptions extends ConsumerWidget {
  const InkOptions({super.key, this.sliderWidth = 140, this.compact = false});

  /// Width of the size slider; smaller on a phone.
  final double sliderWidth;

  /// Two rows (colours, then size) so it fits a phone's width.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(canvasUiProvider);
    final notifier = ref.read(canvasUiProvider.notifier);
    final t = context.tokens;
    final text = AetherText(t.ink);
    final strip = ColourStrip(
      colours: ui.inkColors,
      prefix: 'Pen',
      onPick: notifier.setInkColor,
    );
    final size = [
      SizedBox(
        width: sliderWidth,
        height: AetherTokens.minTarget,
        child: Slider(
          value: ui.inkWidth,
          min: InkPalette.minWidth,
          max: InkPalette.maxWidth,
          divisions: 14,
          label: ui.inkWidth.toStringAsFixed(1),
          semanticFormatterCallback: (v) => 'Pen size ${v.toStringAsFixed(1)}',
          onChanged: notifier.setInkWidth,
        ),
      ),
      // A dot as wide as the pen, so the size can be seen.
      SizedBox(
        width: 28,
        child: Center(
          child: Container(
            width: ui.inkWidth + 2,
            height: ui.inkWidth + 2,
            decoration: BoxDecoration(
              color: Color(ui.inkColor),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
      Semantics(
        label: 'Pen size ${ui.inkWidth.toStringAsFixed(1)}',
        excludeSemantics: true,
        child: SizedBox(
          width: 28,
          child: Text(
            ui.inkWidth.toStringAsFixed(1),
            style: text.caption.copyWith(color: t.inkMuted),
          ),
        ),
      ),
    ];
    return PanelSurface(
      radius: compact ? AetherTokens.rCard : AetherTokens.rPill,
      padding: const EdgeInsets.symmetric(horizontal: AetherTokens.s2),
      child: compact
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                strip,
                Row(mainAxisSize: MainAxisSize.min, children: size),
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                strip,
                Container(
                  width: 1,
                  height: 28,
                  margin: const EdgeInsets.symmetric(
                    horizontal: AetherTokens.s1,
                  ),
                  color: t.hairline,
                ),
                ...size,
              ],
            ),
    );
  }
}
