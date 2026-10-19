import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../canvas/pdf/pdf_source.dart';
import 'password_dialog.dart';
import 'pdf_importer.dart';

/// Progress of the imports currently running, for the library to show.
class ImportProgress {
  const ImportProgress({this.total = 0, this.done = 0, this.current});
  final int total, done;
  final String? current;
  bool get active => total > 0;
}

class ImportProgressNotifier extends Notifier<ImportProgress> {
  @override
  ImportProgress build() => const ImportProgress();
  void set(ImportProgress p) => state = p;
}

final importProgressProvider =
    NotifierProvider<ImportProgressNotifier, ImportProgress>(
      ImportProgressNotifier.new,
    );

/// Imports [requests] one after another, asking for passwords when needed,
/// then reports the outcome and opens the document if exactly one was brought
/// in. Safe to call from anywhere there is a [context] under the router
/// (picker, drag and drop, or a file sent to the app).
Future<void> runImport({
  required BuildContext context,
  required WidgetRef ref,
  required List<ImportRequest> requests,
}) async {
  if (requests.isEmpty) return;
  final progress = ref.read(importProgressProvider.notifier);
  final importer = ref.read(pdfImporterProvider);
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);

  final results = <ImportResult>[];
  final failures = <String>[];
  for (var i = 0; i < requests.length; i++) {
    final req = requests[i];
    progress.set(
      ImportProgress(total: requests.length, done: i, current: req.displayName),
    );
    var attempts = 0;
    try {
      results.add(
        await importer.import(
          req,
          password: () => !context.mounted
              ? Future.value(null)
              : showPdfPasswordDialog(
                  context,
                  fileName: req.displayName,
                  retry: attempts++ > 0,
                ),
        ),
      );
    } on PdfOpenException catch (e) {
      failures.add('${req.displayName}: ${e.message}');
    } catch (e, st) {
      debugPrint('Import of ${req.path} failed: $e\n$st');
      failures.add('${req.displayName}: it could not be imported.');
    }
  }
  progress.set(const ImportProgress());
  ref.invalidate(documentsProvider);
  ref.invalidate(libraryItemsProvider);

  final created = results.where((r) => r.created).length;
  final parts = <String>[];
  if (results.length == 1 && failures.isEmpty) {
    if (!results.single.created) {
      parts.add('Already in your library. Opened it.');
    }
  } else {
    if (created > 0) {
      parts.add(created == 1 ? 'Imported 1 PDF.' : 'Imported $created PDFs.');
    }
    final reused = results.length - created;
    if (reused > 0) parts.add('$reused already in your library.');
  }
  if (failures.isNotEmpty) {
    parts.add(
      failures.length == 1
          ? "Couldn't import ${failures.single}"
          : "Couldn't import ${failures.length} files: ${failures.first}",
    );
  }
  if (parts.isNotEmpty) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(parts.join('\n'))));
  }
  if (results.length == 1 && failures.isEmpty) {
    router.push('/doc/${results.single.docId}');
  }
}
