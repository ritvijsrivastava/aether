import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/theme/theme.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/panel_surface.dart';
import '../canvas_ui_state.dart';

/// What the Erase panel's clear row does.
abstract interface class EraseClearActions {
  /// Clears the whole board (the caller confirms first); one undo step.
  void clearAll();
}

/// The Erase tool's options, kept small: a switch for erasing part of a
/// stroke, and a Clear all row in the danger colour.
class EraseOptions extends ConsumerWidget {
  const EraseOptions({super.key, this.actions});

  final EraseClearActions? actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partial = ref.watch(canvasUiProvider.select((u) => u.erasePartial));
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
