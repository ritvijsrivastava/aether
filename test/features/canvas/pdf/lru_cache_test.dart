import 'package:aether/features/canvas/pdf/lru_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> evicted;
  late LruBytesCache<String, String> cache;
  setUp(() {
    evicted = [];
    cache = LruBytesCache(maxBytes: 100, onEvict: (k, v) => evicted.add(k));
  });

  test('stores and returns values, counting bytes', () {
    cache.put('a', 'A', 30);
    cache.put('b', 'B', 20);
    expect(cache.get('a'), 'A');
    expect(cache.bytes, 50);
    expect(cache.length, 2);
  });

  test('evicts the least recently used when over budget', () {
    cache.put('a', 'A', 40);
    cache.put('b', 'B', 40);
    cache.beginFrame();
    cache.put('c', 'C', 40); // 120 > 100
    expect(evicted, ['a']);
    expect(cache.containsKey('a'), isFalse);
    expect(cache.bytes, 80);
  });

  test('a get refreshes recency', () {
    cache.put('a', 'A', 40);
    cache.put('b', 'B', 40);
    cache.beginFrame();
    cache.get('a'); // a is now newer than b, and protected this frame
    cache.beginFrame();
    cache.put('c', 'C', 40);
    expect(evicted, ['b']);
  });

  test('entries touched this frame are never evicted, even over budget', () {
    cache.put('a', 'A', 60);
    cache.put('b', 'B', 60);
    cache.beginFrame();
    cache.get('a');
    cache.get('b'); // both on screen
    cache.endFrame();
    expect(evicted, isEmpty);
    expect(
      cache.bytes,
      120,
      reason: 'briefly over budget rather than evicting visible tiles',
    );
    cache.beginFrame(); // next frame nothing touches them
    cache.endFrame();
    expect(evicted, ['a']);
    expect(cache.bytes, 60);
  });

  test('peek does not change recency or protection', () {
    cache.put('a', 'A', 60);
    cache.put('b', 'B', 60);
    cache.beginFrame();
    cache.peek('a');
    cache.endFrame();
    expect(evicted, ['a'], reason: 'peeked entries are not protected');
  });

  test('replacing a key releases the old value and its bytes', () {
    cache.put('a', 'A1', 40);
    cache.put('a', 'A2', 10);
    expect(evicted, ['a']);
    expect(cache.bytes, 10);
    expect(cache.get('a'), 'A2');
  });

  test('clear evicts everything', () {
    cache.put('a', 'A', 10);
    cache.put('b', 'B', 10);
    cache.clear();
    expect(evicted.toSet(), {'a', 'b'});
    expect(cache.bytes, 0);
    expect(cache.length, 0);
  });

  test('counts hits and misses', () {
    cache.put('a', 'A', 1);
    cache.get('a');
    cache.get('a');
    cache.get('x');
    expect((cache.hits, cache.misses), (2, 1));
  });

  test('shrinking the budget evicts on the next frame', () {
    for (var i = 0; i < 5; i++) {
      cache.put('k$i', 'v', 20);
    }
    cache.beginFrame();
    cache.maxBytes = 40;
    cache.endFrame();
    expect(cache.bytes, lessThanOrEqualTo(40));
    expect(evicted.length, 3);
  });

  test('a long scroll never holds more than the budget plus one frame', () {
    // Each frame touches 5 tiles of 10 bytes; the budget is 100.
    for (var f = 0; f < 200; f++) {
      cache.beginFrame();
      for (var i = 0; i < 5; i++) {
        final k = 't${f * 5 + i}';
        cache.get(k);
        cache.put(k, 'v', 10);
      }
      cache.endFrame();
      expect(cache.bytes, lessThanOrEqualTo(100));
    }
  });
}
