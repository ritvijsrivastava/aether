import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/theme/theme.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/panel_surface.dart';
import '../canvas_ui_state.dart';

/// The Erase tool's one option: whole strokes (default) or just the part
/// under the eraser.
class EraseOptions extends ConsumerWidget {
  const EraseOptions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partial = ref.watch(canvasUiProvider.select((u) => u.erasePartial));
    final t = context.tokens;
    final text = AetherText(t.ink);
    return PanelSurface(
      radius: AetherTokens.rPill,
      padding: const EdgeInsets.only(
        left: AetherTokens.s4,
        right: AetherTokens.s2,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Erase part of a stroke', style: text.label),
          const SizedBox(width: AetherTokens.s2),
          Semantics(
            label: 'Erase part of a stroke',
            toggled: partial,
            child: Switch(
              value: partial,
              onChanged: (v) =>
                  ref.read(canvasUiProvider.notifier).setErasePartial(v),
            ),
          ),
        ],
      ),
    );
  }
}
