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

/// The Erase tool's options: whole strokes (default) or just the part under
/// the eraser, and the buttons that clear ink in one go.
class EraseOptions extends ConsumerWidget {
  const EraseOptions({super.key, this.compact = false, this.actions});

  /// Two rows, so it fits a phone's width.
  final bool compact;
  final EraseClearActions? actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partial = ref.watch(canvasUiProvider.select((u) => u.erasePartial));
    final t = context.tokens;
    final text = AetherText(t.ink);
    final toggle = Row(
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
    );
    final a = actions;
    final clear = a == null
        ? const <Widget>[]
        : [
            _Clear('Clear page ink', a.clearPageInk, t.ink),
            _Clear('Clear all ink', a.clearAllInk, t.ink),
            _Clear('Clear board', a.clearBoard, t.danger),
          ];
    return PanelSurface(
      radius: compact ? AetherTokens.rCard : AetherTokens.rPill,
      padding: const EdgeInsets.only(
        left: AetherTokens.s4,
        right: AetherTokens.s2,
      ),
      child: compact
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                toggle,
                if (clear.isNotEmpty)
                  Row(mainAxisSize: MainAxisSize.min, children: clear),
              ],
            )
          : Row(mainAxisSize: MainAxisSize.min, children: [toggle, ...clear]),
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
        padding: const EdgeInsets.symmetric(horizontal: AetherTokens.s3),
      ),
      onPressed: onTap,
      child: Text(label, style: text.button.copyWith(color: color)),
    );
  }
}
