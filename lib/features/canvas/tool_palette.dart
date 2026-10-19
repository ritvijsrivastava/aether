import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/model/models.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/meaning_disc.dart';
import '../../ui/widgets/panel_surface.dart';
import '../../ui/widgets/tool_button.dart';
import 'canvas_ui_state.dart';

/// One tappable meaning swatch with a 48 dp hit area.
class MeaningButton extends ConsumerWidget {
  const MeaningButton(this.meaning, {super.key});
  final Meaning meaning;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(canvasUiProvider);
    final selected = ui.meaning == meaning && ui.tool == CanvasTool.mark;
    return Semantics(
      button: true,
      selected: selected,
      label: '${meaning.label} highlight',
      excludeSemantics: true,
      onTap: () => ref.read(canvasUiProvider.notifier).setMeaning(meaning),
      child: Tooltip(
        message: meaning.label,
        child: InkResponse(
          radius: 24,
          onTap: () => ref.read(canvasUiProvider.notifier).setMeaning(meaning),
          child: SizedBox(
            width: AetherTokens.minTarget,
            height: AetherTokens.minTarget,
            child: Center(child: MeaningDisc(meaning, selected: selected)),
          ),
        ),
      ),
    );
  }
}

/// Vertical floating tool rail (tablet and desktop).
class ToolRail extends ConsumerWidget {
  const ToolRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(canvasUiProvider);
    final t = context.tokens;
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
                    ref.read(canvasUiProvider.notifier).setTool(tool),
              ),
              const SizedBox(height: AetherTokens.s1),
            ],
            Container(
              height: 1,
              width: 40,
              margin: const EdgeInsets.symmetric(vertical: AetherTokens.s1),
              color: t.hairline,
            ),
            for (final m in Meaning.values) MeaningButton(m),
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
                        ref.read(canvasUiProvider.notifier).setTool(tool),
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

/// Row of the three meanings, shown above the toolbar while Mark is active.
class MeaningStrip extends StatelessWidget {
  const MeaningStrip({super.key});

  @override
  Widget build(BuildContext context) => PanelSurface(
    radius: AetherTokens.rPill,
    padding: const EdgeInsets.symmetric(horizontal: AetherTokens.s2),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [for (final m in Meaning.values) MeaningButton(m)],
    ),
  );
}
