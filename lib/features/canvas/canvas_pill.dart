import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../ui/theme/theme.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/aether_icon.dart';
import '../../ui/widgets/panel_surface.dart';

/// The only chrome above the canvas: a small pill with Back, the board's name,
/// Undo, Redo and Settings. It rests faint so the drawing stays in front, and
/// comes up to full strength under a mouse, a focus or a touch.
class CanvasPill extends StatefulWidget {
  const CanvasPill({
    super.key,
    required this.title,
    this.canUndo = false,
    this.canRedo = false,
    this.onUndo,
    this.onRedo,
  });

  final String title;
  final bool canUndo, canRedo;
  final VoidCallback? onUndo, onRedo;

  @override
  State<CanvasPill> createState() => _CanvasPillState();
}

class _CanvasPillState extends State<CanvasPill> {
  bool _hover = false, _focus = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = AetherText(t.ink);
    final active = _hover || _focus;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (f) => setState(() => _focus = f),
        child: Listener(
          onPointerDown: (_) => setState(() => _hover = true),
          child: AnimatedOpacity(
            duration: AetherTokens.medium,
            curve: Curves.easeOutCubic,
            opacity: active ? 1 : 0.6,
            child: PanelSurface(
              radius: AetherTokens.rPill,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Back to library',
                    onPressed: () =>
                        context.canPop() ? context.pop() : context.go('/'),
                    icon: AetherIcon(AetherIcons.back, color: t.ink),
                  ),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(
                        widget.title,
                        style: text.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: AetherTokens.s1),
                  IconButton(
                    tooltip: 'Undo',
                    onPressed: widget.canUndo ? widget.onUndo : null,
                    icon: AetherIcon(
                      AetherIcons.undo,
                      color: widget.canUndo ? t.ink : t.inkFaint,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Redo',
                    onPressed: widget.canRedo ? widget.onRedo : null,
                    icon: AetherIcon(
                      AetherIcons.redo,
                      color: widget.canRedo ? t.ink : t.inkFaint,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Settings',
                    onPressed: () => context.push('/settings'),
                    icon: AetherIcon(AetherIcons.settings, color: t.ink),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
