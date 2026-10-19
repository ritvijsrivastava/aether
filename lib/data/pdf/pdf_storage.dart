import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// A file copied into storage but not yet committed under its hash.
class StoredCopy {
  const StoredCopy({
    required this.tempPath,
    required this.hash,
    required this.bytes,
  });
  final String tempPath;

  /// SHA-256 of the content, lowercase hex.
  final String hash;
  final int bytes;
}

/// Imported PDFs, content-addressed: `pdfs/<sha256>.pdf`.
///
/// The same file imported twice is stored once. Everything the app needs to
/// rebuild is the hash in a document's `sourceHash` field; the original file
/// can move or vanish without affecting the library.
class PdfStorage {
  PdfStorage(this.root);

  /// Creates [root] and its subfolders if needed.
  static Future<PdfStorage> open(Directory root) async {
    final s = PdfStorage(root);
    await s._pdfDir.create(recursive: true);
    await s._thumbDir.create(recursive: true);
    return s;
  }

  final Directory root;
  Directory get _pdfDir => Directory(p.join(root.path, 'pdfs'));
  Directory get _thumbDir => Directory(p.join(root.path, 'thumbs'));

  String pdfPath(String hash) => p.join(_pdfDir.path, '$hash.pdf');
  String thumbnailPath(String hash) => p.join(_thumbDir.path, '$hash.png');

  bool hasPdf(String hash) => File(pdfPath(hash)).existsSync();

  int _tmpCounter = 0;

  /// Streams [source] into a temporary file while hashing it, in one pass.
  /// Deletes the partial file if the stream fails.
  Future<StoredCopy> copyIn(Stream<List<int>> source) async {
    final tmp = File(
      p.join(
        _pdfDir.path,
        '.incoming-$pid-${DateTime.now().microsecondsSinceEpoch}-${_tmpCounter++}.part',
      ),
    );
    final sink = _DigestSink();
    final hasher = sha256.startChunkedConversion(sink);
    var bytes = 0;
    final out = tmp.openWrite();
    try {
      await out.addStream(
        source.map((chunk) {
          hasher.add(chunk);
          bytes += chunk.length;
          return chunk;
        }),
      );
      await out.flush();
      await out.close();
      hasher.close();
    } catch (_) {
      try {
        await out.close();
      } catch (_) {}
      if (tmp.existsSync()) await tmp.delete();
      rethrow;
    }
    return StoredCopy(
      tempPath: tmp.path,
      hash: sink.value!.toString(),
      bytes: bytes,
    );
  }

  /// Moves [copy] into place under its hash (atomically). If a file with that
  /// hash already exists the temporary copy is simply dropped. Returns the
  /// final path.
  Future<String> commit(StoredCopy copy) async {
    final dest = pdfPath(copy.hash);
    final tmp = File(copy.tempPath);
    if (File(dest).existsSync()) {
      if (tmp.existsSync()) await tmp.delete();
    } else {
      await tmp.rename(dest);
    }
    return dest;
  }

  /// Drops a copy that was never committed.
  Future<void> discard(StoredCopy copy) async {
    final f = File(copy.tempPath);
    if (f.existsSync()) await f.delete();
  }

  Future<void> writeThumbnail(String hash, Uint8List png) =>
      File(thumbnailPath(hash)).writeAsBytes(png, flush: true);

  /// Removes a stored PDF and its thumbnail.
  Future<void> delete(String hash) async {
    for (final path in [pdfPath(hash), thumbnailPath(hash)]) {
      final f = File(path);
      if (f.existsSync()) await f.delete();
    }
  }

  /// Removes leftover partial copies from an interrupted import.
  Future<int> sweepPartials() async {
    var n = 0;
    await for (final e in _pdfDir.list()) {
      if (e is File && e.path.endsWith('.part')) {
        await e.delete();
        n++;
      }
    }
    return n;
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
