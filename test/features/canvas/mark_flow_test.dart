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
import 'package:aether/features/canvas/canvas_ui_state.dart';
import 'package:aether/features/canvas/canvas_view.dart';
import 'package:aether/features/canvas/ink/ink_options.dart';
import 'package:aether/features/canvas/engine/view_state.dart';
import 'package:aether/features/canvas/pdf/pdf_source.dart';
import 'package:aether/features/library/import/pdf_importer.dart';
import 'package:aether/features/library/import/pdf_inspector.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show SystemChannels;
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
    for (var i = 0; i < 400 && c.tools == null; i++) {
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

    // Extract lists it, quoted, and tapping it takes the canvas there.
    await tester.pump();
    expect(find.text('1 item'), findsOneWidget);
    expect(
      find.textContaining('programming model and an associated'),
      findsOneWidget,
    );
    final b = saved.single.bounds;
    final card = c.scene.value.cards.first;
    // Look somewhere else first: far down the document, zoomed out.
    c.setView(const ViewState(x: -300, y: -6000, zoom: 0.4));
    await tester.pump();
    await tester.tap(
      find.textContaining('programming model and an associated'),
    );
    await tester.pump(); // starts the move
    await tester.pump(const Duration(seconds: 1)); // and finishes it
    final centre = c.view.value.worldToScreen(
      card.rect.topLeft + Offset((b.x0 + b.x1) / 2, (b.y0 + b.y1) / 2),
    );
    final free = Offset(
      c.insets.left + (c.viewport.width - c.insets.horizontal) / 2,
      c.insets.top + (c.viewport.height - c.insets.vertical) / 2,
    );
    expect((centre - free).distance, lessThan(2), reason: 'centred in view');
    expect(c.view.value.zoom, 1.0, reason: 'from far out it comes in to 100%');
    await tester.pump(const Duration(seconds: 2)); // the outline finishes

    // Copy as Markdown puts the quoted list on the clipboard.
    String? clip;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clip = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(find.text('Copy as Markdown'));
    await tester.pump();
    expect(
      clip,
      '# mapreduce\n\n## Claim\n- "programming model and an associated '
      'implementation for processing and generating large data sets." '
      '(p. 1)\n',
    );
    expect(find.text('Copied'), findsOneWidget, reason: 'the button says so');
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Copy as Markdown'), findsOneWidget);

    // Delete takes it off the page and out of storage; Undo brings it back.
    await tester.tap(find.byTooltip('Delete highlight'));
    await tester.pump();
    expect(find.text('0 items'), findsOneWidget);
    for (var i = 0; i < 100; i++) {
      var n = -1;
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        n = (await store.entities(kind: EntityKind.mark, docId: docId)).length;
      });
      if (n == 0) break;
    }
    expect(
      await tester.runAsync(
        () => store.entities(kind: EntityKind.mark, docId: docId),
      ),
      isEmpty,
    );
    // The Copy message slides away, then the Delete one slides in.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.tap(find.text('Undo').last);
    for (var i = 0; i < 100 && find.text('1 item').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 25));
    }
    expect(find.text('1 item'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7)); // the snackbar goes

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

  testWidgets('drawing with the Ink tool saves a stroke on the page', (
    tester,
  ) async {
    final db = AetherDatabase(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));
    final store = DriftOpStore(db);
    final tmp = Directory.systemTemp.createTempSync('aether_inkflow_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    late PdfStorage storage;
    late String docId;
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
    });
    await pumpApp(
      tester,
      size: const Size(1280, 800),
      db: db,
      location: '/doc/$docId',
      storage: storage,
    );
    await pumpUntil(tester, find.byType(CanvasView));
    final c = tester.widget<CanvasView>(find.byType(CanvasView)).controller;
    for (var i = 0; i < 400 && c.tools == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 25));
    }
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('Ink'));
    await tester.pump();
    expect(find.byType(InkOptions), findsOneWidget, reason: 'options appear');
    await tester.tap(find.byTooltip('Coral'));
    await tester.pump();

    final origin = tester.getTopLeft(find.byType(CanvasView));
    final from = origin + const Offset(500, 300);
    // A stylus stroke with pressure, 12 samples.
    const id = 7;
    await tester.sendEventToBinding(
      PointerDownEvent(
        kind: PointerDeviceKind.stylus,
        pointer: id,
        position: from,
        buttons: kPrimaryButton,
        pressure: 0.3,
        pressureMin: 0,
        pressureMax: 1,
      ),
    );
    for (var i = 1; i <= 12; i++) {
      await tester.sendEventToBinding(
        PointerMoveEvent(
          kind: PointerDeviceKind.stylus,
          pointer: id,
          position: from + Offset(i * 12.0, (i % 3) * 4.0),
          buttons: kPrimaryButton,
          pressure: 0.3 + i * 0.03,
          pressureMin: 0,
          pressureMax: 1,
        ),
      );
    }
    await tester.sendEventToBinding(
      PointerUpEvent(
        kind: PointerDeviceKind.stylus,
        pointer: id,
        position: from + const Offset(160, 0),
        pressureMin: 0,
        pressureMax: 1,
      ),
    );
    await tester.pump();

    List<Ink> saved = [];
    for (var i = 0; i < 200 && saved.isEmpty; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        saved = [
          for (final e in await store.entities(
            kind: EntityKind.mark,
            docId: docId,
          ))
            if (Mark.fromState(e) case final Ink i) i,
        ];
      });
    }
    expect(saved, hasLength(1));
    expect(saved.single.pageId, c.scene.value.cards.first.id);
    expect(saved.single.color, InkPalette.colors[1]);
    expect(saved.single.pointCount, greaterThanOrEqualTo(3));
    expect(
      saved.single.samples[2],
      closeTo(0.3, 1e-4),
      reason: 'the first sample keeps its pressure',
    );
    expect(find.text('Highlight'), findsNothing);
    expect(
      find.text('0 items'),
      findsOneWidget,
      reason: 'ink is not in Extract',
    );

    // The pen's eraser end wipes across it: the stroke goes, as one step.
    const eraserId = 8;
    await tester.sendEventToBinding(
      PointerDownEvent(
        kind: PointerDeviceKind.invertedStylus,
        pointer: eraserId,
        position: from + const Offset(60, -30),
        buttons: kPrimaryButton,
        pressureMin: 0,
        pressureMax: 1,
      ),
    );
    for (var i = 1; i <= 6; i++) {
      await tester.sendEventToBinding(
        PointerMoveEvent(
          kind: PointerDeviceKind.invertedStylus,
          pointer: eraserId,
          position: from + Offset(60, -30.0 + i * 12),
          buttons: kPrimaryButton,
          pressureMin: 0,
          pressureMax: 1,
        ),
      );
    }
    await tester.sendEventToBinding(
      PointerUpEvent(
        kind: PointerDeviceKind.invertedStylus,
        pointer: eraserId,
        position: from + const Offset(60, 42),
        pressureMin: 0,
        pressureMax: 1,
      ),
    );
    await tester.pump();
    for (var i = 0; i < 200; i++) {
      var n = -1;
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        n = (await store.entities(kind: EntityKind.mark, docId: docId)).length;
      });
      if (n == 0) break;
    }
    expect(
      await tester.runAsync(
        () => store.entities(kind: EntityKind.mark, docId: docId),
      ),
      isEmpty,
      reason: 'erased from storage',
    );
    // Undo brings it back.
    await tester.tap(find.byTooltip('Undo'));
    var back = 0;
    for (var i = 0; i < 200 && back == 0; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        back = (await store.entities(
          kind: EntityKind.mark,
          docId: docId,
        )).length;
      });
    }
    expect(back, 1);
  }, skip: skip != null);
}
