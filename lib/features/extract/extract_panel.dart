import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/theme/theme.dart';
import '../../ui/theme/tokens.dart';
import '../canvas/canvas_ui_state.dart';

/// The Extract panel: every mark as a quoted item, filterable. The list is
/// empty until marks exist (M3); the empty state is the real, final copy.
class ExtractPanel extends ConsumerWidget {
  const ExtractPanel({super.key, this.scrollController, this.header});

  final ScrollController? scrollController;

  /// Optional widget above the title (the sheet's drag handle on phones).
  final Widget? header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final text = AetherText(t.ink);
    final ui = ref.watch(canvasUiProvider);
    const count = 0; // M3 wires real marks.
    return ColoredBox(
      color: t.panel,
      child: CustomScrollView(
        controller: scrollController,
        slivers: [
          if (header != null) SliverToBoxAdapter(child: header),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AetherTokens.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(child: Text('Extract', style: text.panelTitle)),
                      Text(
                        '$count items',
                        style: text.caption.copyWith(color: t.inkMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: AetherTokens.s3),
                  Wrap(
                    spacing: 6,
                    runSpacing: 0,
                    children: [
                      for (final f in ExtractFilter.values)
                        FilterChip(
                          label: Text(
                            f.label,
                            style: text.label.copyWith(
                              color: ui.filter == f ? t.desk : t.ink,
                            ),
                          ),
                          selected: ui.filter == f,
                          onSelected: (_) =>
                              ref.read(canvasUiProvider.notifier).setFilter(f),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AetherTokens.s4,
                vertical: AetherTokens.s6,
              ),
              child: Text(
                'Highlight or write to start collecting. Everything you mark '
                'lands here, quoted and ready to export.',
                style: text.body.copyWith(color: t.inkMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
