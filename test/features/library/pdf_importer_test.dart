import 'dart:io';

import 'package:aether/core/hlc/hlc.dart';
import 'package:aether/core/id/id_generator.dart';
import 'package:aether/data/db/database.dart';
import 'package:aether/data/db/drift_op_store.dart';
import 'package:aether/data/pdf/pdf_storage.dart';
import 'package:aether/domain/commands/command.dart';
import 'package:aether/domain/commands/command_bus.dart';
import 'package:aether/domain/model/models.dart';
import 'package:aether/domain/ops/op.dart';
import 'package:aether/features/canvas/pdf/pdf_source.dart';
import 'package:aether/features/library/import/pdf_importer.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory tmp;
  late Directory sources;
  late AetherDatabase db;
  late DriftOpStore store;
  late PdfStorage storage;
  late CommandBus bus;
  late FakeInspector inspector;
  late PdfImporter importer;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('aether_import_');
    sources = await Directory('${tmp.path}/src').create();
    db = AetherDatabase(NativeDatabase.memory());
    store = DriftOpStore(db);
    storage = await PdfStorage.open(Directory('${tmp.path}/lib'));
    var t = 1000;
    bus = CommandBus(
      store: store,
      clock: HlcClock('dev', now: () => t++),
      ids: SequentialIdGenerator('b'),
    );
    inspector = FakeInspector();
    importer = PdfImporter(
      store: store,
      bus: bus,
      storage: storage,
      inspector: inspector,
      db: db,
      ids: SequentialIdGenerator('doc'),
      now: () => DateTime.utc(2026, 10, 19, 12),
    );
  });
  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  Future<List<Document>> documents() async => [
    for (final e in await store.entities(kind: EntityKind.document))
      Document.fromState(e),
  ];
  Future<List<PageRef>> pagesOf(String docId) async => [
    for (final e in await store.entities(kind: EntityKind.page, docId: docId))
      PageRef.fromState(e),
  ]..sort((a, b) => a.index.compareTo(b.index));

  test(
    'imports a PDF: stores it by hash, creates the document and its pages',
    () async {
      final src = writeFakePdf(sources, 'My Paper.pdf');
      final r = await importer.import(ImportRequest(src.path));

      expect(r.created, isTrue);
      expect(r.title, 'My Paper');
      final docs = await documents();
      expect(docs.length, 1);
      expect(docs.single.title, 'My Paper');
      expect(docs.single.pageCount, 3);
      expect(storage.hasPdf(docs.single.sourceHash), isTrue);
      expect(
        File(storage.pdfPath(docs.single.sourceHash)).readAsStringSync(),
        src.readAsStringSync(),
      );
      expect(
        src.existsSync(),
        isTrue,
        reason: 'the user\'s file is left alone',
      );
    },
  );

  test(
    'pages are laid out in one column, centred, with their real sizes',
    () async {
      final r = await importer.import(
        ImportRequest(writeFakePdf(sources, 'a.pdf').path),
      );
      final pages = await pagesOf(r.docId);
      expect(pages.length, 3);
      expect(pages.map((p) => p.index), [0, 1, 2]);
      expect(pages[0].cardY, 0);
      expect(pages[1].cardY, 792 + 80);
      expect(pages[2].cardY, 792 + 80 + 792 + 80);
      // The landscape page is wider, so the portrait pages are centred on it.
      expect(pages[2].width, 792);
      expect(pages[0].cardX, (792 - 612) / 2);
      expect(pages[2].cardX, 0);
      expect(pages.every((p) => p.docId == r.docId), isTrue);
    },
  );

  test('records the stored file and writes a thumbnail', () async {
    final r = await importer.import(
      ImportRequest(writeFakePdf(sources, 'a.pdf').path),
    );
    final hash = (await documents()).single.sourceHash;
    final row = await db.pdfFile(hash);
    expect(row, isNotNull);
    expect(row!.path, storage.pdfPath(hash));
    expect(
      row.importedAt,
      DateTime.utc(2026, 10, 19, 12).millisecondsSinceEpoch,
    );
    expect(File(storage.thumbnailPath(hash)).readAsBytesSync(), [
      137,
      80,
      78,
      71,
    ]);
    expect(r.created, isTrue);
  });

  test('a missing thumbnail does not fail the import', () async {
    inspector = FakeInspector(thumbnail: false);
    importer = PdfImporter(
      store: store,
      bus: bus,
      storage: storage,
      inspector: inspector,
      db: db,
      ids: SequentialIdGenerator('doc'),
    );
    final r = await importer.import(
      ImportRequest(writeFakePdf(sources, 'a.pdf').path),
    );
    expect(r.created, isTrue);
    final hash = (await documents()).single.sourceHash;
    expect(File(storage.thumbnailPath(hash)).existsSync(), isFalse);
  });

  test(
    'the same file again opens the existing document and adds nothing',
    () async {
      final first = await importer.import(
        ImportRequest(writeFakePdf(sources, 'a.pdf').path),
      );
      final again = await importer.import(
        ImportRequest(writeFakePdf(sources, 'a.pdf').path),
      );
      expect(again.created, isFalse);
      expect(again.docId, first.docId);
      expect((await documents()).length, 1);
      expect(
        (await pagesOf(first.docId)).length,
        3,
        reason: 'no duplicate pages',
      );
      expect(
        inspector.inspected.length,
        1,
        reason: 'not even opened a second time',
      );
      expect(
        Directory('${tmp.path}/lib/pdfs').listSync().whereType<File>().length,
        1,
      );
    },
  );

  test(
    'the same bytes under another name are still the same document',
    () async {
      final first = await importer.import(
        ImportRequest(writeFakePdf(sources, 'paper.pdf').path),
      );
      final renamed = await importer.import(
        ImportRequest(writeFakePdf(sources, 'copy of paper (1).pdf').path),
      );
      expect(renamed.docId, first.docId);
      expect(renamed.created, isFalse);
    },
  );

  test('different files become different documents', () async {
    final a = await importer.import(
      ImportRequest(writeFakePdf(sources, 'a.pdf', seed: 'one').path),
    );
    final b = await importer.import(
      ImportRequest(writeFakePdf(sources, 'b.pdf', seed: 'two').path),
    );
    expect(a.docId, isNot(b.docId));
    expect((await documents()).length, 2);
  });

  test(
    'an unopenable file leaves the library untouched and the copy removed',
    () async {
      inspector.failure = PdfOpenException(PdfOpenFailure.unreadable);
      await expectLater(
        importer.import(ImportRequest(writeFakePdf(sources, 'bad.pdf').path)),
        throwsA(
          isA<PdfOpenException>().having(
            (e) => e.failure,
            'failure',
            PdfOpenFailure.unreadable,
          ),
        ),
      );
      expect(await documents(), isEmpty);
      expect(
        Directory('${tmp.path}/lib/pdfs').listSync(),
        isEmpty,
        reason: 'no stored copy, no partial',
      );
      expect(await store.allOps(), isEmpty);
    },
  );

  test(
    'a file that needs a password asks for it and opens with the right one',
    () async {
      inspector = FakeInspector(password: 'hunter2');
      importer = PdfImporter(
        store: store,
        bus: bus,
        storage: storage,
        inspector: inspector,
        db: db,
        ids: SequentialIdGenerator('doc'),
      );
      final answers = ['wrong', 'hunter2'];
      final r = await importer.import(
        ImportRequest(writeFakePdf(sources, 'locked.pdf').path),
        password: () async => answers.removeAt(0),
      );
      expect(r.created, isTrue);
      expect(inspector.passwordPrompts, 2);
    },
  );

  test(
    'giving up on the password rejects the file and keeps nothing',
    () async {
      inspector = FakeInspector(password: 'hunter2');
      importer = PdfImporter(
        store: store,
        bus: bus,
        storage: storage,
        inspector: inspector,
        db: db,
        ids: SequentialIdGenerator('doc'),
      );
      await expectLater(
        importer.import(
          ImportRequest(writeFakePdf(sources, 'locked.pdf').path),
          password: () async => null,
        ),
        throwsA(
          isA<PdfOpenException>().having(
            (e) => e.failure,
            'failure',
            PdfOpenFailure.password,
          ),
        ),
      );
      expect(await documents(), isEmpty);
      expect(Directory('${tmp.path}/lib/pdfs').listSync(), isEmpty);
    },
  );

  test(
    'a failed re-import keeps the file that a deleted document still refers to',
    () async {
      final first = await importer.import(
        ImportRequest(writeFakePdf(sources, 'a.pdf').path),
      );
      final hash = (await documents()).single.sourceHash;
      await bus.run(await CommandFactory(store).delete(first.docId));
      expect(await documents(), isEmpty);
      // Importing it again while it cannot be opened must not delete the blob
      // that Undo of the delete would need.
      inspector.failure = PdfOpenException(PdfOpenFailure.unreadable);
      await expectLater(
        importer.import(ImportRequest(writeFakePdf(sources, 'a.pdf').path)),
        throwsA(isA<PdfOpenException>()),
      );
      expect(storage.hasPdf(hash), isTrue);
    },
  );

  /// A temporary copy as the Android side makes it: alone in its own folder.
  File tempCopy(String name, String seed) {
    final dir = Directory('${sources.path}/incoming-$seed')..createSync();
    return writeFakePdf(dir, name, seed: seed);
  }

  test(
    'a temporary source is removed after import, success or failure',
    () async {
      final ok = tempCopy('tmp-ok.pdf', 'ok');
      await importer.import(ImportRequest(ok.path, deleteSourceAfter: true));
      expect(ok.existsSync(), isFalse);

      inspector.failure = PdfOpenException(PdfOpenFailure.unreadable);
      final bad = tempCopy('tmp-bad.pdf', 'bad');
      await expectLater(
        importer.import(ImportRequest(bad.path, deleteSourceAfter: true)),
        throwsA(isA<PdfOpenException>()),
      );
      expect(bad.existsSync(), isFalse);

      // A file the user chose is never touched.
      final keep = writeFakePdf(sources, 'keep.pdf', seed: 'keep');
      inspector.failure = null;
      await importer.import(ImportRequest(keep.path));
      expect(keep.existsSync(), isTrue);
    },
  );

  test("a temporary copy's own folder is removed with it", () async {
    final f = tempCopy('Tmp Paper.pdf', 'folder');
    final r = await importer.import(
      ImportRequest(f.path, deleteSourceAfter: true),
    );
    expect(
      r.title,
      'Tmp Paper',
      reason: 'the title comes from the real file name',
    );
    expect(f.parent.existsSync(), isFalse);
  });

  test(
    'only an empty folder is removed, never one with other files in it',
    () async {
      final folder = await Directory('${sources.path}/shared').create();
      final f = writeFakePdf(folder, 'a.pdf', seed: 'shared');
      final other = writeFakePdf(folder, 'other.pdf', seed: 'other');
      await importer.import(ImportRequest(f.path, deleteSourceAfter: true));
      expect(f.existsSync(), isFalse);
      expect(other.existsSync(), isTrue);
      expect(folder.existsSync(), isTrue);
    },
  );

  test(
    'a missing source file fails cleanly without leaving anything behind',
    () async {
      await expectLater(
        importer.import(ImportRequest('${sources.path}/nope.pdf')),
        throwsA(isA<FileSystemException>()),
      );
      expect(Directory('${tmp.path}/lib/pdfs').listSync(), isEmpty);
      expect(await documents(), isEmpty);
    },
  );

  test(
    'importing is one undoable step that hides the document, pages included',
    () async {
      final r = await importer.import(
        ImportRequest(writeFakePdf(sources, 'a.pdf').path),
      );
      expect((await documents()).length, 1);
      expect(await bus.undo(), isTrue);
      expect(await documents(), isEmpty);
      expect(await bus.redo(), isTrue);
      expect((await documents()).single.id, r.docId);
    },
  );

  test(
    'titles come from the file name without its extension; odd names survive',
    () async {
      for (final (name, title) in [
        ('Report v2.PDF', 'Report v2'),
        ('.pdf', 'Untitled'),
        ('a.b.c.pdf', 'a.b.c'),
      ]) {
        final r = await importer.import(
          ImportRequest(writeFakePdf(sources, name, seed: name).path),
        );
        expect(r.title, title, reason: name);
      }
    },
  );
}
