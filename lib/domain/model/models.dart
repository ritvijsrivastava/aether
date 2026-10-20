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
}

enum MarkType { ink }

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
  static const points = 'points';
  static const color = 'color';
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
    return Ink(
      id: s.id,
      docId: s.field<String>(F.docId) ?? '',
      pageId: s.field<String>(F.pageId),
      samples: InkCodec.decode(s.field<String>(F.points) ?? ''),
      width: (s.field<num>(F.width) ?? 2.5).toDouble(),
      color: (s.field<num>(F.color) ?? 0xFF2B2723).toInt(),
    );
  }
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
