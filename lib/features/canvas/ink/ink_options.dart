import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/theme/theme.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/panel_surface.dart';
import '../canvas_ui_state.dart';

/// The Ink tool's options: four pen colours and the pen size.
class InkOptions extends ConsumerWidget {
  const InkOptions({super.key, this.sliderWidth = 140});

  /// Width of the size slider; smaller on a phone.
  final double sliderWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(canvasUiProvider);
    final notifier = ref.read(canvasUiProvider.notifier);
    final t = context.tokens;
    final text = AetherText(t.ink);
    return PanelSurface(
      radius: AetherTokens.rPill,
      padding: const EdgeInsets.symmetric(horizontal: AetherTokens.s2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < InkPalette.colors.length; i++)
            _ColorButton(
              color: Color(InkPalette.colors[i]),
              name: InkPalette.names[i],
              selected: ui.inkColor == InkPalette.colors[i],
              onTap: () => notifier.setInkColor(InkPalette.colors[i]),
            ),
          Container(
            width: 1,
            height: 28,
            margin: const EdgeInsets.symmetric(horizontal: AetherTokens.s1),
            color: t.hairline,
          ),
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
        ],
      ),
    );
  }
}

class _ColorButton extends StatelessWidget {
  const _ColorButton({
    required this.color,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Pen colour $name',
      excludeSemantics: true,
      onTap: onTap,
      child: Tooltip(
        message: name,
        child: InkResponse(
          radius: 24,
          onTap: onTap,
          child: SizedBox(
            width: AetherTokens.minTarget,
            height: AetherTokens.minTarget,
            child: Center(
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: selected
                      ? Border.all(color: t.ink, width: 2)
                      : Border.all(color: t.hairline),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
