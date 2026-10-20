import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:aether/domain/ink/ink_geometry.dart';
import 'package:aether/domain/model/models.dart';
import 'package:aether/features/canvas/ink/ink_layer.dart';
import 'package:flutter_test/flutter_test.dart';

/// SPEC §13: "Ink while drawing, page with 10,000 strokes: stable 60 fps".
/// These run a page of 10,000 strokes of about 40 samples each (a dense page
/// of handwriting is a few thousand) and time the work that happens per frame
/// and per stroke. They run in a debug-mode VM, so the limits are loose; the
/// numbers printed are what to compare against on the tablet.
List<Ink> strokes(int n, {String page = 'p0'}) {
  final r = math.Random(5);
  return [
    for (var i = 0; i < n; i++)
      () {
        final x = r.nextDouble() * 560, y = r.nextDouble() * 760;
        final samples = Float32List(40 * 3);
        for (var k = 0; k < 40; k++) {
          samples[k * 3] = x + k * 0.8;
          samples[k * 3 + 1] = y + math.sin(k / 5) * 6;
          samples[k * 3 + 2] = 0.3 + 0.4 * (k / 40);
        }
        return Ink(
          id: 's$i',
          docId: 'd',
          pageId: page,
          samples: InkGeometry.simplify(samples, 0.15),
          width: 2.5,
          color: 0xFF2B2723,
        );
      }(),
  ];
}

void main() {
  test('building and loading 10,000 strokes', () {
    final sw = Stopwatch()..start();
    final all = strokes(10000);
    final built = sw.elapsedMilliseconds;
    sw.reset();
    final layer = InkLayer()..replaceAll(all);
    // ignore: avoid_print
    print('build $built ms, load into the layer ${sw.elapsedMilliseconds} ms');
    expect(layer.count, 10000);
    expect(sw.elapsedMilliseconds, lessThan(2000));
  });

  test(
    'recording the page picture happens once, and replaying it is cheap',
    () async {
      final layer = InkLayer()..replaceAll(strokes(10000));
      final sw = Stopwatch()..start();
      var rec = PictureRecorder();
      layer.paint(Canvas(rec), 'p0');
      final first = sw.elapsedMilliseconds;
      final pic = rec.endRecording();
      sw.reset();
      // Panning replays the same recorded picture: no strokes are rebuilt.
      for (var i = 0; i < 60; i++) {
        rec = PictureRecorder();
        layer.paint(Canvas(rec), 'p0');
        rec.endRecording().dispose();
      }
      final replay = sw.elapsedMicroseconds / 60 / 1000;
      pic.dispose();
      // ignore: avoid_print
      print(
        'first paint (records 10,000 strokes): $first ms; '
        'each later paint: ${replay.toStringAsFixed(3)} ms; '
        'pictures recorded: ${layer.rebuilds}',
      );
      expect(layer.rebuilds, 1);
      expect(replay, lessThan(2), reason: 'a frame must not rebuild strokes');
    },
  );

  test('drawing a new stroke on a full page does not rebuild the page', () {
    final layer = InkLayer()..replaceAll(strokes(10000));
    final c = Canvas(PictureRecorder());
    layer.paint(c, 'p0');
    final sw = Stopwatch()..start();
    final fresh = strokes(20);
    for (var i = 0; i < 20; i++) {
      layer.add(
        Ink(
          id: 'new$i',
          docId: 'd',
          pageId: 'p0',
          samples: fresh[i].samples,
          width: 2.5,
          color: 1,
        ),
      );
      layer.paint(c, 'p0');
    }
    final per = sw.elapsedMicroseconds / 20 / 1000;
    // ignore: avoid_print
    print(
      'adding a stroke and repainting: ${per.toStringAsFixed(3)} ms each, '
      'rebuilds: ${layer.rebuilds}',
    );
    expect(layer.rebuilds, 1);
    expect(per, lessThan(5));
  });

  test('erase hit-testing on a full page stays fast', () {
    final layer = InkLayer()..replaceAll(strokes(10000));
    final r = math.Random(1);
    // Warm up.
    for (var i = 0; i < 100; i++) {
      layer.touching('p0', r.nextDouble() * 560, r.nextDouble() * 760, 14);
    }
    final sw = Stopwatch()..start();
    var found = 0;
    const n = 2000;
    for (var i = 0; i < n; i++) {
      found += layer
          .touching('p0', r.nextDouble() * 560, r.nextDouble() * 760, 14)
          .length;
    }
    final per = sw.elapsedMicroseconds / n / 1000;
    // ignore: avoid_print
    print(
      'touching() on 10,000 strokes: ${per.toStringAsFixed(3)} ms per call '
      '(avg ${found / n} found)',
    );
    expect(per, lessThan(2));
  });

  test('the outline of one stroke costs well under a millisecond', () {
    final s = strokes(1).first;
    final sw = Stopwatch()..start();
    for (var i = 0; i < 500; i++) {
      strokePath(s.samples, s.width, layerCurve);
    }
    final per = sw.elapsedMicroseconds / 500 / 1000;
    // ignore: avoid_print
    print('outline of a stroke: ${per.toStringAsFixed(3)} ms');
    expect(per, lessThan(1));
  });

  test('the live stroke path for a long stroke stays under a frame', () {
    // A stroke of 3,000 samples redrawn on every frame while it is drawn.
    final n = 3000;
    final s = Float32List(n * 3);
    for (var i = 0; i < n; i++) {
      s[i * 3] = i * 0.2;
      s[i * 3 + 1] = math.sin(i / 30) * 40;
      s[i * 3 + 2] = 0.5;
    }
    final sw = Stopwatch()..start();
    for (var i = 0; i < 20; i++) {
      strokePath(s, 2.5, layerCurve);
    }
    final per = sw.elapsedMicroseconds / 20 / 1000;
    // ignore: avoid_print
    print('live path of a 3,000-sample stroke: ${per.toStringAsFixed(2)} ms');
    expect(per, lessThan(16));
  });

  group('crowded pages are drawn from a bitmap', () {
    testWidgets(
      'a page over the limit gets one bitmap, which later paints reuse',
      (tester) async {
        await tester.runAsync(() async {
          final layer = InkLayer()..replaceAll(strokes(1000));
          void paint(double scale) {
            final rec = PictureRecorder();
            layer.paint(Canvas(rec), 'p0', scale: scale);
            rec.endRecording().dispose();
          }

          paint(1); // records the picture, draws paths, asks for a bitmap
          expect(layer.rebuilds, 1);
          expect(layer.bitmapRenders, 0);
          await Future<void>.delayed(const Duration(milliseconds: 400));
          expect(layer.bitmapRenders, 1);
          for (var i = 0; i < 30; i++) {
            paint(1); // panning: no more renders
          }
          expect(layer.bitmapRenders, 1);
          expect(layer.rebuilds, 1);
        });
      },
    );

    testWidgets('a small page never makes a bitmap', (tester) async {
      await tester.runAsync(() async {
        final layer = InkLayer()..replaceAll(strokes(InkLayer.bitmapThreshold));
        final rec = PictureRecorder();
        layer.paint(Canvas(rec), 'p0', scale: 1);
        rec.endRecording().dispose();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(layer.bitmapRenders, 0);
      });
    });

    testWidgets('the bitmap looks like the paths', (tester) async {
      await tester.runAsync(() async {
        final layer = InkLayer()..replaceAll(strokes(800));
        Future<ByteData> render() async {
          final rec = PictureRecorder();
          final c = Canvas(rec)
            ..drawColor(const Color(0xFFFFFFFF), BlendMode.src);
          layer.paint(c, 'p0', scale: 1);
          final img = await rec.endRecording().toImage(620, 820);
          return (await img.toByteData())!;
        }

        final paths = await render();
        await Future<void>.delayed(const Duration(milliseconds: 400));
        expect(layer.bitmapRenders, 1);
        final bitmap = await render();
        // Average darkness agrees closely: the same ink in the same places.
        double dark(ByteData d) {
          var sum = 0;
          for (var i = 0; i < d.lengthInBytes; i += 4) {
            sum += 255 - d.getUint8(i);
          }
          return sum / (d.lengthInBytes / 4);
        }

        expect(dark(bitmap), closeTo(dark(paths), dark(paths) * 0.08));
        expect(dark(paths), greaterThan(1), reason: 'there is ink to compare');
      });
    });

    testWidgets(
      'zooming in far enough asks for a sharper one; zooming out does not',
      (tester) async {
        await tester.runAsync(() async {
          final layer = InkLayer()..replaceAll(strokes(800));
          void paint(double scale) {
            final rec = PictureRecorder();
            layer.paint(Canvas(rec), 'p0', scale: scale);
            rec.endRecording().dispose();
          }

          paint(1);
          await Future<void>.delayed(const Duration(milliseconds: 400));
          expect(layer.bitmapRenders, 1);
          paint(0.4); // zoomed out: the same bitmap, scaled down
          await Future<void>.delayed(const Duration(milliseconds: 300));
          expect(layer.bitmapRenders, 1);
          paint(3); // zoomed in 3x: needs a sharper bitmap
          await Future<void>.delayed(const Duration(milliseconds: 500));
          expect(layer.bitmapRenders, 2);
        });
      },
    );

    testWidgets(
      'a new stroke is drawn over the bitmap, not into it, until folded',
      (tester) async {
        await tester.runAsync(() async {
          final layer = InkLayer()..replaceAll(strokes(800));
          void paint() {
            final rec = PictureRecorder();
            layer.paint(Canvas(rec), 'p0', scale: 1);
            rec.endRecording().dispose();
          }

          paint();
          await Future<void>.delayed(const Duration(milliseconds: 400));
          final renders = layer.bitmapRenders;
          layer.add(
            Ink(
              id: 'extra',
              docId: 'd',
              pageId: 'p0',
              samples: Float32List.fromList([1, 1, 1, 50, 50, 1]),
              width: 2,
              color: 1,
            ),
          );
          paint();
          await Future<void>.delayed(const Duration(milliseconds: 300));
          expect(
            layer.bitmapRenders,
            renders,
            reason: 'no new bitmap for one stroke',
          );
          expect(layer.rebuilds, 1);
        });
      },
    );

    testWidgets('erasing from a crowded page drops the stale bitmap', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final layer = InkLayer()..replaceAll(strokes(800));
        void paint() {
          final rec = PictureRecorder();
          layer.paint(Canvas(rec), 'p0', scale: 1);
          rec.endRecording().dispose();
        }

        paint();
        await Future<void>.delayed(const Duration(milliseconds: 400));
        layer.remove('s5');
        paint(); // must not draw the old image, which still has s5
        expect(layer.rebuilds, 2);
        await Future<void>.delayed(const Duration(milliseconds: 400));
        expect(layer.bitmapRenders, 2, reason: 'a fresh bitmap without it');
      });
    });
  });
}

final layerCurve = InkLayer().curve;
