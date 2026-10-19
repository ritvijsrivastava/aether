import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

import '../../../data/pdf/pdf_password_cache.dart';
import '../../canvas/pdf/pdf_source.dart';

/// What the importer needs to know about a PDF.
class PdfInfo {
  const PdfInfo({required this.pageSizes, this.thumbnailPng});

  /// Each page's size in points.
  final List<ui.Size> pageSizes;

  /// First page as a small PNG for the library, if it could be rendered.
  final Uint8List? thumbnailPng;
}

/// Opens a PDF far enough to validate it and describe it.
abstract interface class PdfInspector {
  /// Throws [PdfOpenException] if the file cannot be opened (including when a
  /// password is needed and [password] gives none).
  Future<PdfInfo> inspect(String path, {PasswordProvider? password});
}

/// The real inspector, on pdfium.
class PdfiumInspector implements PdfInspector {
  const PdfiumInspector({this.thumbnailWidth = 360});

  final int thumbnailWidth;

  @override
  Future<PdfInfo> inspect(String path, {PasswordProvider? password}) async {
    final pdf = await openPdfFile(path, password: password);
    try {
      if (pdf.pageSizes.isEmpty) {
        throw PdfOpenException(PdfOpenFailure.unreadable, 'no pages');
      }
      return PdfInfo(
        pageSizes: pdf.pageSizes,
        thumbnailPng: await _thumbnail(pdf.document.pages.first),
      );
    } finally {
      await pdf.dispose();
    }
  }

  Future<Uint8List?> _thumbnail(PdfPage page) async {
    PdfImage? raw;
    try {
      final w = thumbnailWidth.toDouble();
      raw = await page.render(
        fullWidth: w,
        fullHeight: w * page.height / page.width,
        backgroundColor: 0xffffffff,
      );
      if (raw == null) return null;
      final image = await raw.createImage();
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data?.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } catch (_) {
      return null; // a missing thumbnail must never fail an import
    } finally {
      raw?.dispose();
    }
  }
}
