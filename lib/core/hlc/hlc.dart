import 'package:meta/meta.dart';

/// Hybrid Logical Clock timestamp: `(physicalMs, counter, deviceId)`.
///
/// Totally ordered across devices, monotonic per device. The encoded form
/// sorts lexicographically in the same order as [compareTo].
@immutable
class Hlc implements Comparable<Hlc> {
  const Hlc(this.physicalMs, this.counter, this.deviceId);

  /// Parses the output of [encode].
  factory Hlc.parse(String s) {
    final a = s.indexOf('-');
    final b = a < 0 ? -1 : s.indexOf('-', a + 1);
    if (a != 12 || b != 17) {
      throw FormatException('Malformed HLC', s);
    }
    return Hlc(
      int.parse(s.substring(0, a), radix: 16),
      int.parse(s.substring(a + 1, b), radix: 16),
      s.substring(b + 1),
    );
  }

  static const int maxCounter = 0xFFFF;

  /// Milliseconds since the Unix epoch. Fits in 48 bits.
  final int physicalMs;
  final int counter;

  /// Lowercase hex (no hyphens), so [encode] stays unambiguous.
  final String deviceId;

  String encode() =>
      '${physicalMs.toRadixString(16).padLeft(12, '0')}-'
      '${counter.toRadixString(16).padLeft(4, '0')}-$deviceId';

  @override
  int compareTo(Hlc other) {
    final p = physicalMs.compareTo(other.physicalMs);
    if (p != 0) return p;
    final c = counter.compareTo(other.counter);
    if (c != 0) return c;
    return deviceId.compareTo(other.deviceId);
  }

  bool operator <(Hlc o) => compareTo(o) < 0;
  bool operator >(Hlc o) => compareTo(o) > 0;
  bool operator <=(Hlc o) => compareTo(o) <= 0;
  bool operator >=(Hlc o) => compareTo(o) >= 0;

  @override
  bool operator ==(Object other) => other is Hlc && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(physicalMs, counter, deviceId);

  @override
  String toString() => encode();
}

/// Thrown when a remote timestamp is implausibly far ahead of local time.
class ClockDriftException implements Exception {
  ClockDriftException(this.driftMs);
  final int driftMs;
  @override
  String toString() =>
      'ClockDriftException: remote clock is ${driftMs}ms ahead';
}

/// Issues monotonically increasing [Hlc] values for one device.
class HlcClock {
  HlcClock(
    this.deviceId, {
    int Function()? now,
    Hlc? last,
    this.maxDriftMs = 24 * 60 * 60 * 1000,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch),
       _physical = last?.physicalMs ?? 0,
       _counter = last?.counter ?? 0;

  final String deviceId;
  final int maxDriftMs;
  final int Function() _now;
  int _physical;
  int _counter;

  Hlc get last => Hlc(_physical, _counter, deviceId);

  /// Timestamp for a local event.
  Hlc send() {
    final pt = _now();
    if (pt > _physical) {
      _physical = pt;
      _counter = 0;
    } else {
      _bump();
    }
    return last;
  }

  /// Merges a remote timestamp and returns the next local one.
  Hlc receive(Hlc remote) {
    final pt = _now();
    if (remote.physicalMs - pt > maxDriftMs) {
      throw ClockDriftException(remote.physicalMs - pt);
    }
    final maxP = [
      pt,
      _physical,
      remote.physicalMs,
    ].reduce((a, b) => a > b ? a : b);
    final int c;
    if (maxP == _physical && maxP == remote.physicalMs) {
      c = (_counter > remote.counter ? _counter : remote.counter) + 1;
    } else if (maxP == _physical) {
      c = _counter + 1;
    } else if (maxP == remote.physicalMs) {
      c = remote.counter + 1;
    } else {
      c = 0;
    }
    _physical = maxP;
    _counter = c;
    if (_counter > Hlc.maxCounter) {
      _physical++;
      _counter = 0;
    }
    return last;
  }

  void _bump() {
    _counter++;
    if (_counter > Hlc.maxCounter) {
      _physical++;
      _counter = 0;
    }
  }
}
