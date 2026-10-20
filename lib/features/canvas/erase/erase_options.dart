import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/theme/theme.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/panel_surface.dart';
import '../canvas_ui_state.dart';

/// What the Erase panel's "clear" buttons do.
abstract interface class EraseClearActions {
  /// All ink on the page in view.
  void clearPageInk();

  /// All ink on every page and off them.
  void clearAllInk();

  /// Everything: ink, highlights, notes and links. The caller confirms first.
  void clearBoard();
}

/// The Erase tool's options as a column: the partial-erase switch, then the
/// clear buttons under it.
class EraseOptions extends ConsumerWidget {
  const EraseOptions({super.key, this.compact = false, this.actions});

  /// True on a phone (the column floats above the bottom bar).
  final bool compact;
  final EraseClearActions? actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partial = ref.watch(canvasUiProvider.select((u) => u.erasePartial));
    final t = context.tokens;
    final text = AetherText(t.ink);
    final a = actions;
    return PanelSurface(
      radius: AetherTokens.rCard,
      padding: const EdgeInsets.symmetric(
        horizontal: AetherTokens.s2,
        vertical: AetherTokens.s1,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                  onChanged: (v) =>
                      ref.read(canvasUiProvider.notifier).setErasePartial(v),
                ),
              ),
            ],
          ),
          if (a != null) ...[
            Container(height: 1, color: t.hairline),
            _Clear('Clear page ink', a.clearPageInk, t.ink),
            _Clear('Clear all ink', a.clearAllInk, t.ink),
            _Clear('Clear board', a.clearBoard, t.danger),
          ],
        ],
      ),
    );
  }
}

class _Clear extends StatelessWidget {
  const _Clear(this.label, this.onTap, this.color);
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = AetherText(color);
    return TextButton(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, AetherTokens.minTarget),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: AetherTokens.s2),
      ),
      onPressed: onTap,
      child: Text(label, style: text.button.copyWith(color: color)),
    );
  }
}
