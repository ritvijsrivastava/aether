import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A rounded region on the desk: canvas frame, side panel, tool rail.
class PanelSurface extends StatelessWidget {
  const PanelSurface({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = AetherTokens.rPanel,
    this.floating = true,
    this.clip = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Casts the Float shadow (for things the user can lift or that hover over
  /// the canvas). Fixed regions pass false and rely on tone.
  final bool floating;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shape = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: shape,
        boxShadow: floating ? t.float : null,
      ),
      child: clip
          ? ClipRRect(
              borderRadius: shape,
              child: Padding(padding: padding, child: child),
            )
          : Padding(padding: padding, child: child),
    );
  }
}
