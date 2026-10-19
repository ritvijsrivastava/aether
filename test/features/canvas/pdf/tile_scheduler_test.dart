import 'dart:async';
import 'dart:ui' as ui;

import 'package:aether/features/canvas/pdf/tile_math.dart';
import 'package:aether/features/canvas/pdf/tile_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

/// A renderer whose renders finish only when the test says so.
class FakeRenderer implements TileRenderer {
  final Map<TileKey, Completer<TileImage?>> pending = {};
  final Map<TileKey, CancelToken> tokens = {};
  final List<TileKey> started = [];
  late final ui.Image image;

  @override
  Future<TileImage?> render(TileKey key, CancelToken token) {
    started.add(key);
    tokens[key] = token;
    return (pending[key] = Completer<TileImage?>()).future;
  }

  void finish(TileKey k) => pending[k]!.complete(TileImage(image));
  void finishNull(TileKey k) => pending[k]!.complete(null);
  void fail(TileKey k) => pending[k]!.completeError(StateError('boom'));
}

TileKey k(int n) => TileKey(0, 3, n, 0);

void main() {
  late FakeRenderer r;
  late List<TileKey> delivered;
  late TileScheduler s;

  Future<void> setUpScheduler(WidgetTester tester, {int max = 2}) async {
    r = FakeRenderer();
    await tester.runAsync(
      () async => r.image = await createTestImage(width: 4, height: 4),
    );
    delivered = [];
    s = TileScheduler(
      renderer: r,
      onTile: (key, t) => delivered.add(key),
      maxConcurrent: max,
    );
    addTearDown(s.dispose);
  }

  Future<void> settle(WidgetTester tester) =>
      tester.runAsync(() => Future<void>.delayed(Duration.zero));

  testWidgets(
    'renders the most urgent tiles first, up to the concurrency limit',
    (tester) async {
      await setUpScheduler(tester);
      s.want({k(1): 50, k(2): 10, k(3): 30, k(4): 20});
      expect(r.started, [k(2), k(4)]);
      expect((s.active, s.queued), (2, 2));
    },
  );

  testWidgets('starts the next tile as soon as one finishes', (tester) async {
    await setUpScheduler(tester);
    s.want({k(1): 1, k(2): 2, k(3): 3});
    r.finish(k(1));
    await settle(tester);
    expect(r.started, [k(1), k(2), k(3)]);
    expect(delivered, [k(1)]);
  });

  testWidgets(
    'tiles no longer wanted are canceled in flight and dropped from the queue',
    (tester) async {
      await setUpScheduler(tester);
      s.want({k(1): 1, k(2): 2, k(3): 3});
      s.want({k(3): 3});
      expect(r.tokens[k(1)]!.isCanceled, isTrue);
      expect(r.tokens[k(2)]!.isCanceled, isTrue);
      expect(s.queued, 1);
      // A canceled render's result is discarded, not delivered.
      r.finish(k(1));
      r.finishNull(k(2));
      await settle(tester);
      expect(delivered, isEmpty);
      expect(
        r.started.last,
        k(3),
        reason: 'freed slots go to what is still wanted',
      );
    },
  );

  testWidgets('priorities of queued tiles can change between frames', (
    tester,
  ) async {
    await setUpScheduler(tester, max: 1);
    s.want({k(1): 1, k(2): 50, k(3): 60});
    s.want({k(1): 1, k(2): 50, k(3): 2}); // k3 became urgent
    r.finish(k(1));
    await settle(tester);
    expect(r.started, [k(1), k(3)]);
  });

  testWidgets('a wanted tile already in flight is not started twice', (
    tester,
  ) async {
    await setUpScheduler(tester);
    s.want({k(1): 1});
    s.want({k(1): 1});
    s.want({k(1): 5});
    expect(r.started, [k(1)]);
  });

  testWidgets(
    'a tile wanted again while its canceled render winds down is re-rendered after',
    (tester) async {
      await setUpScheduler(tester, max: 1);
      s.want({k(1): 1});
      s.want({}); // scrolled away: canceled but still running
      s.want({k(1): 1}); // scrolled back
      expect(r.started, [k(1)], reason: 'cannot run twice at once');
      r.finishNull(k(1)); // the canceled run ends
      await settle(tester);
      expect(r.started, [k(1), k(1)]);
    },
  );

  testWidgets(
    'a failing tile does not block the rest and is not retried in a storm',
    (tester) async {
      await setUpScheduler(tester, max: 1);
      s.want({k(1): 1, k(2): 2});
      r.fail(k(1));
      await settle(tester);
      expect(s.failed, 1);
      expect(r.started, [k(1), k(2)]);
      // Still wanted next frame: not retried.
      s.want({k(1): 1, k(2): 2});
      expect(r.started.where((e) => e == k(1)).length, 1);
      // Once it leaves the wanted set, it may be tried again later.
      s.want({k(2): 2});
      expect(s.failed, 0);
      s.want({k(1): 1, k(2): 2});
      r.finish(k(2)); // frees the single slot, which k1 can now take
      await settle(tester);
      expect(r.started.where((e) => e == k(1)).length, 2);
    },
  );

  testWidgets('a renderer that throws synchronously is treated as a failure', (
    tester,
  ) async {
    final bad = _Throwing();
    final sched = TileScheduler(renderer: bad, onTile: (_, _) {});
    addTearDown(sched.dispose);
    sched.want({k(1): 1});
    await settle(tester);
    expect(sched.failed, 1);
    expect(sched.active, 0);
  });

  testWidgets('dispose cancels everything and stops delivering', (
    tester,
  ) async {
    await setUpScheduler(tester);
    s.want({k(1): 1, k(2): 2, k(3): 3});
    s.dispose();
    expect(r.tokens.values.every((t) => t.isCanceled), isTrue);
    r.finish(k(1));
    await settle(tester);
    expect(delivered, isEmpty);
    s.want({k(9): 1});
    expect(r.started.contains(k(9)), isFalse);
  });

  testWidgets('counts completed tiles', (tester) async {
    await setUpScheduler(tester);
    s.want({k(1): 1, k(2): 2});
    r.finish(k(1));
    r.finish(k(2));
    await settle(tester);
    expect(s.completed, 2);
  });

  test(
    'CancelToken runs listeners once, and immediately if already canceled',
    () {
      final t = CancelToken();
      var n = 0;
      t.onCancel(() => n++);
      t.cancel();
      t.cancel();
      expect(n, 1);
      t.onCancel(() => n++);
      expect(n, 2);
    },
  );
}

class _Throwing implements TileRenderer {
  @override
  Future<TileImage?> render(TileKey key, CancelToken token) =>
      throw StateError('sync');
}
