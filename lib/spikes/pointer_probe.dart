// THROWAWAY (M0 spike): logs every raw pointer field to JSONL so pen support
// (pressure, eraser end, hover, buttons, palm) can be judged from real data.
// Run: flutter run -d linux -t lib/spikes/pointer_probe.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(const MaterialApp(home: ProbePage()));

const _phases = [
  'hover-press-lift',
  'light-stroke',
  'heavy-stroke',
  'eraser-end',
  'barrel-button-1',
  'barrel-button-2',
  'palm-while-hovering',
  'finger-pan',
  'two-finger-pinch',
];

class ProbePage extends StatefulWidget {
  const ProbePage({super.key});
  @override
  State<ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<ProbePage> {
  File? _file;
  final _buf = StringBuffer();
  String _path = '…';
  String _phase = 'untagged';
  int _count = 0;
  String _last = '';
  final _strokes = <List<Offset>>[];
  final _active = <int, List<Offset>>{};
  final _times = <int>[]; // µs timestamps of recent down/move events
  double _hz = 0;
  Timer? _flush;

  @override
  void initState() {
    super.initState();
    _open();
    _flush = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _writeOut();
      if (mounted) setState(() {});
    });
  }

  Future<void> _open() async {
    final dir =
        (Platform.isAndroid
            ? await getExternalStorageDirectory()
            : await getApplicationDocumentsDirectory()) ??
        Directory.systemTemp;
    final f = File(
      '${dir.path}/probe_${Platform.operatingSystem}_${DateTime.now().millisecondsSinceEpoch}.jsonl',
    );
    _file = f;
    final env = Platform.environment;
    _buf.writeln(
      jsonEncode({
        'meta': {
          'os': Platform.operatingSystem,
          'session': env['XDG_SESSION_TYPE'],
          'gdkBackend': env['GDK_BACKEND'],
          'dpr': WidgetsBinding
              .instance
              .platformDispatcher
              .views
              .first
              .devicePixelRatio,
        },
      }),
    );
    setState(() => _path = f.path);
  }

  void _log(String type, PointerEvent e) {
    _count++;
    _buf.writeln(
      jsonEncode({
        'phase': _phase,
        't': e.timeStamp.inMicroseconds,
        'type': type,
        'kind': e.kind.name,
        'device': e.device,
        'pointer': e.pointer,
        'buttons': e.buttons,
        'pos': [e.position.dx.round(), e.position.dy.round()],
        'pressure': e.pressure,
        'pressureMin': e.pressureMin,
        'pressureMax': e.pressureMax,
        'distance': e.distance,
        'distanceMax': e.distanceMax,
        'tilt': e.tilt,
        'orientation': e.orientation,
        'radiusMajor': e.radiusMajor,
        'radiusMinor': e.radiusMinor,
        'size': e.size,
      }),
    );
    _last =
        '$type ${e.kind.name} b=${e.buttons} p=${e.pressure.toStringAsFixed(2)} [${e.pressureMin.toStringAsFixed(1)}..${e.pressureMax.toStringAsFixed(1)}] d=${e.distance.toStringAsFixed(2)} tilt=${e.tilt.toStringAsFixed(2)} r=${e.radiusMajor.toStringAsFixed(1)}';
    if (type == 'down' || type == 'move') {
      _times.add(e.timeStamp.inMicroseconds);
      if (_times.length > 60) _times.removeAt(0);
      if (_times.length > 5) {
        final span = _times.last - _times.first;
        if (span > 0) _hz = (_times.length - 1) * 1e6 / span;
      }
    }
  }

  void _writeOut() {
    if (_file == null || _buf.isEmpty) return;
    _file!.writeAsStringSync(_buf.toString(), mode: FileMode.append);
    _buf.clear();
  }

  @override
  void dispose() {
    _flush?.cancel();
    _writeOut();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in _phases)
                    ChoiceChip(
                      label: Text(p),
                      selected: _phase == p,
                      onSelected: (_) => setState(() {
                        _phase = p;
                        _buf.writeln(jsonEncode({'phaseStart': p}));
                      }),
                    ),
                  OutlinedButton(
                    onPressed: () => setState(() {
                      _strokes.clear();
                      _active.clear();
                    }),
                    child: const Text('clear canvas'),
                  ),
                ],
              ),
            ),
            Text(
              'phase=$_phase  events=$_count  rate≈${_hz.toStringAsFixed(0)} Hz',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            Text(
              _last,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            Text(_path, style: const TextStyle(fontSize: 11)),
            Expanded(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) {
                  _log('down', e);
                  _active[e.pointer] = [e.localPosition];
                },
                onPointerMove: (e) {
                  _log('move', e);
                  _active[e.pointer]?.add(e.localPosition);
                },
                onPointerUp: (e) {
                  _log('up', e);
                  final s = _active.remove(e.pointer);
                  if (s != null) _strokes.add(s);
                },
                onPointerCancel: (e) {
                  _log('cancel', e);
                  _active.remove(e.pointer);
                },
                onPointerHover: (e) => _log('hover', e),
                onPointerSignal: (e) => _log('signal', e),
                onPointerPanZoomStart: (e) => _log('panZoomStart', e),
                onPointerPanZoomUpdate: (e) => _log('panZoomUpdate', e),
                onPointerPanZoomEnd: (e) => _log('panZoomEnd', e),
                child: CustomPaint(
                  painter: _P([..._strokes, ..._active.values]),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _P extends CustomPainter {
  _P(this.strokes);
  final List<List<Offset>> strokes;
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.black;
    for (final st in strokes) {
      if (st.length > 1) c.drawPoints(PointMode.polygon, st, p);
    }
  }

  @override
  bool shouldRepaint(_P o) => true;
}
