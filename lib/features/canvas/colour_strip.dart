import 'package:flutter/material.dart';

import '../../ui/theme/tokens.dart';
import '../../ui/widgets/colour_picker.dart';
import '../../ui/widgets/color_disc.dart';
import 'palette.dart';

/// A tool's last five colours as discs, then a button for any other colour.
///
/// [prefix] names what the colour is for ("Pen", "Marker") in the labels.
class ColourStrip extends StatelessWidget {
  const ColourStrip({
    super.key,
    required this.colours,
    required this.onPick,
    required this.prefix,
    this.axis = Axis.horizontal,
  });

  final ToolColours colours;
  final ValueChanged<int> onPick;
  final String prefix;

  /// Vertical in the highlight action strip.
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    return Flex(
      direction: axis,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final c in colours.recent)
          ColourSwatch(
            color: c,
            selected: c == colours.current,
            label: 'A $prefix colour',
            onTap: () => onPick(c),
          ),
        AnyColourButton(
          label: 'Other $prefix colour',
          current: colours.current,
          saved: colours.recent,
          onPick: onPick,
        ),
      ],
    );
  }
}

class ColourSwatch extends StatelessWidget {
  const ColourSwatch({
    super.key,
    this.tile = AetherTokens.minTarget,
    required this.color,
    required this.selected,
    required this.label,
    required this.onTap,
  });
  final double tile;
  final int color;
  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Tooltip(
        message: 'Colour',
        child: InkResponse(
          radius: 24,
          onTap: onTap,
          child: SizedBox(
            width: tile,
            height: tile,
            child: Center(child: ColorDisc(color, selected: selected)),
          ),
        ),
      ),
    );
  }
}

class AnyColourButton extends StatelessWidget {
  const AnyColourButton({
    super.key,
    this.tile = AetherTokens.minTarget,
    required this.label,
    required this.current,
    required this.saved,
    required this.onPick,
  });
  final double tile;
  final String label;
  final int current;
  final List<int> saved;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    Future<void> open() async {
      final c = await showColourPicker(
        context,
        initial: InkPalette.resolve(current, Theme.of(context).brightness),
        saved: [
          for (final c in saved)
            InkPalette.resolve(c, Theme.of(context).brightness),
        ],
      );
      if (c != null) onPick(c);
    }

    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: open,
      child: Tooltip(
        message: 'Any colour',
        child: InkResponse(
          radius: 24,
          onTap: open,
          child: SizedBox(
            width: tile,
            height: tile,
            child: Center(
              child: Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    colors: [
                      Color(0xFFFF4D4D),
                      Color(0xFFFFE94A),
                      Color(0xFF3FD97A),
                      Color(0xFF4DB8FF),
                      Color(0xFF9B5DE5),
                      Color(0xFFFF4D4D),
                    ],
                  ),
                ),
                child: const Icon(Icons.add, size: 16, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
