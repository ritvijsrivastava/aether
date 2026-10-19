import 'dart:ui' show Size;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:pdfrx/pdfrx.dart';

import '../../../data/pdf/pdf_password_cache.dart';

enum PdfOpenFailure {
  /// Needs a password we do not have.
  password,

  /// Missing, corrupt, or not a PDF.
  unreadable,
}

class PdfOpenException implements Exception {
  PdfOpenException(this.failure, [this.cause]);
  final PdfOpenFailure failure;
  final Object? cause;

  String get message => switch (failure) {
    PdfOpenFailure.password => 'This PDF is password protected.',
    PdfOpenFailure.unreadable => 'This file could not be opened as a PDF.',
  };

  @override
  String toString() => 'PdfOpenException($failure, $cause)';
}

/// An open document and the size of each page in points.
class OpenedPdf {
  OpenedPdf(this.document)
    : pageSizes = [for (final p in document.pages) Size(p.width, p.height)];

  final PdfDocument document;
  final List<Size> pageSizes;

  Future<void> dispose() => document.dispose();
}

/// Opens [path]. Files that are encrypted but have an empty user password
/// (copying allowed, editing not) open silently. A real user password is
/// requested from [password] (repeatedly, while it is wrong); with none given,
/// or if the user gives up, this raises [PdfOpenFailure.password].
Future<OpenedPdf> openPdfFile(String path, {PasswordProvider? password}) async {
  try {
    await pdfrxFlutterInitialize();
    final doc = await PdfDocument.openFile(
      path,
      passwordProvider: password ?? () => null,
    );
    return OpenedPdf(doc);
  } on PdfPasswordException catch (e) {
    throw PdfOpenException(PdfOpenFailure.password, e);
  } catch (e) {
    debugPrint('Could not open $path: $e');
    throw PdfOpenException(PdfOpenFailure.unreadable, e);
  }
}
