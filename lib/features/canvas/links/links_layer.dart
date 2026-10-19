import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show CustomPainter;

import '../../../core/geometry/box.dart';
import '../../../domain/marks/link_geometry.dart';
import '../../../domain/model/models.dart';
import '../../../ui/theme/tokens.dart';
import '../engine/scene.dart';
import '../engine/view_state.dart';
import '../marks/mark_layers.dart';
import '../notes/notes_layer.dart';
import '../notes/notes_overlay.dart' show NotesOverlay;

/// The links of the open document: each joins a note to a highlight.
class LinksLayer extends ChangeNotifier {
  final Map<String, Link> _byId = {};

  /// The link whose delete control is showing.
  String? selectedId;

  Iterable<Link> get all => _byId.values;
  int get count => _byId.length;
  Link? byId(String id) => _byId[id];

  List<Link> forNote(String noteId) => [
    for (final l in _byId.values)
      if (l.fromNoteId == noteId) l,
  ];

  List<Link> forHighlight(String highlightId) => [
    for (final l in _byId.values)
      if (l.toHighlightId == highlightId) l,
  ];

  /// The link between this note and this highlight, if there is one.
  Link? between(String noteId, String highlightId) {
    for (final l in _byId.values) {
      if (l.fromNoteId == noteId && l.toHighlightId == highlightId) return l;
    }
    return null;
  }

  void replaceAll(Iterable<Link> links) {
    _byId
      ..clear()
      ..addEntries(links.map((l) => MapEntry(l.id, l)));
    if (selectedId != null && !_byId.containsKey(selectedId)) selectedId = null;
    notifyListeners();
  }

  void add(Link l) {
    _byId[l.id] = l;
    notifyListeners();
  }

  void remove(String id) {
    if (_byId.remove(id) == null) return;
    if (selectedId == id) selectedId = null;
    notifyListeners();
  }

  void select(String? id) {
    if (selectedId == id) return;
    selectedId = id;
    notifyListeners();
  }
}

/// Where one link's two ends are, in world space.
class LinkEnds {
  const LinkEnds(this.note, this.highlight, this.control);
  final Offset note, highlight, control;

  Offset get middle => LinkGeometry.at(note, control, highlight, 0.5);
}

/// Resolves links to places. A link whose note or highlight is not on the
/// canvas (deleted, or its page gone) has no ends and is not drawn.
class LinkLayout {
  const LinkLayout({
    required this.scene,
    required this.notes,
    required this.highlights,
  });

  final Scene scene;
  final NotesLayer notes;
  final HighlightLayer highlights;

  Box? noteBox(String noteId) {
    final n = notes.byId(noteId);
    if (n == null) return null;
    final o = NotesOverlay.worldOrigin(n, scene);
    if (o == null) return null;
    return Box(o.dx, o.dy, o.dx + n.width, o.dy + n.height);
  }

  List<Box>? highlightBoxes(String highlightId) {
    final h = highlights.byId(highlightId);
    final card = h?.pageId == null ? null : scene.byId(h!.pageId!);
    if (h == null || card == null || h.rects.isEmpty) return null;
    final o = card.rect.topLeft;
    return [
      for (final r in h.rects)
        Box(r.x0 + o.dx, r.y0 + o.dy, r.x1 + o.dx, r.y1 + o.dy),
    ];
  }

  LinkEnds? ends(Link l) {
    final nb = noteBox(l.fromNoteId), hb = highlightBoxes(l.toHighlightId);
    if (nb == null || hb == null) return null;
    final centre = Offset((nb.x0 + nb.x1) / 2, (nb.y0 + nb.y1) / 2);
    final h = LinkGeometry.onHighlight(hb, centre);
    final n = LinkGeometry.edgeToward(nb, h);
    return LinkEnds(n, h, LinkGeometry.control(n, h));
  }
}

/// Draws every link as an indigo curve with a dot where it meets the
/// highlight (DESIGN "Link Line": 2.5 px, round caps).
class LinksPainter extends CustomPainter {
  LinksPainter({
    required this.view,
    required this.scene,
    required this.links,
    required this.notes,
    required this.highlights,
    required this.tokens,
  }) : super(
         repaint: Listenable.merge([view, scene, links, notes, highlights]),
       );

  final ValueListenable<ViewState> view;
  final ValueListenable<Scene> scene;
  final LinksLayer links;
  final NotesLayer notes;
  final HighlightLayer highlights;
  final AetherTokens tokens;

  @override
  void paint(Canvas canvas, Size size) {
    if (links.count == 0) return;
    final v = view.value;
    final layout = LinkLayout(
      scene: scene.value,
      notes: notes,
      highlights: highlights,
    );
    final world = v.worldRect(size).inflate(60 / v.zoom);
    canvas.save();
    canvas.translate(v.x, v.y);
    canvas.scale(v.zoom);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = tokens.indigo;
    final dot = Paint()..color = tokens.indigo;
    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = tokens.indigo.withValues(alpha: 0.25);
    for (final l in links.all) {
      final e = layout.ends(l);
      if (e == null) continue;
      final box = Rect.fromPoints(
        e.note,
        e.highlight,
      ).inflate(math.max((e.control - e.note).distance, 1));
      if (!box.overlaps(world)) continue;
      final path = Path()
        ..moveTo(e.note.dx, e.note.dy)
        ..quadraticBezierTo(
          e.control.dx,
          e.control.dy,
          e.highlight.dx,
          e.highlight.dy,
        );
      final selected = links.selectedId == l.id;
      if (selected) {
        halo.strokeWidth = 10 / v.zoom;
        canvas.drawPath(path, halo);
      }
      line.strokeWidth = (selected ? 3.5 : 2.5) / v.zoom;
      canvas.drawPath(path, line);
      canvas.drawCircle(e.highlight, 4 / v.zoom, dot);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(LinksPainter old) =>
      old.view != view ||
      old.scene != scene ||
      old.links != links ||
      old.tokens != tokens;
}

/// The link being dragged out, and the target it would snap to.
class LiveLink extends ChangeNotifier {
  bool active = false;

  /// World space: where the line starts and where it points now.
  Offset from = Offset.zero, to = Offset.zero;

  /// World-space rects of the target to halo, empty if nothing is in reach.
  List<Rect> target = const [];

  void begin(Offset start) {
    active = true;
    from = to = start;
    target = const [];
    notifyListeners();
  }

  void update({
    required Offset from,
    required Offset to,
    List<Rect> target = const [],
  }) {
    this.from = from;
    this.to = to;
    this.target = target;
    notifyListeners();
  }

  void end() {
    active = false;
    target = const [];
    notifyListeners();
  }
}

/// Draws the link being dragged: a dashed line, and a halo round its target.
class LiveLinkPainter extends CustomPainter {
  LiveLinkPainter({
    required this.view,
    required this.live,
    required this.tokens,
  }) : super(repaint: Listenable.merge([view, live]));

  final ValueListenable<ViewState> view;
  final LiveLink live;
  final AetherTokens tokens;

  @override
  void paint(Canvas canvas, Size size) {
    if (!live.active) return;
    final v = view.value;
    canvas.save();
    canvas.translate(v.x, v.y);
    canvas.scale(v.zoom);
    final px = 1 / v.zoom;
    for (final r in live.target) {
      final rr = RRect.fromRectAndRadius(
        r.inflate(4 * px),
        Radius.circular(AetherTokens.rHighlight * px + 4 * px),
      );
      canvas.drawRRect(
        rr,
        Paint()..color = tokens.indigoWash.withValues(alpha: 0.7),
      );
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * px
          ..color = tokens.indigo,
      );
    }
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.5 * px
      ..color = tokens.indigo;
    final path = Path()
      ..moveTo(live.from.dx, live.from.dy)
      ..lineTo(live.to.dx, live.to.dy);
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 6 * px, m.length)), line);
        d += 11 * px;
      }
    }
    canvas.drawCircle(live.to, 4 * px, Paint()..color = tokens.indigo);
    canvas.restore();
  }

  @override
  bool shouldRepaint(LiveLinkPainter old) =>
      old.view != view || old.live != live || old.tokens != tokens;
}
