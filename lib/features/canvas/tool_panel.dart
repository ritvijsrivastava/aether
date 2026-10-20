import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'canvas_ui_state.dart';
import 'erase/erase_options.dart';
import 'ink/ink_options.dart';

/// The options of the tool in use. Pressing the tool's button again hides
/// them completely; nothing is left behind (no tab, no chevron).
class ToolPanel extends ConsumerWidget {
  const ToolPanel({super.key, this.onClear});

  /// The Erase panel's clear row.
  final EraseClearActions? onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tool = ref.watch(canvasUiProvider.select((u) => u.tool));
    final hidden = ref.watch(
      canvasUiProvider.select((u) => u.collapsedPanels.contains(tool)),
    );
    if (!tool.hasPanel || hidden) return const SizedBox.shrink();
    return switch (tool) {
      CanvasTool.ink => const InkOptions(),
      CanvasTool.erase => EraseOptions(actions: onClear),
      _ => const SizedBox.shrink(),
    };
  }
}
