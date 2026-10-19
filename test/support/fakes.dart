import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:aether/data/pdf/pdf_password_cache.dart';
import 'package:aether/features/canvas/pdf/pdf_source.dart';
import 'package:aether/features/library/import/pdf_importer.dart';
import 'package:aether/features/library/import/pdf_inspector.dart';
import 'package:aether/features/library/import/pdf_picker.dart';

/// An inspector that never touches pdfium.
class FakeInspector implements PdfInspector {
  FakeInspector({
    this.pages = const [Size(612, 792), Size(612, 792), Size(792, 612)],
    this.failure,
    this.password,
    this.thumbnail = true,
  });

  final List<Size> pages;

  /// Throw this from every call.
  PdfOpenException? failure;

  /// If set, the file "needs" this password.
  final String? password;
  final bool thumbnail;
  final List<String> inspected = [];
  int passwordPrompts = 0;

  @override
  Future<PdfInfo> inspect(String path, {PasswordProvider? password}) async {
    inspected.add(path);
    if (failure != null) throw failure!;
    final needed = this.password;
    if (needed != null) {
      var given = await password?.call();
      passwordPrompts++;
      while (given != needed) {
        if (given == null) throw PdfOpenException(PdfOpenFailure.password);
        given = await password!();
        passwordPrompts++;
      }
    }
    return PdfInfo(
      pageSizes: pages,
      thumbnailPng: thumbnail ? Uint8List.fromList([137, 80, 78, 71]) : null,
    );
  }
}

class FakePicker implements PdfPicker {
  FakePicker([this.next = const []]);
  List<ImportRequest> next;
  int calls = 0;

  @override
  Future<List<ImportRequest>> pick() async {
    calls++;
    return next;
  }
}

/// Writes a small file whose content depends on [seed], so different seeds
/// have different hashes. It is not a real PDF (use with [FakeInspector]).
File writeFakePdf(Directory dir, String name, {String seed = 'a'}) {
  final f = File('${dir.path}/$name')
    ..writeAsStringSync('%PDF-1.4 fake $seed\n' * 20);
  return f;
}
