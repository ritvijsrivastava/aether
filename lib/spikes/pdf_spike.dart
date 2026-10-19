// THROWAWAY (M0 spike): headless check of pdfrx + Drift on the current platform.
// Run: flutter run -d linux -t lib/spikes/pdf_spike.dart \
//   --dart-define=PDF=<abs path> --dart-define=OUT=<abs report path>
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

import 'spike_db.dart';

const _pdf = String.fromEnvironment('PDF');
const _out = String.fromEnvironment('OUT');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();
  final r = <String, Object?>{'platform': Platform.operatingSystem};
  try {
    r['pdf'] = await _pdfSpike();
  } catch (e, s) {
    r['pdfError'] = '$e\n$s';
  }
  try {
    r['drift'] = await _driftSpike();
  } catch (e, s) {
    r['driftError'] = '$e\n$s';
  }
  final json = const JsonEncoder.withIndent('  ').convert(r);
  debugPrint('SPIKE_REPORT_BEGIN\n$json\nSPIKE_REPORT_END');
  if (_out.isNotEmpty) File(_out).writeAsStringSync(json);
  exit(0);
}

Future<Map<String, Object?>> _pdfSpike() async {
  var prompts = 0;
  final sw = Stopwatch()..start();
  final doc = await PdfDocument.openFile(
    _pdf,
    passwordProvider: () {
      prompts++;
      return null;
    },
  );
  final res = <String, Object?>{
    'openMs': sw.elapsedMilliseconds,
    'passwordPrompts': prompts,
    'pageCount': doc.pages.length,
  };
  final p1 = doc.pages[0];
  res['page1Size'] = [p1.width, p1.height];

  final renders = <Map<String, Object?>>[];
  for (final scale in [1.0, 3.0]) {
    sw
      ..reset()
      ..start();
    final img = await p1.render(
      fullWidth: p1.width * scale,
      fullHeight: p1.height * scale,
    );
    renders.add({
      'scale': scale,
      'ms': sw.elapsedMilliseconds,
      'px': img == null ? null : [img.width, img.height],
    });
    img?.dispose();
  }
  res['renders'] = renders;

  // Tile-style partial render: 512px square from the middle at 3x.
  sw
    ..reset()
    ..start();
  final tile = await p1.render(
    x: 600,
    y: 900,
    width: 512,
    height: 512,
    fullWidth: p1.width * 3,
    fullHeight: p1.height * 3,
  );
  res['tile512Ms'] = sw.elapsedMilliseconds;
  res['tilePx'] = tile == null ? null : [tile.width, tile.height];
  tile?.dispose();

  // Text layer.
  sw
    ..reset()
    ..start();
  final t = await p1.loadText();
  res['loadTextMs'] = sw.elapsedMilliseconds;
  if (t != null) {
    res['textChars'] = t.fullText.length;
    res['charRects'] = t.charRects.length;
    final i = t.fullText.indexOf('MapReduce');
    if (i >= 0) {
      final a = t.charRects[i], b = t.charRects[i + 8];
      res['firstMapReduce'] = {
        'index': i,
        'firstCharRect': [a.left, a.top, a.right, a.bottom],
        'lastCharRect': [b.left, b.top, b.right, b.bottom],
      };
    }
  }

  // Reading order on a two-column body page (page 2): first 40 fragments.
  sw
    ..reset()
    ..start();
  final t2 = await doc.pages[1].loadStructuredText();
  res['structuredTextMs'] = sw.elapsedMilliseconds;
  res['page2Fragments'] = t2.fragments.length;
  {
    // One entry per visual line start, in the order the engine returns them.
    final starts = <Map<String, Object?>>[];
    double? lastY;
    for (final f in t2.fragments) {
      if (f.text.trim().isEmpty) continue;
      if (lastY == null || (f.bounds.top - lastY).abs() > 3) {
        starts.add({
          'x': f.bounds.left.round(),
          'yTop': f.bounds.top.round(),
          'text': f.text,
        });
      }
      lastY = f.bounds.top;
    }
    res['page2LineStarts'] = starts;
  }
  await doc.dispose();
  return res;
}

Future<Map<String, Object?>> _driftSpike() async {
  final db = SpikeDb(NativeDatabase.memory());
  await db
      .into(db.marks)
      .insert(
        MarksCompanion.insert(
          id: 'm1',
          kind: 'ink',
          payload: Uint8List.fromList([1, 2, 3]),
        ),
      );
  final rows = await db.select(db.marks).get();
  final v = await db.customSelect('select sqlite_version() as v').getSingle();
  await db.close();
  return {'rows': rows.length, 'sqliteVersion': v.read<String>('v')};
}
