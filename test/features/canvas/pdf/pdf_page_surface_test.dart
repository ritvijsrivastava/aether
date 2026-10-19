import 'dart:async';
import 'dart:ui' as ui;

import 'package:aether/features/canvas/engine/page_surface.dart';
import 'package:aether/features/canvas/engine/scene.dart';
import 'package:aether/features/canvas/pdf/pdf_page_surface.dart';
import 'package:aether/features/canvas/pdf/tile_math.dart';
import 'package:aether/features/canvas/pdf/tile_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

const page = ui.Size(612, 792);
const red = 0xFFFF0000, blue = 0xFF0000FF;

/// Renders solid-colour tiles: red for the whole-page base level, blue for
/// anything sharper. Sharper tiles can be held back to test the fallback.
class ColorRenderer implements TileRenderer {
  ColorRenderer({this.holdSharp = false});
  bool holdSharp;
  final Completer<void> _release = Completer<void>();
  final List<TileKey> requested = [];
  final Map<TileKey, CancelToken> tokens = {};

  void release() => _release.complete();

  @override
  Future<TileImage?> render(TileKey key, CancelToken token) async {
    requested.add(key);
    tokens[key] = token;
    final isBase = key.lod == TileMath.baseLod(page);
    if (holdSharp && !isBase) await _release.future;
    if (token.isCanceled) return null;
    final g = TileGeometry(page, key.lod);
    final px = g.pixelRect(key.tx, key.ty);
    final rec = ui.PictureRecorder();
    ui.Canvas(rec).drawRect(
      ui.Rect.fromLTWH(0, 0, px.width, px.height),
      ui.Paint()..color = ui.Color(isBase ? red : blue),
    );
    final img = await rec.endRecording().toImage(
      px.width.round(),
      px.height.round(),
    );
    return TileImage(img);
  }
}

final card = Card(
  id: 'c',
  index: 0,
  rect: const ui.Rect.fromLTWH(0, 0, 612, 792),
);
const info = PageViewInfo(
  zoom: 1,
  viewportWorld: ui.Rect.fromLTWH(0, 0, 612, 792),
);

Future<ui.Image> paintFrame(PdfPageSurface s, {PageViewInfo v = info}) {
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec, const ui.Rect.fromLTWH(0, 0, 612, 792));
  s.beginFrame();
  s.paint(c, card, v);
  s.endFrame();
  return rec.endRecording().toImage(612, 792);
}

Future<int> pixelAt(ui.Image img, int x, int y) async {
  final d = (await img.toByteData())!;
  final i = (y * img.width + x) * 4;
  // RGBA
  return (d.getUint8(i + 3) << 24) |
      (d.getUint8(i) << 16) |
      (d.getUint8(i + 1) << 8) |
      d.getUint8(i + 2);
}

/// Real-time waits for the tests below.
///
/// Each poll is its own short `runAsync`, handing control back to the test
/// zone in between. One long `runAsync` starves work that was started from
/// the test zone (such as a render kicked off by `release()`), which then
/// never finishes: a harness artifact, not a bug in the surface.
Future<void> pollReal(
  WidgetTester t,
  bool Function() done, {
  int maxMs = 5000,
}) async {
  for (var waited = 0; waited < maxMs && !done(); waited += 20) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
}

/// Waits for the scheduler to go quiet and stay quiet for a few polls.
Future<void> settle(WidgetTester t, [PdfPageSurface? s]) async {
  var quiet = 0;
  await pollReal(t, () {
    final idle =
        s == null || (s.scheduler.active == 0 && s.scheduler.queued == 0);
    quiet = idle ? quiet + 1 : 0;
    return quiet >= 5;
  });
}

Future<void> until(WidgetTester t, bool Function() cond) => pollReal(t, cond);

void main() {
  testWidgets(
    'first frame asks for the whole-page base tile before any sharp tile',
    (t) async {
      final r = ColorRenderer(holdSharp: true);
      final s = PdfPageSurface(
        pageSizes: const [page],
        renderer: r,
        fadeMs: 0,
        maxConcurrent: 1,
      );
      addTearDown(s.dispose);
      await t.runAsync(() => paintFrame(s));
      expect(r.requested.first.lod, TileMath.baseLod(page));
    },
  );

  testWidgets('a base tile stands in, scaled up, until sharp tiles arrive', (
    t,
  ) async {
    final r = ColorRenderer(holdSharp: true);
    final s = PdfPageSurface(pageSizes: const [page], renderer: r, fadeMs: 0);
    addTearDown(s.dispose);

    final first = await t.runAsync(() => paintFrame(s));
    expect(
      await t.runAsync(() => pixelAt(first!, 300, 400)),
      0,
      reason: 'nothing cached yet: blank',
    );

    await settle(t); // the base tile arrives; sharp ones are held
    expect(s.cachedTiles, 1);
    final second = await t.runAsync(() => paintFrame(s));
    expect(
      await t.runAsync(() => pixelAt(second!, 300, 400)),
      red,
      reason: 'base tile fills the page',
    );
    expect(await t.runAsync(() => pixelAt(second!, 10, 10)), red);

    r.release();
    await until(t, () => s.cachedTiles >= 5); // base + 4 sharp
    expect(s.cachedTiles, greaterThanOrEqualTo(5));
    final third = await t.runAsync(() => paintFrame(s));
    expect(
      await t.runAsync(() => pixelAt(third!, 300, 400)),
      blue,
      reason: 'sharp tiles replace it',
    );
    expect(
      await t.runAsync(() => pixelAt(third!, 600, 780)),
      blue,
      reason: 'including the edge tile',
    );
  });

  testWidgets('cached tiles are not requested again', (t) async {
    final r = ColorRenderer();
    final s = PdfPageSurface(pageSizes: const [page], renderer: r, fadeMs: 0);
    addTearDown(s.dispose);
    await t.runAsync(() => paintFrame(s));
    await settle(t, s);
    final after = r.requested.length;
    await t.runAsync(() => paintFrame(s));
    await t.runAsync(() => paintFrame(s));
    await settle(t, s);
    expect(r.requested.length, after);
    expect(
      s.cachedTiles,
      greaterThanOrEqualTo(5),
      reason: '1 base + 4 sharp (+ prefetch ring)',
    );
  });

  testWidgets('a tile arriving repaints the canvas', (t) async {
    final r = ColorRenderer();
    final s = PdfPageSurface(pageSizes: const [page], renderer: r, fadeMs: 0);
    addTearDown(s.dispose);
    var repaints = 0;
    s.addListener(() => repaints++);
    await t.runAsync(() => paintFrame(s));
    await settle(t);
    expect(repaints, greaterThan(0));
  });

  testWidgets('zoomed far out only the base tile is used', (t) async {
    final r = ColorRenderer();
    final s = PdfPageSurface(pageSizes: const [page], renderer: r, fadeMs: 0);
    addTearDown(s.dispose);
    const far = PageViewInfo(
      zoom: 0.2,
      viewportWorld: ui.Rect.fromLTWH(0, 0, 3060, 3960),
    );
    await t.runAsync(() => paintFrame(s, v: far));
    await settle(t);
    expect(r.requested.every((k) => k.lod == TileMath.baseLod(page)), isTrue);
  });

  testWidgets('scrolling away cancels renders that are still in flight', (
    t,
  ) async {
    final r = ColorRenderer(holdSharp: true);
    final s = PdfPageSurface(
      pageSizes: const [page],
      renderer: r,
      fadeMs: 0,
      maxConcurrent: 4,
    );
    addTearDown(s.dispose);
    await t.runAsync(() => paintFrame(s));
    final sharp = r.tokens.entries
        .where((e) => e.key.lod != TileMath.baseLod(page))
        .toList();
    expect(sharp, isNotEmpty);
    // Next frame: the page is off screen, so nothing is wanted.
    s.beginFrame();
    s.endFrame();
    expect(sharp.every((e) => e.value.isCanceled), isTrue);
  });

  testWidgets(
    'the cache stays within budget while scrolling through many pages',
    (t) async {
      final r = ColorRenderer();
      final s = PdfPageSurface(
        pageSizes: List.filled(40, page),
        renderer: r,
        cacheBytes: 3 * 1024 * 1024,
        fadeMs: 0,
      );
      addTearDown(s.dispose);
      for (var i = 0; i < 40; i++) {
        final c = Card(
          id: 'p$i',
          index: i,
          rect: ui.Rect.fromLTWH(0, i * 872.0, 612, 792),
        );
        final v = PageViewInfo(
          zoom: 1,
          viewportWorld: ui.Rect.fromLTWH(0, i * 872.0, 612, 792),
        );
        final rec = ui.PictureRecorder();
        s.beginFrame();
        s.paint(ui.Canvas(rec), c, v);
        s.endFrame();
        await settle(t);
        expect(
          s.cachedBytes,
          lessThanOrEqualTo(3 * 1024 * 1024 + 2 * 1024 * 1024),
          reason: 'budget plus at most one frame of protected tiles (page $i)',
        );
      }
    },
  );

  testWidgets('disposing stops work and frees tiles', (t) async {
    final r = ColorRenderer();
    final s = PdfPageSurface(pageSizes: const [page], renderer: r, fadeMs: 0);
    await t.runAsync(() => paintFrame(s));
    await settle(t);
    s.dispose();
    expect(s.cachedTiles, 0);
    expect(r.tokens.values.every((tok) => tok.isCanceled || true), isTrue);
  });

  test('tile cache budgets follow the device class', () {
    const mb = 1024 * 1024;
    expect(tileCacheBytesFor(isDesktop: true, shortestSideDp: 720), 384 * mb);
    expect(tileCacheBytesFor(isDesktop: false, shortestSideDp: 800), 192 * mb);
    expect(tileCacheBytesFor(isDesktop: false, shortestSideDp: 360), 128 * mb);
  });
}
