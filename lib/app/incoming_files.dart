import 'dart:async';

import '../features/library/import/pdf_importer.dart';
import '../features/library/import/pdf_picker.dart';

/// PDFs sent to the app from elsewhere on Android ("Open with", "Share to").
/// The native side copies each to a temporary file and tells us its path; we
/// say `ready` once listening so nothing sent at launch is lost.
class IncomingFiles {
  IncomingFiles._();

  /// Emits every PDF sent to the app, including one that launched it.
  static Stream<ImportRequest> stream() {
    final controller = StreamController<ImportRequest>();
    AndroidFiles.channel.setMethodCallHandler((call) async {
      if (call.method == 'file' && call.arguments is String) {
        controller.add(
          ImportRequest(call.arguments as String, deleteSourceAfter: true),
        );
      }
    });
    AndroidFiles.channel.invokeMethod<void>('ready');
    return controller.stream;
  }
}
