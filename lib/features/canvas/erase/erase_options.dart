import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/theme/theme.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/aether_icon.dart';
import '../../../ui/widgets/panel_surface.dart';
import '../ink/ink_options.dart' show SizeWavePainter;
import '../canvas_ui_state.dart';
import '../../../app/providers.dart';

/// What the Erase panel's clear row does.
abstract interface class EraseClearActions {
  /// Clears the whole board (the caller confirms first); one undo step.
  void clearAll();
}

/// The Erase tool's options: a thickness wave, a switch for erasing part of
/// a stroke, and a Clear all row in the danger colour.
class EraseOptions extends ConsumerWidget {
  const EraseOptions({super.key, this.actions});

  final EraseClearActions? actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partial = ref.watch(canvasUiProvider.select((u) => u.erasePartial));
    final eraseWidth =
        ref.watch(settingsProvider.select((s) => s.value?.eraseWidth)) ?? 28.0;
    final t = context.tokens;
    final text = AetherText(t.ink);
    final a = actions;
    return PanelSurface(
      radius: AetherTokens.rCard,
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AetherTokens.s3,
                AetherTokens.s1,
                AetherTokens.s2,
                AetherTokens.s1,
              ),
              child: _EraseSizeRow(width: eraseWidth, color: t.ink),
            ),
            Container(height: 1, color: t.hairline),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AetherTokens.s3,
                AetherTokens.s1,
                AetherTokens.s2,
                AetherTokens.s1,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text('Erase part of a stroke', style: text.label),
                  ),
                  const SizedBox(width: AetherTokens.s2),
                  Semantics(
                    label: 'Erase part of a stroke',
                    toggled: partial,
                    child: Switch(
                      value: partial,
                      onChanged: (v) => ref
                          .read(canvasUiProvider.notifier)
                          .setErasePartial(v),
                    ),
                  ),
                ],
              ),
            ),
            if (a != null) ...[
              Container(height: 1, color: t.hairline),
              // The whole row is the button.
              Semantics(
                button: true,
                label: 'Clear all',
                excludeSemantics: true,
                onTap: a.clearAll,
                child: InkWell(
                  onTap: a.clearAll,
                  child: SizedBox(
                    height: AetherTokens.minTarget,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AetherTokens.s3,
                        ),
                        child: Text(
                          'Clear all',
                          style: text.button.copyWith(color: t.danger),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The eraser's thickness: the same wave and −/+ row the pen has, sweeping
/// [EraseOptions]' tip diameter.
class _EraseSizeRow extends ConsumerWidget {
  const _EraseSizeRow({required this.width, required this.color});
  final double width;
  final Color color;

  static const step = 2.0, minWidth = 8.0, maxWidth = 60.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    void set(double w) => ref
        .read(settingsProvider.notifier)
        .setEraseWidth(w.clamp(minWidth, maxWidth));
    return Semantics(
      container: true,
      label: 'Eraser size ${width.toStringAsFixed(0)}',
      value: width.toStringAsFixed(0),
      increasedValue: (width + step).toStringAsFixed(0),
      decreasedValue: (width - step).toStringAsFixed(0),
      onIncrease: () => set(width + step),
      onDecrease: () => set(width - step),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Thinner',
            visualDensity: VisualDensity.compact,
            onPressed: width <= minWidth ? null : () => set(width - step),
            icon: AetherIcon(
              AetherIcons.minus,
              size: 18,
              color: width <= minWidth ? t.inkFaint : t.ink,
            ),
          ),
          Expanded(
            child: ExcludeSemantics(
              child: CustomPaint(
                size: const Size.fromHeight(32),
                painter: SizeWavePainter(width: width, color: color),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Thicker',
            visualDensity: VisualDensity.compact,
            onPressed: width >= maxWidth ? null : () => set(width + step),
            icon: AetherIcon(
              AetherIcons.plus,
              size: 18,
              color: width >= maxWidth ? t.inkFaint : t.ink,
            ),
          ),
        ],
      ),
    );
  }
}
