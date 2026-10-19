import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../theme/tokens.dart';
import 'aether_icon.dart';

/// A canvas tool: icon over label in a 56 dp rounded square. Filled indigo
/// when active.
class ToolButton extends StatelessWidget {
  const ToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.tooltip,
    this.size = 56,
    this.showLabel = true,
  });

  final String icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final String? tooltip;
  final double size;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fg = selected ? t.onIndigo : t.ink;
    final text = AetherText(fg);
    return Semantics(
      button: true,
      selected: selected,
      label: tooltip ?? label,
      excludeSemantics: true,
      onTap: onPressed,
      child: Tooltip(
        message: tooltip ?? label,
        child: Material(
          color: selected ? t.indigo : Colors.transparent,
          borderRadius: BorderRadius.circular(AetherTokens.rTool),
          child: InkWell(
            borderRadius: BorderRadius.circular(AetherTokens.rTool),
            onTap: onPressed,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: size, minHeight: size),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                // Labels under icons stay readable but stop growing at 1.3x:
                // the tooltip and semantics label carry the full name, and an
                // unbounded label would make the rail wider than the canvas.
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AetherIcon(icon, color: fg),
                      if (showLabel) ...[
                        const SizedBox(height: 3),
                        Text(label, style: text.label, maxLines: 1),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
