import 'package:flutter/material.dart';

import '../../../ui/theme/theme.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/aether_icon.dart';

/// What the note menu's buttons do.
abstract interface class NoteMenuActions {
  /// Removes every link of the note.
  void unlinkNote(String id);

  /// The note's whole text to the clipboard.
  void copyAll(String id);

  void deleteNote(String id);
}

/// Which note's menu is open, and where the press was (global screen).
class NoteMenuController extends ChangeNotifier {
  String? noteId;
  Offset? anchor;

  bool get isOpen => noteId != null;

  void open(String id, Offset at) {
    if (noteId == id && anchor == at) return;
    noteId = id;
    anchor = at;
    notifyListeners();
  }

  void close() {
    if (noteId == null) return;
    noteId = null;
    anchor = null;
    notifyListeners();
  }
}

/// The horizontal menu of a note, opened by a long press on it: Unlink,
/// Copy all, Delete. It sits above the press point, kept on screen.
class NoteMenuOverlay extends StatelessWidget {
  const NoteMenuOverlay({
    super.key,
    required this.controller,
    required this.actions,
  });

  final NoteMenuController controller;
  final NoteMenuActions actions;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: false,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final id = controller.noteId;
          final at = controller.anchor;
          if (id == null || at == null) return const SizedBox.shrink();
          final t = context.tokens;
          const double pillH = AetherTokens.minTarget + 8;
          const double pillW = 3 * 52 + 16;
          // Above the press, clamped on screen; the press itself is ~a stylus
          // tip, so a small offset is enough.
          var left = at.dx - pillW / 2;
          left = left.clamp(8.0, double.infinity);
          double top = at.dy - pillH - 16;
          top = top < 8 ? at.dy + 16 : top;
          return Stack(
            children: [
              // A tap outside closes it.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: controller.close,
                ),
              ),
              Positioned(
                left: left,
                top: top,
                width: pillW,
                child: Material(
                  color: t.panel,
                  elevation: 4,
                  shadowColor: t.shadowColor,
                  borderRadius: BorderRadius.circular(AetherTokens.rCard),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Item(
                          label: 'Unlink',
                          icon: AetherIcons.link,
                          onTap: () {
                            actions.unlinkNote(id);
                            controller.close();
                          },
                        ),
                        _Item(
                          label: 'Copy all',
                          icon: AetherIcons.copy,
                          onTap: () {
                            actions.copyAll(id);
                            controller.close();
                          },
                        ),
                        _Item(
                          label: 'Delete',
                          icon: AetherIcons.trash,
                          danger: true,
                          onTap: () {
                            actions.deleteNote(id);
                            controller.close();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.label,
    required this.icon,
    required this.onTap,
    this.danger = false,
  });
  final String label;
  final String icon;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = danger ? t.danger : t.ink;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Tooltip(
        message: label,
        child: InkResponse(
          radius: 26,
          onTap: onTap,
          child: SizedBox(
            width: 52,
            height: AetherTokens.minTarget,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AetherIcon(icon, size: 20, color: color),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: kUiFont,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: color,
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
