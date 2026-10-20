import 'dart:typed_data';

import 'package:aether/core/hlc/hlc.dart';
import 'package:aether/domain/model/ink_codec.dart';
import 'package:aether/domain/model/models.dart';
import 'package:aether/domain/ops/entity_state.dart';
import 'package:aether/domain/ops/op.dart';
import 'package:flutter_test/flutter_test.dart';

EntityState stateOf(EntityKind kind, String id, Map<String, Object?> fields) =>
    EntityState(
      id: id,
      kind: kind,
      deleted: false,
      createdHlc: const Hlc(1, 1, 'test'),
      fields: fields,
    );

void main() {
  test('ink samples survive the codec bit-for-bit', () {
    final src = Float32List.fromList([
      0.5,
      -1.25,
      0.0,
      612.0,
      792.5,
      1.0,
      3.14159,
      2.71828,
      0.33,
    ]);
    final back = InkCodec.decode(InkCodec.encode(src));
    expect(back, src);
  });

  test('an empty stroke round-trips', () {
    expect(InkCodec.decode(InkCodec.encode(Float32List(0))), isEmpty);
  });

  test('Ink round-trips and reports padded bounds', () {
    final ink = Ink(
      id: 'i1',
      docId: 'd1',
      width: 4,
      samples: Float32List.fromList([10, 10, 0.5, 30, 50, 0.7]),
    );
    final f = ink.toFields();
    expect(f['bx0'], 8.0);
    expect(f['by1'], 52.0);
    final back = Mark.fromState(stateOf(EntityKind.mark, 'i1', f)) as Ink;
    expect(back.samples, ink.samples);
    expect(back.pointCount, 2);
  });

  test('Ink.translated keeps everything but the position', () {
    final ink = Ink(
      id: 'i1',
      docId: 'd1',
      width: 3,
      samples: Float32List.fromList([10, 10, 0.5, 30, 50, 0.7]),
    );
    final t = ink.translated(5, -2);
    expect(t.samples, Float32List.fromList([15, 8, 0.5, 35, 48, 0.7]));
    expect((t.id, t.width, t.color), ('i1', 3, ink.color));
  });

  test('Document round-trips', () {
    const d = Document(id: 'd1', title: 'Sketch');
    final back = Document.fromState(
      stateOf(EntityKind.document, 'd1', d.toFields()),
    );
    expect(back.title, 'Sketch');
  });

  test('any colour survives a round trip', () {
    const c = 0x80123456;
    final ink = Ink(
      id: 'i',
      docId: 'd',
      samples: Float32List.fromList([0, 0, 0.5]),
      color: c,
    );
    final back =
        Mark.fromState(stateOf(EntityKind.mark, 'i', ink.toFields())) as Ink;
    expect(back.color, c);
  });
}
