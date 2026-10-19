import 'dart:ui' show Size;

import 'package:pdfrx/pdfrx.dart';

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
/// (copying allowed, editing not) open silently; a real user password raises
/// [PdfOpenFailure.password] until a prompt exists.
Future<OpenedPdf> openPdfFile(String path) async {
  await pdfrxFlutterInitialize();
  try {
    final doc = await PdfDocument.openFile(path, passwordProvider: () => null);
    return OpenedPdf(doc);
  } on PdfPasswordException catch (e) {
    throw PdfOpenException(PdfOpenFailure.password, e);
  } catch (e) {
    throw PdfOpenException(PdfOpenFailure.unreadable, e);
  }
}
