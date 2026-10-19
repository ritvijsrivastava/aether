import 'dart:io';
import 'dart:ui' show Size;

import 'package:aether/core/hlc/hlc.dart';
import 'package:aether/core/id/id_generator.dart';
import 'package:aether/data/db/database.dart';
import 'package:aether/data/db/drift_op_store.dart';
import 'package:aether/data/pdf/pdf_storage.dart';
import 'package:aether/domain/commands/command_bus.dart';
import 'package:aether/domain/model/models.dart';
import 'package:aether/domain/ops/op.dart';
import 'package:aether/features/canvas/pdf/pdf_source.dart';
import 'package:aether/features/library/import/pdf_importer.dart';
import 'package:aether/features/library/import/pdf_inspector.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pdfium_env.dart';

/// The importer against real pdfium and real PDFs. Fixtures are third-party or
/// generated from one, live under the git-ignored test/fixtures, and these
/// tests skip with a reason if they are missing:
///   mapreduce/mapreduce.pdf   13 pages, owner-password only
///   generated/locked.pdf      13 pages, user password "secret"
///   generated/big200.pdf      208 pages;  generated/big500.pdf  507 pages
///   generated/fake.pdf        a text file named .pdf
const _paper = 'test/fixtures/mapreduce/mapreduce.pdf';
const _locked = 'test/fixtures/generated/locked.pdf';
const _big200 = 'test/fixtures/generated/big200.pdf';
const _big500 = 'test/fixtures/generated/big500.pdf';
const _fake = 'test/fixtures/generated/fake.pdf';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUpAll(setUpPdfium);

  late Directory tmp;
  late AetherDatabase db;
  late DriftOpStore store;
  late PdfStorage storage;
  late PdfImporter importer;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('aether_pdfimport_');
    db = AetherDatabase(NativeDatabase.memory());
    store = DriftOpStore(db);
    storage = await PdfStorage.open(Directory('${tmp.path}/lib'));
    var t = 1000;
    importer = PdfImporter(
      store: store,
      bus: CommandBus(
        store: store,
        clock: HlcClock('d', now: () => t++),
        ids: SequentialIdGenerator('b'),
      ),
      storage: storage,
      inspector: const PdfiumInspector(),
      db: db,
      ids: SequentialIdGenerator('doc'),
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

  final needsPaper = pdfiumSkipReason([_paper]);
  final needsLocked = pdfiumSkipReason([_paper, _locked]);
  final needsBig = pdfiumSkipReason([_big200, _big500]);
  final needsFake = pdfiumSkipReason([_paper, _fake]);

  test('real pdfium describes the paper and renders a PNG thumbnail', () async {
    final info = await const PdfiumInspector().inspect(_paper);
    expect(info.pageSizes.length, 13);
    expect(info.pageSizes.first, const Size(612, 792));
    final png = info.thumbnailPng!;
    expect(png.sublist(0, 4), [137, 80, 78, 71], reason: 'PNG signature');
    expect(png.length, greaterThan(2000), reason: 'not an empty image');
  }, skip: needsPaper);

  test(
    'imports the paper end to end and its stored copy is a valid PDF',
    () async {
      final r = await importer.import(ImportRequest(_paper));
      expect(r.title, 'mapreduce');
      final doc = (await documents()).single;
      expect(doc.pageCount, 13);
      expect(
        File(storage.thumbnailPath(doc.sourceHash)).lengthSync(),
        greaterThan(2000),
      );

      // Open the stored copy, as the canvas will.
      final reopened = await openPdfFile(storage.pdfPath(doc.sourceHash));
      addTearDown(reopened.dispose);
      expect(reopened.pageSizes.length, 13);
    },
    skip: needsPaper,
  );

  test('a PDF with a real user password asks, rejects a wrong one, accepts the right one', () async {
    await expectLater(
      importer.import(const ImportRequest(_locked)),
      throwsA(
        isA<PdfOpenException>().having(
          (e) => e.failure,
          'failure',
          PdfOpenFailure.password,
        ),
      ),
      reason: 'no password given',
    );
    expect(await documents(), isEmpty);
    expect(
      Directory('${tmp.path}/lib/pdfs').listSync(),
      isEmpty,
      reason: 'nothing kept',
    );

    final answers = ['nope', 'secret'];
    var asked = 0;
    final r = await importer.import(
      const ImportRequest(_locked),
      password: () async {
        asked++;
        return answers.removeAt(0);
      },
    );
    expect(asked, 2);
    expect(r.created, isTrue);
    expect((await documents()).single.pageCount, 13);
  }, skip: needsLocked);

  test('giving up on the password imports nothing', () async {
    await expectLater(
      importer.import(const ImportRequest(_locked), password: () async => null),
      throwsA(
        isA<PdfOpenException>().having(
          (e) => e.failure,
          'failure',
          PdfOpenFailure.password,
        ),
      ),
    );
    expect(await documents(), isEmpty);
  }, skip: needsLocked);

  test('a text file named .pdf is rejected, and nothing is kept', () async {
    await expectLater(
      importer.import(const ImportRequest(_fake)),
      throwsA(
        isA<PdfOpenException>().having(
          (e) => e.failure,
          'failure',
          PdfOpenFailure.unreadable,
        ),
      ),
    );
    expect(await documents(), isEmpty);
    expect(Directory('${tmp.path}/lib/pdfs').listSync(), isEmpty);
  }, skip: needsFake);

  test(
    'the same paper twice is one document (real hashing of a real file)',
    () async {
      final a = await importer.import(const ImportRequest(_paper));
      final b = await importer.import(const ImportRequest(_paper));
      expect(b.created, isFalse);
      expect(b.docId, a.docId);
      expect((await documents()).length, 1);
    },
    skip: needsPaper,
  );

  group('large documents', () {
    for (final (path, pages) in [(_big200, 208), (_big500, 507)]) {
      test(
        'imports $pages pages in a few seconds and lays them all out',
        () async {
          final sw = Stopwatch()..start();
          final r = await importer.import(ImportRequest(path));
          sw.stop();
          final doc = (await documents()).single;
          expect(doc.pageCount, pages);
          final cards = await store.entities(
            kind: EntityKind.page,
            docId: r.docId,
          );
          expect(cards.length, pages);
          // ignore: avoid_print
          print('imported $pages pages in ${sw.elapsedMilliseconds} ms');
          expect(sw.elapsed, lessThan(const Duration(seconds: 20)));
          // Pages are stacked, not overlapping.
          final ys = [for (final c in cards) PageRef.fromState(c)]
            ..sort((a, b) => a.index.compareTo(b.index));
          for (var i = 1; i < ys.length; i++) {
            expect(
              ys[i].cardY,
              greaterThan(ys[i - 1].cardY + ys[i - 1].height - 1e-6),
            );
          }
        },
        timeout: const Timeout(Duration(seconds: 60)),
        skip: needsBig,
      );
    }
  });
}
