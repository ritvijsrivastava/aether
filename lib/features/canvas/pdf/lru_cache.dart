import 'dart:collection';

/// A cache bounded by total byte size, evicting the least recently used.
///
/// Entries touched since the last [beginFrame] are protected: what is on
/// screen right now is never evicted to make room, even if that leaves the
/// cache briefly over budget.
class LruBytesCache<K, V> {
  LruBytesCache({required this.maxBytes, this.onEvict});

  /// Budget in bytes. May be changed (e.g. on a memory warning).
  int maxBytes;

  /// Called for every entry removed (eviction, replacement, [clear]).
  final void Function(K key, V value)? onEvict;

  // Insertion order is recency order: oldest first.
  final LinkedHashMap<K, _Entry<V>> _map = LinkedHashMap();
  int _bytes = 0;
  int _generation = 0;
  int hits = 0, misses = 0;

  int get bytes => _bytes;
  int get length => _map.length;
  bool containsKey(K key) => _map.containsKey(key);

  /// Marks the start of a frame; entries touched from now on are protected.
  void beginFrame() => _generation++;

  /// The value for [key], marking it most recently used and protected.
  V? get(K key) {
    final e = _map.remove(key);
    if (e == null) {
      misses++;
      return null;
    }
    hits++;
    e.touched = _generation;
    _map[key] = e; // re-insert at the most recent end
    return e.value;
  }

  /// The value for [key] without touching its recency (for fallback lookups).
  V? peek(K key) => _map[key]?.value;

  void put(K key, V value, int size) {
    final old = _map.remove(key);
    if (old != null) {
      _bytes -= old.size;
      onEvict?.call(key, old.value);
    }
    _map[key] = _Entry(value, size, _generation);
    _bytes += size;
    _trim();
  }

  /// Evicts down to budget; call after a frame's lookups.
  void endFrame() => _trim();

  void _trim() {
    if (_bytes <= maxBytes) return;
    for (final key in _map.keys.toList()) {
      if (_bytes <= maxBytes) break;
      final e = _map[key]!;
      if (e.touched == _generation) continue; // on screen right now
      _map.remove(key);
      _bytes -= e.size;
      onEvict?.call(key, e.value);
    }
  }

  void clear() {
    final all = _map.entries.toList();
    _map.clear();
    _bytes = 0;
    for (final e in all) {
      onEvict?.call(e.key, e.value.value);
    }
  }
}

class _Entry<V> {
  _Entry(this.value, this.size, this.touched);
  final V value;
  final int size;
  int touched;
}
