import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ui/adaptive/window_class.dart';
import '../../ui/theme/theme.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/aether_icon.dart';

/// Top bar of the canvas screen. Adapts to the window class: a phone shows
/// Back, the title and an overflow menu; larger windows show the wordmark,
/// title, page count and the full action set.
class CanvasTopBar extends ConsumerWidget {
  const CanvasTopBar({
    super.key,
    required this.windowClass,
    required this.title,
    this.canUndo = false,
    this.canRedo = false,
    this.onUndo,
    this.onRedo,
  });

  final WindowClass windowClass;
  final String title;
  final bool canUndo, canRedo;
  final VoidCallback? onUndo, onRedo;

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
          IconButton(
            tooltip: 'Redo',
            onPressed: canRedo ? onRedo : null,
            icon: AetherIcon(
              AetherIcons.redo,
              color: canRedo ? t.ink : t.inkFaint,
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
            icon: AetherIcon(AetherIcons.settings, color: t.ink),
          ),
        ],
      );
    } else {
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
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
            icon: AetherIcon(AetherIcons.settings, color: t.ink),
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
