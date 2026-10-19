import 'dart:io';
import 'dart:ui' as ui;

import 'package:aether/core/hlc/hlc.dart';
import 'package:aether/core/id/id_generator.dart';
import 'package:aether/data/db/database.dart';
import 'package:aether/data/db/drift_op_store.dart';
import 'package:aether/data/pdf/page_text_service.dart';
import 'package:aether/data/pdf/pdf_storage.dart';
import 'package:aether/domain/commands/command_bus.dart';
import 'package:aether/domain/model/models.dart';
import 'package:aether/domain/ops/op.dart';
import 'package:aether/domain/text/page_text.dart';
import 'package:aether/features/canvas/canvas_view.dart';
import 'package:aether/features/canvas/pdf/pdf_source.dart';
import 'package:aether/features/library/import/pdf_importer.dart';
import 'package:aether/features/library/import/pdf_inspector.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' show RepaintBoundary;
import 'package:flutter_test/flutter_test.dart';

import '../../support/harness.dart';
import '../../support/pdfium_env.dart';

/// The whole path, with the real app and real pdfium: import the paper, open
/// it, drag the mouse over its text with the Mark tool, and find a saved,
/// quoted highlight (SPEC §18, M3: "drag-select matches expected text").
const _paper = 'test/fixtures/mapreduce/mapreduce.pdf';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUpAll(setUpPdfium);
  final skip = pdfiumSkipReason([_paper]);

  testWidgets('dragging over the abstract saves a highlight that quotes it', (
    tester,
  ) async {
    final db = AetherDatabase(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));
    final store = DriftOpStore(db);
    final tmp = Directory.systemTemp.createTempSync('aether_markflow_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    late PdfStorage storage;
    late String docId, hash;
    await tester.runAsync(() async {
      storage = await PdfStorage.open(Directory('${tmp.path}/lib'));
      var t = 1000;
      final importer = PdfImporter(
        store: store,
        bus: CommandBus(
          store: store,
          clock: HlcClock('imp', now: () => t++),
          ids: SequentialIdGenerator('b'),
        ),
        storage: storage,
        inspector: const PdfiumInspector(),
        db: db,
        ids: SequentialIdGenerator('doc'),
      );
      docId = (await importer.import(const ImportRequest(_paper))).docId;
      hash = Document.fromState((await store.entity(docId))!).sourceHash;
    });

    await pumpApp(
      tester,
      size: const Size(1280, 800),
      db: db,
      location: '/doc/$docId',
      storage: storage,
    );
    await pumpUntil(tester, find.byType(CanvasView));
    final view = tester.widget<CanvasView>(find.byType(CanvasView));
    final c = view.controller;
    // The pages appear first; marking is ready once the PDF itself is open.
    for (var i = 0; i < 400 && c.marks == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 25));
    }
    expect(c.scene.value.cards, hasLength(13));
    // Let the first fit settle.
    await tester.pump(const Duration(milliseconds: 500));

    // Where the words are, from the same pdfium the app uses.
    late PageText page;
    await tester.runAsync(() async {
      final pdf = await openPdfFile(storage.pdfPath(hash));
      page = await PageTextService(
        docKey: 'x',
        extractor: PdfrxTextExtractor(pdf.document),
      ).pageText(0);
      await pdf.dispose();
    });
    int word(String t) => [
      for (var i = 0; i < page.words.length; i++)
        if (page.quote(page.words[i].start, page.words[i].end) == t) i,
    ].first;

    final origin = tester.getTopLeft(find.byType(CanvasView));
    Offset onScreen(int w) {
      final b = page.words[w].box;
      final card = c.scene.value.cards.first;
      final v = c.view.value;
      final world =
          card.rect.topLeft + Offset((b.x0 + b.x1) / 2, (b.y0 + b.y1) / 2);
      return origin + world * v.zoom + Offset(v.x, v.y);
    }

    final from = onScreen(word('programming'));
    final to = onScreen(word('sets.'));
    expect(
      Rect.fromLTWH(0, 0, 1280, 800).contains(from) &&
          Rect.fromLTWH(0, 0, 1280, 800).contains(to),
      isTrue,
      reason: 'both words are on screen after the first fit ($from, $to)',
    );

    final g = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    // The page's text loads on a worker; give it real time, as a person would.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await g.moveTo(Offset.lerp(from, to, 0.5)!);
    await g.moveTo(to);
    await tester.pump();
    await g.up();
    await tester.pump();

    List<Highlight> saved = [];
    for (var i = 0; i < 200 && saved.isEmpty; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        saved = [
          for (final e in await store.entities(
            kind: EntityKind.mark,
            docId: docId,
          ))
            Mark.fromState(e) as Highlight,
        ];
      });
    }
    expect(saved, hasLength(1));
    expect(
      saved.single.quote,
      'programming model and an associated implementation for processing and '
      'generating large data sets.',
    );
    expect(saved.single.meaning, Meaning.claim);
    expect(saved.single.rects, hasLength(3));
    expect(saved.single.pageId, c.scene.value.cards.first.id);

    // A picture of it, for looking at: AETHER_SCREENSHOTS=/some/dir flutter test ...
    final shots = Platform.environment['AETHER_SCREENSHOTS'];
    if (shots == null) return;
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).first,
      );
      final image = await boundary.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$shots/mark_flow.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  }, skip: skip != null);
}
