import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the bundled fonts so tests and goldens use real glyph metrics.
/// Without this, flutter_test falls back to the Ahem placeholder font, whose
/// glyphs are far wider than Figtree and produce false overflow failures.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _load('Figtree', [
    for (final w in [400, 500, 600, 700]) 'assets/fonts/Figtree-$w.ttf',
  ]);
  await _load('SourceSerif4', [
    for (final w in [400, 600, 700]) 'assets/fonts/SourceSerif4-$w.ttf',
  ]);
  await testMain();
}

Future<void> _load(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    final bytes = File(p).readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}
