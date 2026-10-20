import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/theme/tokens.dart';
import '../../ui/widgets/panel_surface.dart';
import '../../ui/widgets/tool_button.dart';
import 'canvas_ui_state.dart';
import 'colour_strip.dart';

/// Vertical floating tool rail (tablet and desktop).
class ToolRail extends ConsumerWidget {
  const ToolRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(canvasUiProvider);
    return PanelSurface(
      padding: const EdgeInsets.all(AetherTokens.s2),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final tool in CanvasTool.values) ...[
              ToolButton(
                icon: tool.icon,
                label: tool.label,
                tooltip: '${tool.tip} (${tool.key})',
                selected: ui.tool == tool,
                onPressed: () =>
                    ref.read(canvasUiProvider.notifier).pressTool(tool),
              ),
              const SizedBox(height: AetherTokens.s1),
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
              horizontal: AetherTokens.s2,
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

/// The marker's options: a column of its last five colours and any other
/// colour. Shown beside the rail (or above the toolbar) while Mark is active.
class MarkOptions extends ConsumerWidget {
  const MarkOptions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colours = ref.watch(canvasUiProvider.select((u) => u.markColors));
    return PanelSurface(
      radius: AetherTokens.rCard,
      padding: const EdgeInsets.symmetric(
        horizontal: AetherTokens.s1,
        vertical: AetherTokens.s1,
      ),
      child: ColourStrip(
        colours: colours,
        prefix: 'Marker',
        axis: Axis.vertical,
        onPick: ref.read(canvasUiProvider.notifier).setMarkColor,
      ),
    );
  }
}
