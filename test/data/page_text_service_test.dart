import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:aether/data/pdf/page_text_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeExtractor implements PageTextExtractor {
  int calls = 0;
  Completer<void>? gate;
  bool fail = false;
  bool unavailable = false;

  @override
  Future<({Int32List codes, Float32List boxes})?> extract(int pageIndex) async {
    calls++;
    await gate?.future;
    if (fail) throw StateError('pdfium said no');
    if (unavailable) return null;
    final s = 'page $pageIndex text';
    final codes = Int32List.fromList(s.runes.toList());
    final boxes = Float32List(codes.length * 4);
    for (var i = 0; i < codes.length; i++) {
      boxes.setAll(i * 4, [i * 6.0, 0, i * 6.0 + 6, 10]);
    }
    return (codes: codes, boxes: boxes);
  }
}

void main() {
  late Directory dir;
  late _FakeExtractor ex;
  late PageTextCache cache;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('axt');
    ex = _FakeExtractor();
    cache = PageTextCache(dir);
  });
  tearDown(() => dir.delete(recursive: true));

  PageTextService service({int max = 48, bool withCache = true}) =>
      PageTextService(
        docKey: 'abc',
        extractor: ex,
        cache: withCache ? cache : null,
        maxPagesInMemory: max,
      );

  test('extracts once, then serves from memory', () async {
    final s = service();
    final a = await s.pageText(2);
    final b = await s.pageText(2);
    expect(a.quote(0, a.length), 'page 2 text');
    expect(identical(a, b), isTrue);
    expect(ex.calls, 1);
    expect(s.memoryHits, 1);
  });

  test('a second session reads the disk cache, not pdfium', () async {
    await service().pageText(0);
    expect(ex.calls, 1);
    final again = service();
    final t = await again.pageText(0);
    expect(t.quote(0, t.length), 'page 0 text');
    expect(ex.calls, 1, reason: 'no new extraction');
    expect(again.diskHits, 1);
  });

  test('concurrent requests for one page share one extraction', () async {
    ex.gate = Completer<void>();
    final s = service();
    final f1 = s.pageText(1);
    final f2 = s.pageText(1);
    ex.gate!.complete();
    final r = await Future.wait([f1, f2]);
    expect(identical(r[0], r[1]), isTrue);
    expect(ex.calls, 1);
  });

  test('a corrupt cache file is ignored and replaced', () async {
    await service().pageText(3);
    final f = File('${dir.path}/abc/3.axt');
    await f.writeAsBytes([1, 2, 3]);
    final s = service();
    final t = await s.pageText(3);
    expect(t.quote(0, t.length), 'page 3 text');
    expect(ex.calls, 2);
    expect(s.diskHits, 0);
    final fresh = service();
    await fresh.pageText(3);
    expect(fresh.diskHits, 1, reason: 'the file was rewritten');
  });

  test('a failing page is empty, not an exception, and is retried', () async {
    ex.fail = true;
    final s = service();
    final t = await s.pageText(0);
    expect(t.hasText, isFalse);
    ex.fail = false;
    final retry = await s.pageText(0);
    expect(retry.hasText, isTrue);
    expect(ex.calls, 2);
  });

  test('an unavailable page is empty and is not cached', () async {
    ex.unavailable = true;
    final s = service();
    expect((await s.pageText(0)).hasText, isFalse);
    expect(File('${dir.path}/abc/0.axt').existsSync(), isFalse);
    ex.unavailable = false;
    expect((await s.pageText(0)).hasText, isTrue);
  });

  test('memory is bounded; the least recently used page goes first', () async {
    final s = service(max: 2, withCache: false);
    await s.pageText(0);
    await s.pageText(1);
    await s.pageText(0); // 0 is now newer than 1
    await s.pageText(2); // evicts 1
    expect(s.peek(0), isNotNull);
    expect(s.peek(1), isNull);
    expect(s.peek(2), isNotNull);
  });

  test('delete removes a document\'s cached pages', () async {
    await service().pageText(0);
    expect(Directory('${dir.path}/abc').existsSync(), isTrue);
    await cache.delete('abc');
    expect(Directory('${dir.path}/abc').existsSync(), isFalse);
    await cache.delete('abc'); // already gone: no error
  });
}
