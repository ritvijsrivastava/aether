import 'dart:typed_data';

import 'package:aether/core/geometry/box.dart';
import 'package:aether/core/hlc/hlc.dart';
import 'package:aether/domain/model/ink_codec.dart';
import 'package:aether/domain/model/models.dart';
import 'package:aether/domain/ops/entity_state.dart';
import 'package:aether/domain/ops/op.dart';
import 'package:flutter_test/flutter_test.dart';

EntityState stateOf(EntityKind k, String id, Map<String, Object?> fields) {
  var s = EntityState(id: id, kind: k);
  var n = 0;
  s = s.applyOp(
    Op(
      opId: 'c',
      hlc: Hlc(++n, 0, 'd'),
      entityKind: k,
      entityId: id,
      kind: OpKind.create,
      txGroupId: 't',
    ),
  );
  for (final e in fields.entries) {
    s = s.applyOp(
      Op(
        opId: 's$n',
        hlc: Hlc(++n, 0, 'd'),
        entityKind: k,
        entityId: id,
        kind: OpKind.setField,
        txGroupId: 't',
        field: e.key,
        value: e.value,
      ),
    );
  }
  return s;
}

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

  test('Highlight round-trips through fields and EntityState', () {
    const h = Highlight(
      id: 'h1',
      docId: 'd1',
      pageId: 'p1',
      color: Swatch.method,
      startChar: 10,
      endChar: 40,
      quote: 'a re-routing step',
      contextBefore: 'we add ',
      contextAfter: ' that runs',
      rects: [Box(10, 20, 100, 32), Box(10, 34, 60, 46)],
    );
    final back = Mark.fromState(stateOf(EntityKind.mark, 'h1', h.toFields()));
    expect(back, isA<Highlight>());
    final b = back as Highlight;
    expect(b.color, Swatch.method);
    expect(b.quote, h.quote);
    expect(b.rects, h.rects);
    expect(b.bounds, const Box(10, 20, 100, 46));
  });

  test('Ink round-trips and reports padded bounds', () {
    final ink = Ink(
      id: 'i1',
      docId: 'd1',
      pageId: 'p1',
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

  test('Note and Link round-trip', () {
    const n = Note(id: 'n1', docId: 'd1', x: 5, y: 6, text: 'Why 3%?');
    final nb =
        Mark.fromState(stateOf(EntityKind.mark, 'n1', n.toFields())) as Note;
    expect(
      (nb.x, nb.y, nb.text, nb.width),
      (5.0, 6.0, 'Why 3%?', Note.defaultWidth),
    );
    const l = Link(
      id: 'l1',
      docId: 'd1',
      fromNoteId: 'n1',
      toHighlightId: 'h1',
    );
    final lb = Link.fromState(stateOf(EntityKind.link, 'l1', l.toFields()));
    expect((lb.fromNoteId, lb.toHighlightId), ('n1', 'h1'));
  });

  test(
    'a Note keeps its size, and an old note without one gets the default',
    () {
      const n = Note(
        id: 'n2',
        docId: 'd1',
        pageId: 'p1',
        x: 10,
        y: 20,
        width: 300,
        height: 150,
        text: 'hi',
      );
      final back =
          Mark.fromState(stateOf(EntityKind.mark, 'n2', n.toFields())) as Note;
      expect((back.width, back.height), (300.0, 150.0));
      expect(back.bounds.width, 300);
      expect(back.bounds.height, 150);

      final old = Map<String, Object?>.of(n.toFields())..remove(F.height);
      final oldBack =
          Mark.fromState(stateOf(EntityKind.mark, 'n2', old)) as Note;
      expect(oldBack.height, Note.defaultHeight);
    },
  );

  test('Note.copyWith changes only what it is given', () {
    const n = Note(id: 'n', docId: 'd', pageId: 'p', x: 1, y: 2, text: 'a');
    final m = n.copyWith(x: 9, text: 'b');
    expect((m.x, m.y, m.text, m.pageId, m.id), (9.0, 2.0, 'b', 'p', 'n'));
    expect(m.width, n.width);
    expect(n.copyWith().height, n.height);
  });

  test('Document and PageRef round-trip', () {
    const d = Document(
      id: 'd1',
      title: 'MapReduce',
      sourceHash: 'abc',
      pageCount: 13,
    );
    final db = Document.fromState(
      stateOf(EntityKind.document, 'd1', d.toFields()),
    );
    expect((db.title, db.pageCount), ('MapReduce', 13));
    const p = PageRef(
      id: 'p1',
      docId: 'd1',
      index: 2,
      width: 612,
      height: 792,
      cardX: 1500,
      cardY: 0,
    );
    final pb = PageRef.fromState(stateOf(EntityKind.page, 'p1', p.toFields()));
    expect((pb.index, pb.cardX, pb.height), (2, 1500.0, 792.0));
  });

  test('an unknown legacy meaning falls back instead of throwing', () {
    expect(Swatch.fromLegacyMeaning('nonsense'), Swatch.coral);
    expect(Swatch.fromLegacyMeaning(null), Swatch.coral);
    expect(Swatch.fromLegacyMeaning('method'), Swatch.amber);
    expect(Swatch.fromLegacyMeaning('question'), Swatch.blue);
  });

  test('a highlight saved before colour was free keeps its colour', () {
    final fields = {
      ...const Highlight(
        id: 'h',
        docId: 'd',
        pageId: 'p',
        color: 0,
        startChar: 0,
        endChar: 1,
        quote: 'q',
        rects: [],
      ).toFields(),
    }..remove(F.color);
    fields[F.meaning] = 'question';
    final h =
        Mark.fromState(stateOf(EntityKind.mark, 'h', fields)) as Highlight;
    expect(h.color, Swatch.blue);
  });

  test('any colour survives a round trip', () {
    const h = Highlight(
      id: 'h',
      docId: 'd',
      pageId: 'p',
      color: 0xFF12AB34,
      startChar: 0,
      endChar: 1,
      quote: 'q',
      rects: [],
    );
    final back = Mark.fromState(stateOf(EntityKind.mark, 'h', h.toFields()));
    expect((back as Highlight).color, 0xFF12AB34);
  });
}
