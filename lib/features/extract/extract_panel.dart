import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/export/extract_items.dart';
import '../../ui/theme/theme.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/aether_icon.dart';
import '../../ui/widgets/meaning_disc.dart';
import '../canvas/canvas_ui_state.dart';
import 'extract_controller.dart';

/// The Extract panel: every mark as a quoted item, in reading order,
/// filterable by meaning. Tap an item to go to it on the canvas.
class ExtractPanel extends ConsumerWidget {
  const ExtractPanel({
    super.key,
    this.source,
    this.scrollController,
    this.header,
  });

  /// The open document's list; null shows the empty panel.
  final ExtractController? source;

  final ScrollController? scrollController;

  /// Optional widget above the title (the sheet's drag handle on phones).
  final Widget? header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(canvasUiProvider);
    final s = source;
    if (s == null) return _Body(items: const [], ui: ui, panel: this);
    return ListenableBuilder(
      listenable: s.changes,
      builder: (context, _) =>
          _Body(items: s.items(ui.filter), ui: ui, panel: this),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.items, required this.ui, required this.panel});

  final List<ExtractItem> items;
  final CanvasUiState ui;
  final ExtractPanel panel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final text = AetherText(t.ink);
    final count = items.length;
    return ColoredBox(
      color: t.panel,
      child: CustomScrollView(
        controller: panel.scrollController,
        slivers: [
          if (panel.header != null) SliverToBoxAdapter(child: panel.header),
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
                        count == 1 ? '1 item' : '$count items',
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
          if (items.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AetherTokens.s4,
                  vertical: AetherTokens.s6,
                ),
                child: Text(
                  _emptyCopy(ui.filter),
                  style: text.body.copyWith(color: t.inkMuted),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AetherTokens.s3,
                0,
                AetherTokens.s3,
                AetherTokens.s6,
              ),
              sliver: SliverList.builder(
                itemCount: items.length,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.only(bottom: AetherTokens.s2),
                  child: ExtractTile(
                    key: ValueKey(items[i].highlight.id),
                    item: items[i],
                    onJump: panel.source == null
                        ? null
                        : () => panel.source!.onJump(items[i].highlight),
                    onDelete: panel.source == null
                        ? null
                        : () => _delete(context, panel.source!, items[i]),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _emptyCopy(ExtractFilter f) => switch (f) {
    ExtractFilter.all =>
      'Highlight or write to start collecting. Everything you mark lands '
          'here, quoted and ready to export.',
    ExtractFilter.notes => 'Notes you write will be listed here.',
    _ => 'Nothing marked as ${f.label} yet.',
  };

  void _delete(BuildContext context, ExtractController s, ExtractItem item) {
    s.onDelete(item.highlight);
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Highlight deleted'),
          action: SnackBarAction(label: 'Undo', onPressed: s.onUndo),
        ),
      );
  }
}

/// One quoted mark: its meaning and page above, the quote below.
class ExtractTile extends StatelessWidget {
  const ExtractTile({
    super.key,
    required this.item,
    this.onJump,
    this.onDelete,
  });

  final ExtractItem item;
  final VoidCallback? onJump, onDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = AetherText(t.ink);
    final where = item.pageIndex < 0 ? '' : 'p. ${item.pageNumber}';
    final quote = item.isRegion ? 'Image region' : item.quote;
    return Semantics(
      container: true,
      button: onJump != null,
      label:
          '${item.meaning.label}${where.isEmpty ? '' : ', page ${item.pageNumber}'}'
          '. $quote',
      onTap: onJump,
      child: Material(
        color: t.desk,
        borderRadius: BorderRadius.circular(AetherTokens.rCard),
        child: InkWell(
          borderRadius: BorderRadius.circular(AetherTokens.rCard),
          hoverColor: t.hoverWash,
          onTap: onJump,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 4, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ExcludeSemantics(
                      child: MeaningDisc(item.meaning, size: 22),
                    ),
                    const SizedBox(width: AetherTokens.s1),
                    Text(item.meaning.label, style: text.label),
                    if (where.isNotEmpty) ...[
                      Text(
                        '  ·  ',
                        style: text.caption.copyWith(color: t.inkMuted),
                      ),
                      Text(
                        where,
                        style: text.caption.copyWith(color: t.inkMuted),
                      ),
                    ],
                    const Spacer(),
                    IconButton(
                      tooltip: 'Delete highlight',
                      onPressed: onDelete,
                      constraints: const BoxConstraints(
                        minWidth: AetherTokens.minTarget,
                        minHeight: AetherTokens.minTarget,
                      ),
                      icon: AetherIcon(
                        AetherIcons.trash,
                        size: 18,
                        color: t.inkMuted,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(
                    quote,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: item.isRegion
                        ? text.body.copyWith(color: t.inkMuted)
                        : TextStyle(
                            fontFamily: kDocFont,
                            fontSize: 15,
                            height: 1.5,
                            color: t.ink,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
