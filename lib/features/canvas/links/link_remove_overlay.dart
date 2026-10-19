import 'package:flutter/material.dart';

import '../../../ui/theme/theme.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/aether_icon.dart';
import '../engine/scene.dart';
import '../engine/view_state.dart';
import '../marks/mark_layers.dart';
import '../notes/notes_layer.dart';
import 'links_layer.dart';

/// The "Remove link" control shown at the middle of a selected link.
class LinkRemoveOverlay extends StatelessWidget {
  const LinkRemoveOverlay({
    super.key,
    required this.view,
    required this.scene,
    required this.links,
    required this.notes,
    required this.highlights,
    required this.onRemove,
  });

  final ValueNotifier<ViewState> view;
  final ValueNotifier<Scene> scene;
  final LinksLayer links;
  final NotesLayer notes;
  final HighlightLayer highlights;
  final void Function(String linkId) onRemove;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([view, scene, links, notes, highlights]),
      builder: (context, _) {
        final id = links.selectedId;
        final link = id == null ? null : links.byId(id);
        if (link == null) return const SizedBox.shrink();
        final ends = LinkLayout(
          scene: scene.value,
          notes: notes,
          highlights: highlights,
        ).ends(link);
        if (ends == null) return const SizedBox.shrink();
        final screen = view.value.worldToScreen(ends.middle);
        final t = context.tokens;
        final text = AetherText(t.ink);
        return Stack(
          children: [
            Positioned(
              left: screen.dx - 70,
              top: screen.dy - 24,
              width: 140,
              height: AetherTokens.minTarget,
              child: Material(
                color: t.panel,
                elevation: 4,
                shadowColor: t.shadowColor,
                borderRadius: BorderRadius.circular(AetherTokens.rPill),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AetherTokens.rPill),
                  onTap: () => onRemove(link.id),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AetherIcon(AetherIcons.trash, size: 18, color: t.danger),
                      const SizedBox(width: AetherTokens.s2),
                      Text(
                        'Remove link',
                        style: text.button.copyWith(color: t.danger),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
