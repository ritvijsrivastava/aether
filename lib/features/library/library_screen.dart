import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../domain/model/models.dart';
import '../../ui/adaptive/window_class.dart';
import '../../ui/theme/theme.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/aether_icon.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  static void importPdf(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(content: Text('PDF import is not built yet.')),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final text = AetherText(t.ink);
    final cls = WindowClass.ofContext(context);
    final docs = ref.watch(documentsProvider);

    final importButton = FilledButton.icon(
      onPressed: () => importPdf(context),
      icon: AetherIcon(AetherIcons.upload, size: 18, color: t.onIndigo),
      label: const Text('Import PDF'),
    );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: AetherTokens.s4,
        title: Text('Aether', style: text.wordmark),
        actions: [
          if (cls == WindowClass.expanded) ...[
            importButton,
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
              onPressed: () => importPdf(context),
              backgroundColor: t.indigo,
              foregroundColor: t.onIndigo,
              elevation: 2,
              shape: const StadiumBorder(side: BorderSide.none),
              focusElevation: 2,
              icon: AetherIcon(AetherIcons.upload, size: 20, color: t.onIndigo),
              label: Text(
                'Import PDF',
                style: text.button.copyWith(color: t.onIndigo),
              ),
            ),
      body: docs.when(
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
        data: (list) =>
            list.isEmpty ? const _EmptyLibrary() : _DocumentList(list),
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
              if (kDebugMode) ...[
                const SizedBox(height: AetherTokens.s4),
                TextButton(
                  onPressed: () => context.push('/doc/specimen'),
                  child: const Text('Open the design specimen (debug)'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DocumentList extends StatelessWidget {
  const _DocumentList(this.docs);
  final List<Document> docs;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = AetherText(t.ink);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AetherTokens.s4,
        AetherTokens.s2,
        AetherTokens.s4,
        96,
      ),
      itemCount: docs.length,
      separatorBuilder: (_, _) => const SizedBox(height: AetherTokens.s2),
      itemBuilder: (context, i) {
        final d = docs[i];
        return Material(
          color: t.panel,
          borderRadius: BorderRadius.circular(AetherTokens.rCard),
          child: InkWell(
            borderRadius: BorderRadius.circular(AetherTokens.rCard),
            onTap: () => context.push('/doc/${d.id}'),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AetherTokens.s4,
                  vertical: AetherTokens.s3,
                ),
                child: Row(
                  children: [
                    AetherIcon(AetherIcons.doc, color: t.inkMuted),
                    const SizedBox(width: AetherTokens.s3),
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
                          Text(
                            d.pageCount == 1
                                ? '1 page'
                                : '${d.pageCount} pages',
                            style: text.caption.copyWith(color: t.inkMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
