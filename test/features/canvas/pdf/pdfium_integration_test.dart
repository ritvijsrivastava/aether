import 'dart:io';

import 'package:aether/features/canvas/pdf/pdf_source.dart';
import 'package:aether/features/canvas/pdf/pdfium_tile_renderer.dart';
import 'package:aether/features/canvas/pdf/tile_math.dart';
import 'package:aether/features/canvas/pdf/tile_scheduler.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart' show Pdfrx;
import 'package:flutter_test/flutter_test.dart';

/// Real pdfium against the local fixture (third-party, git-ignored). Skipped
/// with a clear reason if it is not on this machine.
const _fixture = 'test/fixtures/mapreduce/mapreduce.pdf';

/// `flutter test` does not run native-asset hooks, so pdfium is not bundled
/// into the test environment. Use the library a previous `flutter build`
/// left behind (or `PDFIUM_PATH`).
String? _pdfiumLibrary() {
  for (final p in [
    Platform.environment['PDFIUM_PATH'],
    'build/native_assets/linux/libpdfium.so',
  ]) {
    if (p != null && File(p).existsSync()) return File(p).absolute.path;
  }
  return null;
}

final _lib = _pdfiumLibrary();
final _missing = !File(_fixture).existsSync()
    ? 'fixture $_fixture not present'
    : _lib == null
    ? 'no libpdfium.so (run flutter build linux once, or set PDFIUM_PATH)'
    : null;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // pdfrx asks the path_provider plugin for a temp directory; there is no
  // plugin under flutter test, so answer that one channel.
  setUpAll(() {
    if (_lib != null) Pdfrx.pdfiumModulePath = _lib;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => Directory.systemTemp.path,
        );
  });

  testWidgets(
    'opens the owner-password-only paper silently, with its page sizes',
    (tester) async {
      await tester.runAsync(() async {
        final pdf = await openPdfFile(_fixture);
        addTearDown(pdf.dispose);
        expect(pdf.pageSizes.length, 13);
        expect(pdf.pageSizes.first, const Size(612, 792));
      });
    },
    skip: _missing != null,
  );

  testWidgets(
    'renders a tile at the size the geometry promises, and it is not blank',
    (tester) async {
      await tester.runAsync(() async {
        final pdf = await openPdfFile(_fixture);
        addTearDown(pdf.dispose);
        final renderer = PdfiumTileRenderer(pdf.document);
        const lod = 4; // 4 px per point: 2448 x 3168, a 5 x 7 grid
        final g = TileGeometry(pdf.pageSizes[0], lod);
        final px = g.pixelRect(1, 2);
        final tile = await renderer.render(
          const TileKey(0, lod, 1, 2),
          CancelToken(),
        );
        expect(tile, isNotNull);
        expect(tile!.image.width, px.width.round());
        expect(tile.image.height, px.height.round());
        expect(tile.bytes, tile.image.width * tile.image.height * 4);
        final data = (await tile.image.toByteData())!;
        var dark = 0;
        for (var i = 0; i < data.lengthInBytes; i += 4) {
          if (data.getUint8(i) < 128) dark++; // some text pixels
        }
        expect(
          dark,
          greaterThan(100),
          reason: 'a mid-page tile of a text paper has glyph pixels',
        );
        tile.dispose();
      });
    },
    skip: _missing != null,
  );

  testWidgets('renders an edge tile at its smaller size', (tester) async {
    await tester.runAsync(() async {
      final pdf = await openPdfFile(_fixture);
      addTearDown(pdf.dispose);
      const lod = 4;
      final g = TileGeometry(pdf.pageSizes[0], lod);
      final px = g.pixelRect(g.cols - 1, g.rows - 1);
      final tile = await PdfiumTileRenderer(pdf.document)
          .render(TileKey(0, lod, g.cols - 1, g.rows - 1), CancelToken());
      expect(
        (tile!.image.width, tile.image.height),
        (px.width.round(), px.height.round()),
      );
      tile.dispose();
    });
  }, skip: _missing != null);

  testWidgets('a canceled render returns null and leaks nothing', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final pdf = await openPdfFile(_fixture);
      addTearDown(pdf.dispose);
      final token = CancelToken()..cancel();
      final tile = await PdfiumTileRenderer(pdf.document)
          .render(const TileKey(0, 2, 0, 0), token);
      expect(tile, isNull);
    });
  }, skip: _missing != null);

  testWidgets('the whole-page base tile is a single small tile', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final pdf = await openPdfFile(_fixture);
      addTearDown(pdf.dispose);
      final size = pdf.pageSizes[0];
      final base = TileMath.baseLod(size);
      final tile = await PdfiumTileRenderer(pdf.document)
          .render(TileKey(0, base, 0, 0), CancelToken());
      expect(tile!.image.width, lessThanOrEqualTo(tileSize));
      expect(tile.image.height, lessThanOrEqualTo(tileSize));
      tile.dispose();
    });
  }, skip: _missing != null);

  test(
    'a missing file fails as unreadable, not as a crash',
    skip: _lib == null ? 'no libpdfium.so' : null,
    () async {
      await expectLater(
        openPdfFile('/nonexistent/nope.pdf'),
        throwsA(
          isA<PdfOpenException>().having(
            (e) => e.failure,
            'failure',
            PdfOpenFailure.unreadable,
          ),
        ),
      );
    },
  );
}
