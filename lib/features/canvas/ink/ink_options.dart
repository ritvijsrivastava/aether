import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/theme/theme.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/panel_surface.dart';
import '../canvas_ui_state.dart';
import '../colour_strip.dart';

/// The Ink tool's options as a column hanging from its rail button: the pen's
/// last five colours (and any other colour), then the pen size below.
class InkOptions extends ConsumerWidget {
  const InkOptions({super.key, this.sliderWidth = 140, this.compact = false});

  /// Width of the size slider.
  final double sliderWidth;

  /// True on a phone: the column floats above the bottom bar, so it is not
  /// anchored to a rail (no effect on content).
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(canvasUiProvider);
    final notifier = ref.read(canvasUiProvider.notifier);
    final t = context.tokens;
    final text = AetherText(t.ink);
    return PanelSurface(
      radius: AetherTokens.rCard,
      padding: const EdgeInsets.symmetric(
        horizontal: AetherTokens.s1,
        vertical: AetherTokens.s1,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ColourStrip(
            colours: ui.inkColors,
            prefix: 'Pen',
            axis: Axis.vertical,
            onPick: notifier.setInkColor,
          ),
          Container(height: 1, width: 40, color: t.hairline),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: sliderWidth,
                height: AetherTokens.minTarget,
                child: Slider(
                  value: ui.inkWidth,
                  min: InkPalette.minWidth,
                  max: InkPalette.maxWidth,
                  divisions: 14,
                  label: ui.inkWidth.toStringAsFixed(1),
                  semanticFormatterCallback: (v) =>
                      'Pen size ${v.toStringAsFixed(1)}',
                  onChanged: notifier.setInkWidth,
                ),
              ),
              // A dot as wide as the pen, so the size can be seen.
              SizedBox(
                width: 32,
                child: Center(
                  child: Container(
                    width: (ui.inkWidth + 2).clamp(4, 24),
                    height: (ui.inkWidth + 2).clamp(4, 24),
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
                  width: 30,
                  child: Text(
                    ui.inkWidth.toStringAsFixed(1),
                    style: text.caption.copyWith(color: t.inkMuted),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
