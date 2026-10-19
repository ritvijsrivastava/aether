import 'dart:io' show Platform;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

import 'pdf_importer.dart';

/// Lets the user choose PDFs from the system.
abstract interface class PdfPicker {
  /// The chosen files; empty if the user cancelled.
  Future<List<ImportRequest>> pick();
}

/// Linux: the native GTK dialog, through `file_selector`.
class DesktopPdfPicker implements PdfPicker {
  const DesktopPdfPicker();

  static const _pdf = XTypeGroup(
    label: 'PDF documents',
    extensions: ['pdf'],
    mimeTypes: ['application/pdf'],
  );

  @override
  Future<List<ImportRequest>> pick() async {
    final files = await openFiles(acceptedTypeGroups: const [_pdf]);
    return [for (final f in files) ImportRequest(f.path)];
  }
}

/// Android: the system document picker, run natively (see MainActivity), which
/// streams each choice into a temporary file. `file_selector_android` would
/// load the whole file into memory first.
class AndroidPdfPicker implements PdfPicker {
  const AndroidPdfPicker();

  @override
  Future<List<ImportRequest>> pick() async {
    final paths =
        await AndroidFiles.channel.invokeListMethod<String>('pickPdfs') ??
        const [];
    return [for (final p in paths) ImportRequest(p, deleteSourceAfter: true)];
  }
}

/// The native side of file handling on Android: the picker, and PDFs sent to
/// the app from elsewhere ("Open with", "Share to").
abstract final class AndroidFiles {
  static const channel = MethodChannel('com.ritvijsrivastava.aether/files');
}

PdfPicker platformPdfPicker() =>
    Platform.isAndroid ? const AndroidPdfPicker() : const DesktopPdfPicker();
