import 'package:flutter/foundation.dart' show kDebugMode, kProfileMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../ui/adaptive/window_class.dart';
import '../../ui/theme/theme.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/aether_icon.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String _query = '';

  /// A new empty board, opened at once.
  Future<void> _newBoard() async {
    final id = await ref.read(libraryActionsProvider).createBoard();
    if (!mounted) return;
    context.push('/doc/$id');
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = AetherText(t.ink);
    final cls = WindowClass.ofContext(context);
    final items = ref.watch(libraryItemsProvider);

    final newBoardButton = FilledButton.icon(
      onPressed: _newBoard,
      icon: AetherIcon(AetherIcons.note, size: 18, color: t.onIndigo),
      label: const Text('New board'),
    );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: AetherTokens.s4,
        title: Text('Aether', style: text.wordmark),
        actions: [
          if (cls == WindowClass.expanded) ...[
            newBoardButton,
            const SizedBox(width: AetherTokens.s2),
          ],
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
            icon: AetherIcon(AetherIcons.settings, color: t.ink),
          ),
          const SizedBox(width: AetherTokens.s1),
        ],
      ),
      floatingActionButton: cls == WindowClass.expanded
          ? null
          : FloatingActionButton.extended(
              onPressed: _newBoard,
              backgroundColor: t.indigo,
              foregroundColor: t.onIndigo,
              elevation: 2,
              shape: const StadiumBorder(side: BorderSide.none),
              focusElevation: 2,
              icon: AetherIcon(AetherIcons.note, size: 20, color: t.onIndigo),
              label: Text(
                'New board',
                style: text.button.copyWith(color: t.onIndigo),
              ),
            ),
      body: Column(
        children: [
          Expanded(
            child: items.when(
              loading: () => const SizedBox.shrink(),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(AetherTokens.s6),
                  child: Text(
                    'Your library could not be opened. Restart Aether; your marks are safe on this device.',
                    style: text.body,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              data: (list) => list.isEmpty
                  ? const _EmptyLibrary()
                  : _DocumentList(
                      items: list,
                      query: _query,
                      onQuery: (q) => setState(() => _query = q),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = AetherText(t.ink);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AetherTokens.s6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: t.canvas,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: AetherIcon(AetherIcons.doc, size: 32, color: t.inkMuted),
              ),
              const SizedBox(height: AetherTokens.s4),
              Text(
                'Nothing on the desk yet',
                style: text.panelTitle,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AetherTokens.s2),
              Text(
                'Import a PDF to read it on an endless surface. Everything you '
                'mark lands in Extract, quoted and ready to export.',
                style: text.body.copyWith(color: t.inkMuted),
                textAlign: TextAlign.center,
              ),
              if (kDebugMode || kProfileMode) ...[
                const SizedBox(height: AetherTokens.s4),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: AetherTokens.s2,
                  children: [
                    for (final n in const [30, 500])
                      TextButton(
                        onPressed: () => context.push('/doc/synthetic-$n'),
                        child: Text('Open $n-page test canvas (debug)'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DocumentList extends ConsumerWidget {
  const _DocumentList({
    required this.items,
    required this.query,
    required this.onQuery,
  });
  final List<LibraryItem> items;
  final String query;
  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final text = AetherText(t.ink);
    final q = query.trim().toLowerCase();
    final shown = q.isEmpty
        ? items
        : [
            for (final i in items)
              if (i.doc.title.toLowerCase().contains(q)) i,
          ];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AetherTokens.s4,
            AetherTokens.s1,
            AetherTokens.s4,
            AetherTokens.s2,
          ),
          child: TextField(
            onChanged: onQuery,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search documents',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: t.canvas,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AetherTokens.rPill),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? Center(
                  child: Text(
                    'No documents match "$query".',
                    style: text.body.copyWith(color: t.inkMuted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AetherTokens.s4,
                    AetherTokens.s1,
                    AetherTokens.s4,
                    96,
                  ),
                  itemCount: shown.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AetherTokens.s2),
                  itemBuilder: (context, i) => _DocumentTile(shown[i]),
                ),
        ),
      ],
    );
  }
}

class _DocumentTile extends ConsumerWidget {
  const _DocumentTile(this.item);
  final LibraryItem item;

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: item.doc.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename document'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Title'),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null ||
        title.trim().isEmpty ||
        title.trim() == item.doc.title) {
      return;
    }
    await ref.read(libraryActionsProvider).rename(item.doc.id, title);
    ref.invalidate(libraryItemsProvider);
    ref.invalidate(documentsProvider);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    // This tile disappears with the document, so the Undo callback must not
    // use its `ref`: hold on to the app-wide container instead.
    final container = ProviderScope.containerOf(context, listen: false);
    final actions = container.read(libraryActionsProvider);
    final messenger = ScaffoldMessenger.of(context);
    void refresh() {
      container.invalidate(libraryItemsProvider);
      container.invalidate(documentsProvider);
    }

    await actions.delete(item.doc.id);
    refresh();
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted "${item.doc.title}".'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              await actions.undo();
              refresh();
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final text = AetherText(t.ink);
    final d = item.doc;
    final added = DateFormat.yMMMd().format(item.added);
    return Material(
      color: t.panel,
      borderRadius: BorderRadius.circular(AetherTokens.rCard),
      child: InkWell(
        borderRadius: BorderRadius.circular(AetherTokens.rCard),
        onTap: () => context.push('/doc/${d.id}'),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 88),
          child: Padding(
            padding: const EdgeInsets.all(AetherTokens.s3),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.title,
                        style: text.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Added $added',
                        style: text.caption.copyWith(color: t.inkMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  icon: AetherIcon(AetherIcons.more, color: t.inkMuted),
                  onSelected: (v) {
                    if (v == 'rename') _rename(context, ref);
                    if (v == 'delete') _delete(context, ref);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
