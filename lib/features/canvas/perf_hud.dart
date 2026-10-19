import 'dart:async';
import 'dart:collection';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../ui/theme/tokens.dart';

/// Frame statistics over a rolling window of recent frames.
class FrameStats {
  const FrameStats({
    required this.fps,
    required this.buildMs,
    required this.rasterMs,
    required this.worstMs,
    required this.frames,
  });

  /// Average frames per second across the window (frames are only produced
  /// while something changes, so this reads high only during interaction).
  final double fps;
  final double buildMs, rasterMs;

  /// The slowest single frame (build + raster, wall clock) in the window.
  final double worstMs;
  final int frames;

  static const empty = FrameStats(
    fps: 0,
    buildMs: 0,
    rasterMs: 0,
    worstMs: 0,
    frames: 0,
  );
}

/// Rolling statistics over the engine's frame timings.
class FrameStatsCollector {
  FrameStatsCollector({this.window = 120});

  final int window;
  final Queue<FrameTiming> _timings = Queue();

  void add(List<FrameTiming> batch) {
    for (final t in batch) {
      _timings.addLast(t);
      if (_timings.length > window) _timings.removeFirst();
    }
  }

  FrameStats get stats {
    if (_timings.length < 2) return FrameStats.empty;
    var build = 0.0, raster = 0.0, worst = 0.0;
    for (final t in _timings) {
      build += t.buildDuration.inMicroseconds / 1000;
      raster += t.rasterDuration.inMicroseconds / 1000;
      final total = t.totalSpan.inMicroseconds / 1000;
      if (total > worst) worst = total;
    }
    final n = _timings.length;
    final span =
        (_timings.last.timestampInMicroseconds(FramePhase.rasterFinish) -
            _timings.first.timestampInMicroseconds(FramePhase.rasterFinish)) /
        1e6;
    return FrameStats(
      fps: span > 0 ? (n - 1) / span : 0,
      buildMs: build / n,
      rasterMs: raster / n,
      worstMs: worst,
      frames: n,
    );
  }
}

/// A small readout of frame times and the display refresh rate, for judging
/// smoothness on a real device. Off unless enabled in Settings.
class PerfHud extends StatefulWidget {
  const PerfHud({super.key});

  @override
  State<PerfHud> createState() => _PerfHudState();
}

class _PerfHudState extends State<PerfHud> {
  final _collector = FrameStatsCollector();
  Timer? _timer;
  FrameStats _stats = FrameStats.empty;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() => _stats = _collector.stats);
    });
  }

  void _onTimings(List<FrameTiming> t) => _collector.add(t);

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hz = View.of(context).display.refreshRate;
    final s = _stats;
    final bad = s.worstMs > 1000 / (hz > 0 ? hz : 60) * 1.5;
    return IgnorePointer(
      child: Semantics(
        label: 'Performance overlay',
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.ink.withValues(alpha: .86),
            borderRadius: BorderRadius.circular(AetherTokens.rCard),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: DefaultTextStyle(
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: t.desk,
              ),
              child: Text(
                '${s.fps.toStringAsFixed(0)} fps of ${hz.toStringAsFixed(0)} Hz'
                '  ·  build ${s.buildMs.toStringAsFixed(1)}'
                '  raster ${s.rasterMs.toStringAsFixed(1)}'
                '  worst ${s.worstMs.toStringAsFixed(0)} ms${bad ? ' !' : ''}',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
