import 'package:aether/core/hlc/hlc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const dev = 'aaaa';

  test('encode/parse round-trips and sorts like compareTo', () {
    final xs = [
      const Hlc(5, 0, 'b'),
      const Hlc(5, 1, 'a'),
      const Hlc(5, 0, 'a'),
      const Hlc(4, 0xFFFF, 'z'),
      const Hlc(0x123456789ABC, 7, 'dev'),
    ];
    for (final h in xs) {
      expect(Hlc.parse(h.encode()), h);
    }
    final byObject = [...xs]..sort();
    final byString = [...xs]..sort((a, b) => a.encode().compareTo(b.encode()));
    expect(byString, byObject);
  });

  test('send is strictly increasing when the wall clock is frozen', () {
    final c = HlcClock(dev, now: () => 1000);
    final a = c.send(), b = c.send(), d = c.send();
    expect(a < b && b < d, isTrue);
    expect(d.physicalMs, 1000);
    expect(d.counter, 2);
  });

  test('send stays monotonic when the wall clock goes backwards', () {
    var now = 5000;
    final c = HlcClock(dev, now: () => now);
    final a = c.send();
    now = 1000; // clock jumped back
    final b = c.send();
    expect(b > a, isTrue);
    expect(b.physicalMs, 5000);
  });

  test('counter overflow rolls into the next millisecond', () {
    final c = HlcClock(
      dev,
      now: () => 10,
      last: const Hlc(10, Hlc.maxCounter, dev),
    );
    final h = c.send();
    expect(h.physicalMs, 11);
    expect(h.counter, 0);
  });

  test('receive orders the result after both local and remote', () {
    final c = HlcClock(dev, now: () => 100);
    final local = c.send();
    final remote = const Hlc(100, 9, 'bbbb');
    final merged = c.receive(remote);
    expect(merged > local, isTrue);
    expect(merged > remote, isTrue);
  });

  test('two devices converge on a total order', () {
    var t = 0;
    final a = HlcClock('aa', now: () => t);
    final b = HlcClock('bb', now: () => t);
    final events = <Hlc>[];
    for (var i = 0; i < 50; i++) {
      t += i.isEven ? 1 : 0;
      final h = (i % 3 == 0 ? a : b).send();
      events.add(h);
      (i % 3 == 0 ? b : a).receive(h);
    }
    final sorted = [...events]..sort();
    expect(sorted.toSet().length, events.length, reason: 'no duplicates');
  });

  test('receive rejects a remote clock far in the future', () {
    final c = HlcClock(dev, now: () => 0, maxDriftMs: 1000);
    expect(
      () => c.receive(const Hlc(5000, 0, 'bbbb')),
      throwsA(isA<ClockDriftException>()),
    );
  });

  test('malformed strings are rejected', () {
    expect(() => Hlc.parse('nope'), throwsFormatException);
  });
}
