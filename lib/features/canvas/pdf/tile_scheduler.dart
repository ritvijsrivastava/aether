import 'dart:ui' as ui;

import 'tile_math.dart';

/// A rendered tile: an uploaded image and what it costs in memory.
class TileImage {
  TileImage(this.image) : bytes = image.width * image.height * 4;
  final ui.Image image;
  final int bytes;
  void dispose() => image.dispose();
}

/// Lets the scheduler abandon work that scrolled out of view.
class CancelToken {
  bool _canceled = false;
  final List<void Function()> _listeners = [];

  bool get isCanceled => _canceled;

  void cancel() {
    if (_canceled) return;
    _canceled = true;
    for (final f in _listeners) {
      f();
    }
    _listeners.clear();
  }

  void onCancel(void Function() f) => _canceled ? f() : _listeners.add(f);
}

abstract interface class TileRenderer {
  /// Renders [key]. Completes with null if [token] was canceled; throws on
  /// failure.
  Future<TileImage?> render(TileKey key, CancelToken token);
}

/// Decides which tiles to render, in what order, and how many at once.
///
/// The surface calls [want] every frame with the tiles it is missing, each
/// with a priority (lower is more urgent). Work that is no longer wanted is
/// canceled, so a fast scroll never leaves a backlog of stale renders.
class TileScheduler {
  TileScheduler({
    required this.renderer,
    required this.onTile,
    this.maxConcurrent = 2,
    this.onError,
  });

  final TileRenderer renderer;
  final void Function(TileKey key, TileImage tile) onTile;
  final int maxConcurrent;

  /// Called when a render throws (not when it is canceled).
  final void Function(TileKey key, Object error)? onError;

  final Map<TileKey, double> _queued = {};
  final Map<TileKey, CancelToken> _inFlight = {};
  final Set<TileKey> _failed = {};
  bool _disposed = false;

  /// Renders running right now (including canceled ones still winding down).
  int get active => _inFlight.length;
  int get queued => _queued.length;
  int get failed => _failed.length;
  int completed = 0;

  void want(Map<TileKey, double> wanted) {
    if (_disposed) return;
    for (final e in _inFlight.entries) {
      if (!wanted.containsKey(e.key)) e.value.cancel();
    }
    _queued.removeWhere((k, _) => !wanted.containsKey(k));
    _failed.removeWhere((k) => !wanted.containsKey(k));
    for (final e in wanted.entries) {
      final running = _inFlight[e.key];
      if ((running == null || running.isCanceled) && !_failed.contains(e.key)) {
        _queued[e.key] = e.value;
      }
    }
    _pump();
  }

  void _pump() {
    while (!_disposed && _inFlight.length < maxConcurrent) {
      TileKey? best;
      var bestPriority = double.infinity;
      for (final e in _queued.entries) {
        // A canceled render may still be winding down: skip it until it ends.
        if (_inFlight.containsKey(e.key)) {
          continue;
        }
        if (e.value < bestPriority) {
          best = e.key;
          bestPriority = e.value;
        }
      }
      if (best == null) return;
      _queued.remove(best);
      _start(best);
    }
  }

  void _start(TileKey key) {
    final token = CancelToken();
    _inFlight[key] = token;
    Future<TileImage?> run;
    try {
      run = renderer.render(key, token);
    } catch (e) {
      run = Future.error(e);
    }
    run
        .then<void>((tile) {
          if (tile == null) return;
          if (_disposed || token.isCanceled) {
            tile.dispose();
            return;
          }
          completed++;
          onTile(key, tile);
        })
        .catchError((Object _) {
          if (!token.isCanceled) _failed.add(key);
        })
        .whenComplete(() {
          if (identical(_inFlight[key], token)) _inFlight.remove(key);
          _pump();
        });
  }

  void dispose() {
    _disposed = true;
    for (final t in _inFlight.values) {
      t.cancel();
    }
    _queued.clear();
  }
}
