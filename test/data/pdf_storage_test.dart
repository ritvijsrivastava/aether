import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aether/data/pdf/pdf_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late PdfStorage storage;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('aether_storage_');
    storage = await PdfStorage.open(root);
  });
  tearDown(() => root.delete(recursive: true));

  Stream<List<int>> bytes(String s, {int chunk = 7}) async* {
    final b = utf8.encode(s);
    for (var i = 0; i < b.length; i += chunk) {
      yield b.sublist(i, i + chunk > b.length ? b.length : i + chunk);
    }
  }

  test('open creates the folders', () {
    expect(Directory('${root.path}/pdfs').existsSync(), isTrue);
    expect(Directory('${root.path}/thumbs').existsSync(), isTrue);
  });

  test(
    'copyIn hashes while copying, in one pass, across chunk sizes',
    () async {
      final content =
          'The quick brown fox jumps over the lazy dog. ${'0123456789' * 400}';
      for (final chunk in [1, 7, 4096, 100000]) {
        final copy = await storage.copyIn(bytes(content, chunk: chunk));
        expect(
          copy.hash,
          sha256.convert(utf8.encode(content)).toString(),
          reason: 'chunk $chunk',
        );
        expect(copy.bytes, utf8.encode(content).length);
        expect(File(copy.tempPath).readAsStringSync(), content);
        await storage.discard(copy);
      }
    },
  );

  test('commit moves the copy under its hash', () async {
    final copy = await storage.copyIn(bytes('hello'));
    final path = await storage.commit(copy);
    expect(path, storage.pdfPath(copy.hash));
    expect(File(path).readAsStringSync(), 'hello');
    expect(File(copy.tempPath).existsSync(), isFalse);
    expect(storage.hasPdf(copy.hash), isTrue);
  });

  test('the same content is stored once', () async {
    final a = await storage.copyIn(bytes('same'));
    await storage.commit(a);
    final b = await storage.copyIn(bytes('same'));
    expect(b.hash, a.hash);
    await storage.commit(b);
    expect(
      File(b.tempPath).existsSync(),
      isFalse,
      reason: 'the duplicate temp copy is dropped',
    );
    final stored = Directory('${root.path}/pdfs')
        .listSync()
        .whereType<File>()
        .toList();
    expect(stored.length, 1);
  });

  test('a failing stream leaves no partial file behind and rethrows', () async {
    Stream<List<int>> broken() async* {
      yield utf8.encode('partial');
      throw const FileSystemException('disk gone');
    }

    await expectLater(
      storage.copyIn(broken()),
      throwsA(isA<FileSystemException>()),
    );
    expect(Directory('${root.path}/pdfs').listSync(), isEmpty);
  });

  test('discard removes an uncommitted copy', () async {
    final copy = await storage.copyIn(bytes('x'));
    await storage.discard(copy);
    expect(File(copy.tempPath).existsSync(), isFalse);
    await storage.discard(copy); // harmless twice
  });

  test('thumbnails are written and removed with the PDF', () async {
    final copy = await storage.copyIn(bytes('doc'));
    await storage.commit(copy);
    await storage.writeThumbnail(copy.hash, Uint8List.fromList([1, 2, 3]));
    expect(File(storage.thumbnailPath(copy.hash)).readAsBytesSync(), [1, 2, 3]);
    await storage.delete(copy.hash);
    expect(storage.hasPdf(copy.hash), isFalse);
    expect(File(storage.thumbnailPath(copy.hash)).existsSync(), isFalse);
  });

  test(
    'sweepPartials clears leftovers of an interrupted import only',
    () async {
      File('${root.path}/pdfs/.incoming-1-2-3.part').writeAsStringSync('half');
      final done = await storage.copyIn(bytes('complete'));
      await storage.commit(done);
      expect(await storage.sweepPartials(), 1);
      expect(storage.hasPdf(done.hash), isTrue);
    },
  );

  test('concurrent copies do not collide', () async {
    final copies = await Future.wait([
      for (var i = 0; i < 8; i++) storage.copyIn(bytes('doc $i ' * 100)),
    ]);
    expect(copies.map((c) => c.tempPath).toSet().length, 8);
    expect(copies.map((c) => c.hash).toSet().length, 8);
  });
}
