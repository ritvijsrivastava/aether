import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/theme/tokens.dart';
import '../../ui/widgets/panel_surface.dart';
import '../../ui/widgets/tool_button.dart';
import 'canvas_ui_state.dart';

/// Vertical floating tool rail (tablet and desktop).
class ToolRail extends ConsumerWidget {
  const ToolRail({super.key});

  static const double button = 52, gap = 2, pad = AetherTokens.s1;

  /// The rail's outer width.
  static const double width = button + pad * 2;

  /// Where the options panel of [tool] starts, so it hangs level with the
  /// tool's button (the rail sits [AetherTokens.s3] from the top).
  static double panelTop(CanvasTool tool) =>
      AetherTokens.s3 + pad + tool.index * (button + gap);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(canvasUiProvider);
    return PanelSurface(
      padding: const EdgeInsets.all(pad),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final tool in CanvasTool.values) ...[
              ToolButton(
                icon: tool.icon,
                label: tool.label,
                size: button,
                tooltip: '${tool.tip} (${tool.key})',
                selected: ui.tool == tool,
                onPressed: () =>
                    ref.read(canvasUiProvider.notifier).pressTool(tool),
              ),
              const SizedBox(height: gap),
            ],
          ],
        ),
      ),
    );
  }
}

/// Phone bottom toolbar: four primary tools and a "More" tray.
class BottomToolbar extends ConsumerWidget {
  const BottomToolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(canvasUiProvider);
    final t = context.tokens;
    final primary = CanvasTool.values.where((e) => e.isPrimary);
    final moreSelected = !ui.tool.isPrimary;
    return Material(
      color: t.panel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.hairline)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AetherTokens.s1,
              vertical: AetherTokens.s1,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final tool in primary)
                  ToolButton(
                    icon: tool.icon,
                    label: tool.label,
                    tooltip: tool.tip,
                    selected: ui.tool == tool,
                    onPressed: () =>
                        ref.read(canvasUiProvider.notifier).pressTool(tool),
                  ),
                ToolButton(
                  icon: ui.tool.isPrimary
                      ? 'M12 12h.01M19 12h.01M5 12h.01'
                      : ui.tool.icon,
                  label: moreSelected ? ui.tool.label : 'More',
                  tooltip: 'More tools',
                  selected: moreSelected,
                  onPressed: () => showMoreTools(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet with the tools that do not fit on the phone toolbar.
Future<void> showMoreTools(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final ui = ref.watch(canvasUiProvider);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Wrap(
              spacing: AetherTokens.s2,
              runSpacing: AetherTokens.s2,
              children: [
                for (final tool in CanvasTool.values.where((e) => !e.isPrimary))
                  ToolButton(
                    icon: tool.icon,
                    label: tool.label,
                    tooltip: tool.tip,
                    selected: ui.tool == tool,
                    onPressed: () {
                      ref.read(canvasUiProvider.notifier).setTool(tool);
                      Navigator.of(context).pop();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
