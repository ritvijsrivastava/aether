import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ui/adaptive/window_class.dart';
import '../../ui/theme/theme.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/aether_icon.dart';
import 'canvas_ui_state.dart';

/// Top bar of the canvas screen. Adapts to the window class: a phone shows
/// Back, the title and an overflow menu; larger windows show the wordmark,
/// title, page count and the full action set.
class CanvasTopBar extends ConsumerWidget {
  const CanvasTopBar({
    super.key,
    required this.windowClass,
    required this.title,
    required this.pageCount,
    required this.extractVisible,
    this.canUndo = false,
    this.canRedo = false,
    this.onUndo,
    this.onRedo,
  });

  final WindowClass windowClass;
  final String title;
  final int pageCount;
  final bool extractVisible;
  final bool canUndo, canRedo;
  final VoidCallback? onUndo, onRedo;

  void _copy(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('Nothing to copy yet.')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final text = AetherText(t.ink);
    final compact = windowClass == WindowClass.compact;

    final back = IconButton(
      tooltip: 'Back to library',
      onPressed: () => context.canPop() ? context.pop() : context.go('/'),
      icon: AetherIcon(AetherIcons.back, color: t.ink),
    );
    final titleText = Text(
      title,
      style: text.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final extractToggle = IconButton(
      tooltip: extractVisible ? 'Hide Extract' : 'Show Extract',
      isSelected: extractVisible,
      onPressed: () =>
          ref.read(canvasUiProvider.notifier).setExtractOpen(!extractVisible),
      icon: AetherIcon(
        AetherIcons.list,
        color: extractVisible ? t.indigoText : t.ink,
      ),
    );

    Widget bar;
    if (compact) {
      bar = Row(
        children: [
          back,
          Expanded(child: titleText),
          IconButton(
            tooltip: 'Undo',
            onPressed: canUndo ? onUndo : null,
            icon: AetherIcon(
              AetherIcons.undo,
              color: canUndo ? t.ink : t.inkFaint,
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: AetherIcon(AetherIcons.more, color: t.ink),
            onSelected: (v) {
              if (v == 'copy') _copy(context);
              if (v == 'settings') context.push('/settings');
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'copy', child: Text('Copy as Markdown')),
              PopupMenuItem(value: 'settings', child: Text('Settings')),
            ],
          ),
        ],
      );
    } else {
      // Labelled export on wide bars; icon-only when the label would crowd the title.
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final labelled = MediaQuery.sizeOf(context).width / scale >= 760;
      bar = Row(
        children: [
          back,
          Text('Aether', style: text.wordmark),
          Container(
            width: 2,
            height: 24,
            margin: const EdgeInsets.symmetric(horizontal: AetherTokens.s3),
            color: t.hairline,
          ),
          Expanded(child: titleText),
          if (labelled && pageCount > 0)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: AetherTokens.s2),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: t.indigoWash,
                borderRadius: BorderRadius.circular(AetherTokens.rPill),
              ),
              child: Text(
                pageCount == 1 ? '1 page' : '$pageCount pages',
                style: text.label.copyWith(color: t.indigoText),
              ),
            ),
          IconButton(
            tooltip: 'Undo',
            onPressed: canUndo ? onUndo : null,
            icon: AetherIcon(
              AetherIcons.undo,
              color: canUndo ? t.ink : t.inkFaint,
            ),
          ),
          IconButton(
            tooltip: 'Redo',
            onPressed: canRedo ? onRedo : null,
            icon: AetherIcon(
              AetherIcons.redo,
              color: canRedo ? t.ink : t.inkFaint,
            ),
          ),
          extractToggle,
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
            icon: AetherIcon(AetherIcons.settings, color: t.ink),
          ),
          const SizedBox(width: AetherTokens.s1),
          if (labelled)
            FilledButton(
              onPressed: () => _copy(context),
              child: const Text('Copy as Markdown'),
            )
          else
            IconButton.filled(
              tooltip: 'Copy as Markdown',
              onPressed: () => _copy(context),
              icon: AetherIcon(AetherIcons.doc, color: t.onIndigo),
            ),
        ],
      );
    }

    return Material(
      color: t.desk,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.hairline)),
        ),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                start: AetherTokens.s1,
                end: AetherTokens.s3,
              ),
              child: bar,
            ),
          ),
        ),
      ),
    );
  }
}
