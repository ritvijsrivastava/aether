import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ui/theme/theme.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/aether_icon.dart';

/// One choice in the radial menu: an icon, a label and what it does.
class RadialItem {
  const RadialItem({
    required this.icon,
    required this.label,
    required this.onPick,
  });
  final String icon;
  final String label;
  final VoidCallback onPick;
}

/// The state of the radial menu: open at an anchor, with the item the pointer
/// is over (a swipe towards it), or closed. The canvas routes the moves and
/// release of the press that opened it here, because that press belongs to
/// the canvas's listener.
class RadialMenuController extends ChangeNotifier {
  Offset? _anchor;
  List<RadialItem> items = const [];
  int? hovered;

  bool get isOpen => _anchor != null;
  Offset? get anchor => _anchor;

  /// Geometry shared with the overlay.
  static const double radius = 96;
  static const double disc = 56;

  /// Opens the menu at [at] (global screen) with [items].
  void open(Offset at, List<RadialItem> items) {
    _anchor = at;
    this.items = items;
    hovered = null;
    notifyListeners();
  }

  void close() {
    if (_anchor == null) return;
    _anchor = null;
    hovered = null;
    notifyListeners();
  }

  /// The pointer moved to [at] while the press is held: point at an item.
  void pointTo(Offset at, Size viewport) {
    final a = _anchor;
    if (a == null) return;
    final centre = _fit(a, viewport);
    final d = (at - centre).distance;
    int? next;
    if (d >= disc / 2 && d <= radius + disc) {
      var angle = (at - centre).direction;
      if (angle < 0) angle += 2 * math.pi;
      final slice = 2 * math.pi / items.length;
      next = ((angle - math.pi / 2 + slice / 2) % (2 * math.pi)) ~/ slice;
      if (next >= items.length) next = null;
    }
    if (hovered != next) {
      hovered = next;
      notifyListeners();
    }
  }

  /// The press was released: the hovered item's action runs, or the menu
  /// closes with nothing.
  void release(Size viewport) {
    final pick = hovered;
    final item = pick != null && pick < items.length ? items[pick] : null;
    close();
    item?.onPick();
  }

  /// The anchor moved inboard so the ring fits the screen.
  Offset centre(Size viewport) => _fit(_anchor ?? Offset.zero, viewport);

  static Offset _fit(Offset at, Size viewport) => Offset(
    at.dx.clamp(
      radius + disc / 2,
      math.max(radius + disc / 2, viewport.width - radius - disc / 2),
    ),
    at.dy.clamp(
      radius + disc / 2,
      math.max(radius + disc / 2, viewport.height - radius - disc / 2),
    ),
  );
}

/// Draws the open radial menu as real widgets. It never takes pointers: the
/// press that opened it is still down on the canvas, which routes its moves
/// here.
class RadialMenuOverlay extends StatelessWidget {
  const RadialMenuOverlay({super.key, required this.controller});

  final RadialMenuController controller;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final a = controller.anchor;
          if (a == null) return const SizedBox.shrink();
          return LayoutBuilder(
            builder: (context, box) {
              final centre = controller.centre(box.biggest);
              const r = RadialMenuController.radius;
              const d = RadialMenuController.disc;
              return Stack(
                children: [
                  Positioned(
                    left: centre.dx - 10,
                    top: centre.dy - 10,
                    width: 20,
                    height: 20,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: context.tokens.panel,
                        border: Border.all(color: context.tokens.hairline),
                      ),
                    ),
                  ),
                  for (var i = 0; i < controller.items.length; i++)
                    _Disc(
                      centre:
                          centre +
                          Offset.fromDirection(
                            -math.pi / 2 +
                                2 * math.pi * i / controller.items.length,
                            r,
                          ),
                      item: controller.items[i],
                      on: controller.hovered == i,
                      size: d,
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _Disc extends StatelessWidget {
  const _Disc({
    required this.centre,
    required this.item,
    required this.on,
    required this.size,
  });

  final Offset centre;
  final RadialItem item;
  final bool on;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Positioned(
      left: centre.dx - size / 2,
      top: centre.dy - size / 2,
      width: size,
      height: size,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? t.indigo : t.panel,
              border: Border.all(color: on ? t.indigo : t.hairline),
              boxShadow: t.sticky,
            ),
            child: IconTheme(
              data: IconThemeData(color: on ? t.onIndigo : t.ink, size: 22),
              child: Center(child: AetherIcon(item.icon)),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.label,
            style: TextStyle(
              fontFamily: kUiFont,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: on ? t.indigoText : t.ink,
            ),
          ),
        ],
      ),
    );
  }
}
