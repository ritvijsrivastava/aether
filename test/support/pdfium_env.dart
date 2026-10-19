import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart' show Pdfrx;

/// Real-pdfium tests need two things `flutter test` does not provide: the
/// native library (its native-asset hook does not run under test) and the
/// path_provider plugin (which pdfrx asks for a temp directory).
///
/// The library is taken from a previous `flutter build` (or `PDFIUM_PATH`).
String? pdfiumLibrary() {
  for (final p in [
    Platform.environment['PDFIUM_PATH'],
    'build/native_assets/linux/libpdfium.so',
  ]) {
    if (p != null && File(p).existsSync()) return File(p).absolute.path;
  }
  return null;
}

/// Why real-pdfium tests cannot run here, or null if they can.
String? pdfiumSkipReason(List<String> fixtures) {
  for (final f in fixtures) {
    if (!File(f).existsSync()) {
      return 'fixture $f not present (see docs/m2.md to generate)';
    }
  }
  if (pdfiumLibrary() == null) {
    return 'no libpdfium.so (run flutter build linux once, or set PDFIUM_PATH)';
  }
  return null;
}

/// Call from `setUpAll`.
void setUpPdfium() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final lib = pdfiumLibrary();
  if (lib != null) Pdfrx.pdfiumModulePath = lib;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => Directory.systemTemp.path,
      );
}
