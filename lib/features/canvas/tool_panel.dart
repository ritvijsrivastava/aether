import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/theme/tokens.dart';
import '../../ui/widgets/aether_icon.dart';
import '../../ui/widgets/color_disc.dart';
import '../../ui/widgets/panel_surface.dart';
import 'canvas_ui_state.dart';
import 'erase/erase_options.dart';
import 'ink/ink_options.dart';
import 'tool_palette.dart';

/// The options of the tool in use, as one horizontal panel: colours and size
/// for Ink, colours for Mark, the partial switch and the clear buttons for
/// Erase. Double-tap the tool (or tap the small tab) to fold it away; it
/// stays folded for that tool until brought back.
class ToolPanel extends ConsumerWidget {
  const ToolPanel({super.key, this.compact = false, this.onClear});

  /// A phone: panels stack their rows so they fit the width.
  final bool compact;

  /// The Erase panel's clear buttons.
  final EraseClearActions? onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tool = ref.watch(canvasUiProvider.select((u) => u.tool));
    if (!tool.hasPanel) return const SizedBox.shrink();
    final collapsed = ref.watch(
      canvasUiProvider.select((u) => u.collapsedPanels.contains(tool)),
    );
    if (collapsed) return _Tab(tool: tool);
    return switch (tool) {
      CanvasTool.mark => const MarkOptions(),
      CanvasTool.ink => InkOptions(
        sliderWidth: compact ? 160 : 140,
        compact: compact,
      ),
      CanvasTool.erase => EraseOptions(compact: compact, actions: onClear),
      _ => const SizedBox.shrink(),
    };
  }
}

/// What is left of a folded panel: a small tab with the tool's colour (if it
/// has one) and a chevron. Tapping it opens the panel again.
class _Tab extends ConsumerWidget {
  const _Tab({required this.tool});
  final CanvasTool tool;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = switch (tool) {
      CanvasTool.ink => ref.watch(canvasUiProvider.select((u) => u.inkColor)),
      CanvasTool.mark => ref.watch(canvasUiProvider.select((u) => u.markColor)),
      _ => null,
    };
    final label = '${tool.label} options';
    void open() =>
        ref.read(canvasUiProvider.notifier).setPanelCollapsed(tool, false);
    return Semantics(
      button: true,
      label: 'Show $label',
      excludeSemantics: true,
      onTap: open,
      child: Tooltip(
        message: 'Show $label (double-tap ${tool.label})',
        child: PanelSurface(
          radius: AetherTokens.rPill,
          padding: EdgeInsets.zero,
          child: InkResponse(
            radius: 28,
            onTap: open,
            child: SizedBox(
              width: 72,
              height: AetherTokens.minTarget,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (color != null) ...[
                    ColorDisc(color, size: 20),
                    const SizedBox(width: 2),
                  ],
                  Transform.rotate(
                    angle: -1.5708,
                    child: const AetherIcon(AetherIcons.back, size: 18),
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
