import 'dart:ui';

import '../../../core/geometry/box.dart';
import '../../../core/geometry/polygon.dart';
import '../engine/scene.dart';
import '../ink/ink_layer.dart';
import '../marks/mark_layers.dart';
import '../notes/notes_layer.dart';
import '../notes/notes_overlay.dart' show NotesOverlay;
import 'selection.dart';

/// Finds marks by place, for tapping, lassoing and the context menu. All in
/// world space.
class MarkHitTester {
  const MarkHitTester({
    required this.scene,
    required this.ink,
    required this.highlights,
    required this.notes,
  });

  final Scene scene;
  final InkLayer ink;
  final HighlightLayer highlights;
  final NotesLayer notes;

  /// Fingertip reach on ink, in dp.
  static const double inkReachPx = 10;

  Offset? _origin(String? pageId) {
    if (pageId == null) return Offset.zero;
    return scene.byId(pageId)?.rect.topLeft;
  }

  /// The mark under [world] when the view is at [zoom]: notes on top, then
  /// ink, then highlights (a thin highlight is easy to hit; ink and notes are
  /// drawn over it).
  MarkRef? markAt(Offset world, double zoom) {
    for (final n in notes.all) {
      final b = noteBounds(n.id);
      if (b != null && b.contains(world)) return MarkRef(MarkKind.note, n.id);
    }
    final r = inkReachPx / zoom;
    // Free ink, then each page the point is near.
    for (final s in ink.touching(null, world.dx, world.dy, r).reversed) {
      return MarkRef(MarkKind.ink, s.id);
    }
    for (final card in scene.cards.reversed) {
      final local = world - card.rect.topLeft;
      final b = ink.boundsOf(card.id);
      final nearInk =
          b != null &&
          local.dx >= b.x0 - r &&
          local.dx <= b.x1 + r &&
          local.dy >= b.y0 - r &&
          local.dy <= b.y1 + r;
      if (nearInk) {
        for (final s in ink.touching(card.id, local.dx, local.dy, r).reversed) {
          return MarkRef(MarkKind.ink, s.id);
        }
      }
    }
    for (final card in scene.cards.reversed) {
      if (!card.rect.inflate(inkReachPx / zoom).contains(world)) continue;
      final local = world - card.rect.topLeft;
      final h = highlights.hitTest(card.id, local.dx, local.dy, zoom);
      if (h != null) return MarkRef(MarkKind.highlight, h.id);
    }
    return null;
  }

  /// A mark's box in world space, or null if it is gone or its page is.
  Rect? boundsOf(MarkRef ref) {
    switch (ref.kind) {
      case MarkKind.note:
        return noteBounds(ref.id);
      case MarkKind.ink:
        final s = ink.byId(ref.id);
        if (s == null) return null;
        final o = _origin(s.pageId);
        return o == null ? null : _shift(s.bounds, o);
      case MarkKind.highlight:
        final h = highlights.byId(ref.id);
        if (h == null) return null;
        final o = _origin(h.pageId);
        return o == null ? null : _shift(h.bounds, o);
    }
  }

  Rect? noteBounds(String id) {
    final n = notes.byId(id);
    if (n == null) return null;
    final o = NotesOverlay.worldOrigin(n, scene);
    return o == null ? null : o & Size(n.width, n.height);
  }

  /// The box round all of [refs] that still exist.
  Rect? unionBounds(Iterable<MarkRef> refs) {
    Rect? out;
    for (final r in refs) {
      final b = boundsOf(r);
      if (b != null) out = out == null ? b : out.expandToInclude(b);
    }
    return out;
  }

  /// Points that stand for a mark when deciding whether a loop encloses it.
  List<Offset> _anchors(MarkRef ref) {
    switch (ref.kind) {
      case MarkKind.note:
        final b = noteBounds(ref.id);
        return b == null ? const [] : [b.center];
      case MarkKind.ink:
        final s = ink.byId(ref.id);
        final o = s == null ? null : _origin(s.pageId);
        if (s == null || o == null) return const [];
        // Points along the whole line, so a long straight stroke counts by
        // how much of it is inside, not by its two end samples.
        final pts = <Offset>[];
        final n = s.pointCount;
        for (var i = 0; i < n; i++) {
          final x = s.samples[i * 3] + o.dx, y = s.samples[i * 3 + 1] + o.dy;
          if (i > 0) {
            final px = s.samples[(i - 1) * 3] + o.dx;
            final py = s.samples[(i - 1) * 3 + 1] + o.dy;
            final len = (Offset(x, y) - Offset(px, py)).distance;
            final steps = (len / 8).floor();
            for (var k = 1; k <= steps; k++) {
              pts.add(
                Offset(
                  px + (x - px) * k / (steps + 1),
                  py + (y - py) * k / (steps + 1),
                ),
              );
            }
          }
          pts.add(Offset(x, y));
        }
        if (pts.length <= 200) return pts;
        final step = pts.length ~/ 200;
        return [for (var i = 0; i < pts.length; i += step) pts[i]];
      case MarkKind.highlight:
        final h = highlights.byId(ref.id);
        final o = h == null ? null : _origin(h.pageId);
        if (h == null || o == null) return const [];
        return [
          for (final r in h.rects)
            Offset((r.x0 + r.x1) / 2 + o.dx, (r.y0 + r.y1) / 2 + o.dy),
        ];
    }
  }

  Iterable<MarkRef> get _all => [
    for (final n in notes.all) MarkRef(MarkKind.note, n.id),
    for (final s in ink.all) MarkRef(MarkKind.ink, s.id),
    for (final h in highlights.all) MarkRef(MarkKind.highlight, h.id),
  ];

  /// Marks at least half enclosed by the loop ([xy] pairs, world space).
  List<MarkRef> inLoop(List<double> xy) =>
      _enclosed((o) => pointInPolygon(o.dx, o.dy, xy));

  /// Marks at least half inside the rectangle.
  List<MarkRef> inRect(Rect r) => _enclosed(r.contains);

  List<MarkRef> _enclosed(bool Function(Offset) inside) {
    final out = <MarkRef>[];
    for (final ref in _all) {
      final a = _anchors(ref);
      if (a.isEmpty) continue;
      final n = a.where(inside).length;
      if (n * 2 >= a.length) out.add(ref);
    }
    return out;
  }

  static Rect _shift(Box b, Offset o) =>
      Rect.fromLTRB(b.x0 + o.dx, b.y0 + o.dy, b.x1 + o.dx, b.y1 + o.dy);
}
