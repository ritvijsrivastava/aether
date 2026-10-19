import 'package:flutter/material.dart';

import '../../ui/theme/theme.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/aether_icon.dart';
import '../../ui/widgets/panel_surface.dart';

/// Zoom out, percent, zoom in, Fit. Inert until the canvas engine (M2).
class ZoomPill extends StatelessWidget {
  const ZoomPill({
    super.key,
    this.zoom = 0.8,
    this.onZoomOut,
    this.onZoomIn,
    this.onFit,
  });

  final double zoom;
  final VoidCallback? onZoomOut, onZoomIn, onFit;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = AetherText(t.ink);
    Widget divider() => Container(width: 1, height: 24, color: t.hairline);
    return PanelSurface(
      radius: AetherTokens.rPill,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Zoom out',
            onPressed: onZoomOut ?? () {},
            icon: AetherIcon(AetherIcons.minus, color: t.ink),
          ),
          divider(),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 56),
            child: Center(
              child: Semantics(
                label: 'Zoom ${(zoom * 100).round()} percent',
                child: Text('${(zoom * 100).round()}%', style: text.label),
              ),
            ),
          ),
          divider(),
          IconButton(
            tooltip: 'Zoom in',
            onPressed: onZoomIn ?? () {},
            icon: AetherIcon(AetherIcons.plus, color: t.ink),
          ),
          divider(),
          TextButton(
            onPressed: onFit ?? () {},
            style: TextButton.styleFrom(
              foregroundColor: t.ink,
              minimumSize: const Size(
                AetherTokens.minTarget,
                AetherTokens.minTarget,
              ),
            ),
            child: const Text('Fit'),
          ),
        ],
      ),
    );
  }
}
