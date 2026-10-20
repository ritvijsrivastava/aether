import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/model/models.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/aether_icon.dart';
import '../../../ui/widgets/color_disc.dart';
import '../canvas_ui_state.dart';
import '../colour_strip.dart';
import '../engine/scene.dart';
import '../engine/view_state.dart';
import 'mark_layers.dart';

/// The highlight the action strip is about, or none.
class HighlightFocus extends ChangeNotifier {
  String? _id;
  String? get id => _id;

  void show(String id) {
    if (_id == id) return;
    _id = id;
    notifyListeners();
  }

  void clear() {
    if (_id == null) return;
    _id = null;
    notifyListeners();
  }
}

/// What the strip's buttons do.
abstract interface class HighlightActions {
  void addNote(Highlight h);
  void recolor(Highlight h, int color);
  void copyQuote(Highlight h);
  void delete(Highlight h);
}

/// A vertical strip of actions beside a highlight: Add note, Change colour,
/// Copy, Delete. It appears right after marking (and when a highlight is
/// tapped), so the pen, a finger and the mouse all reach the same actions
/// without a long press.
class HighlightActionStrip extends StatefulWidget {
  const HighlightActionStrip({
    super.key,
    required this.view,
    required this.scene,
    required this.highlights,
    required this.focus,
    required this.actions,
    required this.viewport,
  });

  final ValueNotifier<ViewState> view;
  final ValueNotifier<Scene> scene;
  final HighlightLayer highlights;
  final HighlightFocus focus;
  final HighlightActions actions;
  final Size Function() viewport;

  static const double width = AetherTokens.minTarget + 8;

  @override
  State<HighlightActionStrip> createState() => _HighlightActionStripState();
}

class _HighlightActionStripState extends State<HighlightActionStrip> {
  bool _colours = false;
  String? _shownFor;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.view,
        widget.scene,
        widget.highlights,
        widget.focus,
      ]),
      builder: (context, _) {
        final id = widget.focus.id;
        final h = id == null ? null : widget.highlights.byId(id);
        if (_shownFor != id) {
          _shownFor = id;
          _colours = false;
        }
        if (h == null) return const SizedBox.shrink();
        final card = widget.scene.value.byId(h.pageId ?? '');
        if (card == null) return const SizedBox.shrink();
        final v = widget.view.value;
        final o = card.rect.topLeft;
        final b = h.bounds;
        final tl = v.worldToScreen(Offset(o.dx + b.x0, o.dy + b.y0));
        final br = v.worldToScreen(Offset(o.dx + b.x1, o.dy + b.y1));
        final size = widget.viewport();
        final buttons = _colours ? 1 + 6 : 4;
        final height = buttons * AetherTokens.minTarget + 8;
        const w = HighlightActionStrip.width;
        // Right of the highlight if there is room, else left of it.
        var left = br.dx + 10;
        if (left + w > size.width - 8) left = tl.dx - 10 - w;
        left = left.clamp(8.0, math.max(8.0, size.width - w - 8)).toDouble();
        var top = (tl.dy + br.dy) / 2 - height / 2;
        top = top
            .clamp(8.0, math.max(8.0, size.height - height - 8))
            .toDouble();
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: w,
              child: _strip(context, h),
            ),
          ],
        );
      },
    );
  }

  Widget _strip(BuildContext context, Highlight h) {
    final t = context.tokens;
    return Semantics(
      container: true,
      label: 'Highlight actions',
      child: Material(
        color: t.panel,
        elevation: 4,
        shadowColor: t.shadowColor,
        borderRadius: BorderRadius.circular(AetherTokens.rCard),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: _colours ? _colourColumn(h) : _actionColumn(context, h),
        ),
      ),
    );
  }

  Widget _colourColumn(Highlight h) {
    return Consumer(
      builder: (context, ref, _) {
        final colours = ref.watch(canvasUiProvider.select((u) => u.markColors));
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Action(
              label: 'Back',
              onTap: () => setState(() => _colours = false),
              child: AetherIcon(AetherIcons.back, color: context.tokens.ink),
            ),
            ColourStrip(
              colours: ToolColours(h.color, colours.recent),
              prefix: 'Highlight',
              axis: Axis.vertical,
              onPick: (c) {
                widget.actions.recolor(h, c);
                setState(() => _colours = false);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _actionColumn(BuildContext context, Highlight h) {
    final t = context.tokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Action(
          label: 'Add note',
          onTap: () => widget.actions.addNote(h),
          child: AetherIcon(AetherIcons.note, color: t.ink),
        ),
        _Action(
          label: 'Change colour',
          onTap: () => setState(() => _colours = true),
          child: ColorDisc(h.color, size: 22),
        ),
        _Action(
          label: 'Copy quote',
          onTap: () => widget.actions.copyQuote(h),
          child: AetherIcon(AetherIcons.copy, color: t.ink),
        ),
        _Action(
          label: 'Delete highlight',
          onTap: () => widget.actions.delete(h),
          child: AetherIcon(AetherIcons.trash, color: t.danger),
        ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.onTap,
    required this.child,
  });
  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Tooltip(
        message: label,
        child: InkResponse(
          radius: 24,
          onTap: onTap,
          child: SizedBox(
            width: AetherTokens.minTarget,
            height: AetherTokens.minTarget,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
