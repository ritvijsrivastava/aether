import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../../core/geometry/box.dart';
import '../ops/entity_state.dart';
import 'ink_codec.dart';

/// The three default highlight colours (the old Claim, Method and Question).
/// Colour is free: a highlight stores any ARGB value, and these are only the
/// swatches the marker starts with. They carry no name.
abstract final class Swatch {
  static const int coral = 0xFFF4877E;
  static const int amber = 0xFFF2C94C;
  static const int blue = 0xFF6FB1EE;
  static const List<int> defaults = [coral, amber, blue];

  // The old meaning names, for data written before colour became free.
  static const int claim = coral, method = amber, question = blue;

  /// The colour of a highlight stored with the old `meaning` field.
  static int fromLegacyMeaning(String? id) => switch (id) {
    'method' => method,
    'question' => question,
    _ => claim,
  };
}

enum MarkType { highlight, ink, note }

/// Field names used in op values. Kept in one place so writers and readers
/// cannot drift apart.
abstract final class F {
  static const title = 'title';
  static const sourceHash = 'sourceHash';
  static const pageCount = 'pageCount';
  static const docId = 'docId';
  static const pageId = 'pageId';
  static const index = 'index';
  static const width = 'width';
  static const height = 'height';
  static const cardX = 'cardX';
  static const cardY = 'cardY';
  static const type = 'type';
  static const meaning = 'meaning';
  static const startChar = 'startChar';
  static const endChar = 'endChar';
  static const quote = 'quote';
  static const contextBefore = 'contextBefore';
  static const contextAfter = 'contextAfter';
  static const rects = 'rects';
  static const points = 'points';
  static const color = 'color';
  static const x = 'x';
  static const y = 'y';
  static const text = 'text';
  static const z = 'z';
  static const fromNoteId = 'fromNoteId';
  static const toHighlightId = 'toHighlightId';
  static const bx0 = 'bx0';
  static const by0 = 'by0';
  static const bx1 = 'bx1';
  static const by1 = 'by1';
}

@immutable
class Document {
  const Document({
    required this.id,
    required this.title,
    required this.sourceHash,
    required this.pageCount,
  });

  factory Document.fromState(EntityState s) => Document(
    id: s.id,
    title: s.field<String>(F.title) ?? 'Untitled',
    sourceHash: s.field<String>(F.sourceHash) ?? '',
    pageCount: (s.field<num>(F.pageCount) ?? 0).toInt(),
  );

  final String id;
  final String title;
  final String sourceHash;
  final int pageCount;

  Map<String, Object?> toFields() => {
    F.title: title,
    F.sourceHash: sourceHash,
    F.pageCount: pageCount,
  };
}

/// One PDF page as a movable card on the canvas.
@immutable
class PageRef {
  const PageRef({
    required this.id,
    required this.docId,
    required this.index,
    required this.width,
    required this.height,
    required this.cardX,
    required this.cardY,
  });

  factory PageRef.fromState(EntityState s) => PageRef(
    id: s.id,
    docId: s.field<String>(F.docId) ?? '',
    index: (s.field<num>(F.index) ?? 0).toInt(),
    width: (s.field<num>(F.width) ?? 612).toDouble(),
    height: (s.field<num>(F.height) ?? 792).toDouble(),
    cardX: (s.field<num>(F.cardX) ?? 0).toDouble(),
    cardY: (s.field<num>(F.cardY) ?? 0).toDouble(),
  );

  final String id;
  final String docId;
  final int index;
  final double width, height;
  final double cardX, cardY;

  Map<String, Object?> toFields() => {
    F.docId: docId,
    F.index: index,
    F.width: width,
    F.height: height,
    F.cardX: cardX,
    F.cardY: cardY,
  };
}

/// Base for everything the user draws or writes. Stored in page space when
/// [pageId] is set, in canvas space otherwise.
@immutable
sealed class Mark {
  const Mark({required this.id, required this.docId, this.pageId});

  final String id;
  final String docId;
  final String? pageId;

  MarkType get type;
  Box get bounds;

  /// Fields shared by all marks, including the indexed bounds columns.
  @protected
  Map<String, Object?> baseFields() => {
    F.type: type.name,
    F.docId: docId,
    F.pageId: pageId,
    F.bx0: bounds.x0,
    F.by0: bounds.y0,
    F.bx1: bounds.x1,
    F.by1: bounds.y1,
  };

  Map<String, Object?> toFields();

  static Mark fromState(EntityState s) {
    final docId = s.field<String>(F.docId) ?? '';
    final pageId = s.field<String>(F.pageId);
    switch (MarkType.values.byName(s.field<String>(F.type) ?? 'note')) {
      case MarkType.highlight:
        return Highlight(
          id: s.id,
          docId: docId,
          pageId: pageId,
          color:
              (s.field<num>(F.color) ??
                      Swatch.fromLegacyMeaning(s.field<String>(F.meaning)))
                  .toInt(),
          startChar: (s.field<num>(F.startChar) ?? 0).toInt(),
          endChar: (s.field<num>(F.endChar) ?? 0).toInt(),
          quote: s.field<String>(F.quote) ?? '',
          contextBefore: s.field<String>(F.contextBefore) ?? '',
          contextAfter: s.field<String>(F.contextAfter) ?? '',
          rects: [
            for (final r in (s.field<List<dynamic>>(F.rects) ?? const []))
              Box.fromJson(r as List<dynamic>),
          ],
        );
      case MarkType.ink:
        return Ink(
          id: s.id,
          docId: docId,
          pageId: pageId,
          samples: InkCodec.decode(s.field<String>(F.points) ?? ''),
          width: (s.field<num>(F.width) ?? 2.5).toDouble(),
          color: (s.field<num>(F.color) ?? 0xFF2B2723).toInt(),
        );
      case MarkType.note:
        return Note(
          id: s.id,
          docId: docId,
          pageId: pageId,
          x: (s.field<num>(F.x) ?? 0).toDouble(),
          y: (s.field<num>(F.y) ?? 0).toDouble(),
          width: (s.field<num>(F.width) ?? Note.defaultWidth).toDouble(),
          height: (s.field<num>(F.height) ?? Note.defaultHeight).toDouble(),
          text: s.field<String>(F.text) ?? '',
          z: (s.field<num>(F.z) ?? 0).toInt(),
        );
    }
  }
}

class Highlight extends Mark {
  const Highlight({
    required super.id,
    required super.docId,
    super.pageId,
    required this.color,
    required this.startChar,
    required this.endChar,
    required this.quote,
    this.contextBefore = '',
    this.contextAfter = '',
    required this.rects,
  });

  /// ARGB highlight colour.
  final int color;
  final int startChar, endChar;

  Highlight copyWith({int? color}) => Highlight(
    id: id,
    docId: docId,
    pageId: pageId,
    color: color ?? this.color,
    startChar: startChar,
    endChar: endChar,
    quote: quote,
    contextBefore: contextBefore,
    contextAfter: contextAfter,
    rects: rects,
  );

  /// The quoted text as it was at creation time.
  final String quote;

  /// About 24 characters either side, for re-anchoring if the text layer changes.
  final String contextBefore, contextAfter;

  /// One rect per visual line, in page space.
  final List<Box> rects;

  @override
  MarkType get type => MarkType.highlight;

  @override
  Box get bounds => rects.isEmpty
      ? const Box(0, 0, 0, 0)
      : rects.reduce((a, b) => a.union(b));

  @override
  Map<String, Object?> toFields() => {
    ...baseFields(),
    F.color: color,
    F.startChar: startChar,
    F.endChar: endChar,
    F.quote: quote,
    F.contextBefore: contextBefore,
    F.contextAfter: contextAfter,
    F.rects: [for (final r in rects) r.toJson()],
  };
}

class Ink extends Mark {
  const Ink({
    required super.id,
    required super.docId,
    super.pageId,
    required this.samples,
    this.width = 2.5,
    this.color = 0xFF2B2723,
  });

  /// `x, y, pressure` triplets.
  final Float32List samples;
  final double width;

  /// ARGB.
  final int color;

  int get pointCount => samples.length ~/ InkCodec.stride;

  Ink copyWith({int? color}) => Ink(
    id: id,
    docId: docId,
    pageId: pageId,
    samples: samples,
    width: width,
    color: color ?? this.color,
  );

  /// The same stroke moved by ([dx], [dy]).
  Ink translated(double dx, double dy) {
    final out = Float32List(samples.length);
    for (var i = 0; i < samples.length; i += InkCodec.stride) {
      out[i] = samples[i] + dx;
      out[i + 1] = samples[i + 1] + dy;
      out[i + 2] = samples[i + 2];
    }
    return Ink(
      id: id,
      docId: docId,
      pageId: pageId,
      samples: out,
      width: width,
      color: color,
    );
  }

  @override
  MarkType get type => MarkType.ink;

  @override
  Box get bounds {
    if (samples.isEmpty) return const Box(0, 0, 0, 0);
    var x0 = samples[0], y0 = samples[1], x1 = x0, y1 = y0;
    for (var i = 0; i < samples.length; i += InkCodec.stride) {
      final x = samples[i], y = samples[i + 1];
      if (x < x0) x0 = x;
      if (x > x1) x1 = x;
      if (y < y0) y0 = y;
      if (y > y1) y1 = y;
    }
    final pad = width / 2;
    return Box(x0 - pad, y0 - pad, x1 + pad, y1 + pad);
  }

  @override
  Map<String, Object?> toFields() => {
    ...baseFields(),
    F.points: InkCodec.encode(samples),
    F.width: width,
    F.color: color,
  };
}

class Note extends Mark {
  const Note({
    required super.id,
    required super.docId,
    super.pageId,
    required this.x,
    required this.y,
    this.width = defaultWidth,
    this.height = defaultHeight,
    this.text = '',
    this.z = 0,
  });

  static const double defaultWidth = 220;
  static const double defaultHeight = 120;

  /// The smallest a note may be resized to (page points).
  static const double minWidth = 140, minHeight = 80;

  /// Top-left in page space ([pageId] set) or canvas space (null).
  final double x, y;
  final double width, height;
  final String text;

  /// Stacking order among notes: higher is in front.
  final int z;

  Note copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    String? text,
    int? z,
  }) => Note(
    id: id,
    docId: docId,
    pageId: pageId,
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
    text: text ?? this.text,
    z: z ?? this.z,
  );

  @override
  MarkType get type => MarkType.note;

  @override
  Box get bounds => Box(x, y, x + width, y + height);

  @override
  Map<String, Object?> toFields() => {
    ...baseFields(),
    F.x: x,
    F.y: y,
    F.width: width,
    F.height: height,
    F.text: text,
    F.z: z,
  };
}

/// Connects a note to a highlight. A note may have many links.
@immutable
class Link {
  const Link({
    required this.id,
    required this.docId,
    required this.fromNoteId,
    required this.toHighlightId,
  });

  factory Link.fromState(EntityState s) => Link(
    id: s.id,
    docId: s.field<String>(F.docId) ?? '',
    fromNoteId: s.field<String>(F.fromNoteId) ?? '',
    toHighlightId: s.field<String>(F.toHighlightId) ?? '',
  );

  final String id;
  final String docId;
  final String fromNoteId, toHighlightId;

  Map<String, Object?> toFields() => {
    F.docId: docId,
    F.fromNoteId: fromNoteId,
    F.toHighlightId: toHighlightId,
  };
}
