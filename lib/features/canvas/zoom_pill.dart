import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui/theme/theme.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/aether_icon.dart';
import '../../ui/widgets/panel_surface.dart';

/// Zoom and fit, folded to the current zoom level. Tap it and it opens
/// sideways into zoom out, zoom in and Fit; it folds again after a few quiet
/// seconds or on a tap of the level.
class ZoomPill extends StatefulWidget {
  const ZoomPill({
    super.key,
    this.zoom = 1,
    this.onZoomOut,
    this.onZoomIn,
    this.onFit,
    this.openFor = const Duration(seconds: 4),
  });

  final double zoom;
  final VoidCallback? onZoomOut, onZoomIn, onFit;

  /// How long it stays open with no touch.
  final Duration openFor;

  @override
  State<ZoomPill> createState() => _ZoomPillState();
}

class _ZoomPillState extends State<ZoomPill> {
  bool _open = false;
  Timer? _fold;

  void _toggle() {
    setState(() => _open = !_open);
    _rearm();
  }

  void _rearm() {
    _fold?.cancel();
    if (_open) {
      _fold = Timer(widget.openFor, () {
        if (mounted) setState(() => _open = false);
      });
    }
  }

  void _act(VoidCallback? f) {
    f?.call();
    _rearm();
  }

  @override
  void dispose() {
    _fold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = AetherText(t.ink);
    final percent = '${(widget.zoom * 100).round()}%';
    Widget divider() => Container(width: 1, height: 20, color: t.hairline);
    const target = Size(48, 48);
    return PanelSurface(
      radius: AetherTokens.rPill,
      child: AnimatedSize(
        duration: AetherTokens.medium,
        curve: Curves.easeOutCubic,
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_open) ...[
              IconButton(
                tooltip: 'Zoom out',
                constraints: BoxConstraints.tight(target),
                onPressed: () => _act(widget.onZoomOut),
                icon: AetherIcon(AetherIcons.minus, color: t.ink),
              ),
              IconButton(
                tooltip: 'Zoom in',
                constraints: BoxConstraints.tight(target),
                onPressed: () => _act(widget.onZoomIn),
                icon: AetherIcon(AetherIcons.plus, color: t.ink),
              ),
              IconButton(
                tooltip: 'Fit to the drawing',
                constraints: BoxConstraints.tight(target),
                onPressed: () => _act(widget.onFit),
                icon: AetherIcon(AetherIcons.fit, color: t.ink),
              ),
              divider(),
            ],
            Semantics(
              button: true,
              expanded: _open,
              label: 'Zoom ${(widget.zoom * 100).round()} percent',
              excludeSemantics: true,
              onTap: _toggle,
              child: InkWell(
                borderRadius: BorderRadius.circular(AetherTokens.rPill),
                onTap: _toggle,
                child: SizedBox(
                  height: target.height,
                  width: 60,
                  child: Center(child: Text(percent, style: text.label)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
