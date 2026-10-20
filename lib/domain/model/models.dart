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
  static const docId = 'docId';
  static const width = 'width';
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
  const Document({required this.id, required this.title});

  factory Document.fromState(EntityState s) =>
      Document(id: s.id, title: s.field<String>(F.title) ?? 'Untitled');

  final String id;
  final String title;

  Map<String, Object?> toFields() => {F.title: title};
}

/// Base for everything the user draws, in world space.
@immutable
sealed class Mark {
  const Mark({required this.id, required this.docId});

  final String id;
  final String docId;

  MarkType get type;
  Box get bounds;

  /// Fields shared by all marks, including the indexed bounds columns.
  @protected
  Map<String, Object?> baseFields() => {
    F.type: type.name,
    F.docId: docId,
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
    return Ink(id: id, docId: docId, samples: out, width: width, color: color);
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
