import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../../domain/text/page_text.dart';
import '../../domain/text/page_text_source.dart';
import '../../domain/text/page_text_codec.dart';

/// Reads the characters of one page. Implemented over pdfium; faked in tests.
abstract class PageTextExtractor {
  /// The page's characters and boxes (see [PageText.build]), or null if the
  /// page could not be read right now (not cached, so a later call retries).
  Future<({Int32List codes, Float32List boxes})?> extract(int pageIndex);
}

/// Extracts text through pdfrx. pdfium runs on pdfrx's worker isolate, so the
/// UI isolate only converts coordinates.
class PdfrxTextExtractor implements PageTextExtractor {
  PdfrxTextExtractor(this.document);
  final PdfDocument document;

  @override
  Future<({Int32List codes, Float32List boxes})?> extract(int pageIndex) async {
    if (pageIndex < 0 || pageIndex >= document.pages.length) return null;
    final page = document.pages[pageIndex];
    final raw = await page.loadText();
    if (raw == null) return null;

    // pdfium gives one rect per UTF-16 unit of fullText, but a code point
    // outside the BMP is two units. Walk the runes and keep the first unit's
    // rect, so codes and boxes stay one-to-one.
    final text = raw.fullText;
    final codes = <int>[];
    final unitIndex = <int>[];
    var u = 0;
    for (final r in text.runes) {
      codes.add(r);
      unitIndex.add(u);
      u += r > 0xFFFF ? 2 : 1;
    }
    final n = codes.length;
    final boxes = Float32List(n * 4);
    for (var i = 0; i < n; i++) {
      final ri = unitIndex[i];
      if (ri >= raw.charRects.length) continue;
      final r = raw.charRects[ri];
      if (r.isEmpty) continue; // leaves a zero box: an invisible character
      final f = r.toRect(page: page); // page space: points, y down, rotated
      boxes[i * 4] = f.left;
      boxes[i * 4 + 1] = f.top;
      boxes[i * 4 + 2] = f.right;
      boxes[i * 4 + 3] = f.bottom;
    }
    return (codes: Int32List.fromList(codes), boxes: boxes);
  }
}

/// Per-page text cached on disk, one small file per page:
/// `<root>/<documentHash>/<pageIndex>.axt`.
class PageTextCache {
  PageTextCache(this.root);
  final Directory root;

  File _file(String docKey, int page) =>
      File(p.join(root.path, docKey, '$page.axt'));

  Future<PageText?> read(String docKey, int page) async {
    final f = _file(docKey, page);
    try {
      if (!await f.exists()) return null;
      return PageTextCodec.decode(await f.readAsBytes());
    } catch (e) {
      debugPrint('Text cache read failed ($docKey p$page): $e');
      return null;
    }
  }

  /// Writes through a temporary file and a rename, so a crash never leaves a
  /// half-written page that decodes as valid.
  Future<void> write(String docKey, int page, PageText text) async {
    final f = _file(docKey, page);
    try {
      await f.parent.create(recursive: true);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsBytes(PageTextCodec.encode(text), flush: true);
      await tmp.rename(f.path);
    } catch (e) {
      debugPrint('Text cache write failed ($docKey p$page): $e');
    }
  }

  /// Removes every cached page of a document (when its PDF is purged).
  Future<void> delete(String docKey) async {
    final d = Directory(p.join(root.path, docKey));
    if (await d.exists()) await d.delete(recursive: true);
  }
}

/// Text for the pages of one open document, lazily: memory first, then the
/// disk cache, then pdfium. Concurrent requests for a page share one
/// extraction.
class PageTextService implements PageTextSource {
  PageTextService({
    required this.docKey,
    required this.extractor,
    this.cache,
    this.maxPagesInMemory = 48,
  });

  /// Identifies the document in the cache: the PDF's content hash.
  final String docKey;
  final PageTextExtractor extractor;
  final PageTextCache? cache;
  final int maxPagesInMemory;

  final LinkedHashMap<int, PageText> _memory = LinkedHashMap();
  final Map<int, Future<PageText>> _inFlight = {};

  /// Counters for tests and the debug HUD.
  int extractions = 0, diskHits = 0, memoryHits = 0;

  /// How long the last and the slowest pdfium extraction took, in ms.
  int lastExtractMs = 0, maxExtractMs = 0;

  /// One line for the performance overlay.
  String get stats =>
      'text ${_memory.length}p · extract last $lastExtractMs ms'
      ' max $maxExtractMs ms';

  /// The text of page [pageIndex] (0-based). Never throws: a page that cannot
  /// be read comes back as [PageText.empty] and is retried on the next call.
  @override
  Future<PageText> pageText(int pageIndex) {
    final hit = _memory.remove(pageIndex);
    if (hit != null) {
      _memory[pageIndex] = hit; // most recent
      memoryHits++;
      return Future.value(hit);
    }
    return _inFlight[pageIndex] ??= _load(pageIndex).whenComplete(() {
      _inFlight.remove(pageIndex);
    });
  }

  /// The page if it is already in memory.
  @override
  PageText? peek(int pageIndex) => _memory[pageIndex];

  Future<PageText> _load(int i) async {
    final cached = await cache?.read(docKey, i);
    if (cached != null) {
      diskHits++;
      return _remember(i, cached);
    }
    try {
      extractions++;
      final sw = Stopwatch()..start();
      final raw = await extractor.extract(i);
      if (raw == null) return PageText.empty;
      final text = PageText.build(raw.codes, raw.boxes);
      lastExtractMs = sw.elapsedMilliseconds;
      if (lastExtractMs > maxExtractMs) maxExtractMs = lastExtractMs;
      await cache?.write(docKey, i, text);
      return _remember(i, text);
    } catch (e) {
      debugPrint('Text extraction failed ($docKey p$i): $e');
      return PageText.empty;
    }
  }

  PageText _remember(int i, PageText t) {
    _memory[i] = t;
    while (_memory.length > maxPagesInMemory) {
      _memory.remove(_memory.keys.first);
    }
    return t;
  }
}
