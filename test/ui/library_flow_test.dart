import 'dart:io';

import 'package:aether/app/providers.dart';
import 'package:aether/domain/model/models.dart';
import 'package:aether/data/pdf/pdf_password_cache.dart';
import 'package:aether/features/canvas/pdf/pdf_source.dart';
import 'package:aether/features/library/import/import_flow.dart';
import 'package:aether/features/library/import/pdf_importer.dart';
import 'package:aether/features/library/import/pdf_inspector.dart';
import 'package:aether/features/library/import/pdf_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

const phone = Size(360, 800);
const desktop = Size(1280, 720);

void main() {
  late Directory src;
  late FakeInspector inspector;
  late FakePicker picker;

  setUp(() {
    src = Directory.systemTemp.createTempSync('aether_src_');
    inspector = FakeInspector();
    picker = FakePicker();
  });
  tearDown(() => src.deleteSync(recursive: true));

  List<Override> fakes() => [
    pdfInspectorProvider.overrideWithValue(inspector),
    pdfPickerProvider.overrideWithValue(picker),
  ];

  Future<void> tapImport(WidgetTester tester) async {
    await tester.tap(find.text('Import PDF'));
    await tester.pump();
  }

  group('importing through the picker', () {
    testWidgets('choosing nothing changes nothing', (tester) async {
      await pumpApp(tester, size: phone, overrides: fakes());
      await tapImport(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(picker.calls, 1);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Nothing on the desk yet'), findsOneWidget);
    });

    testWidgets('one imported PDF opens straight away', (tester) async {
      picker.next = [ImportRequest(writeFakePdf(src, 'My Paper.pdf').path)];
      await pumpApp(tester, size: phone, overrides: fakes());
      await tapImport(tester);
      await pumpUntil(tester, find.byTooltip('Back to library'));
      expect(
        find.byTooltip('Back to library'),
        findsOneWidget,
        reason: 'now on the canvas screen',
      );
    });

    testWidgets('several PDFs are imported together and stay in the library', (
      tester,
    ) async {
      picker.next = [
        ImportRequest(writeFakePdf(src, 'One.pdf', seed: '1').path),
        ImportRequest(writeFakePdf(src, 'Two.pdf', seed: '2').path),
      ];
      await pumpApp(tester, size: phone, overrides: fakes());
      await tapImport(tester);
      await pumpUntil(tester, find.text('Imported 2 PDFs.'));
      expect(find.text('One'), findsOneWidget);
      expect(find.text('Two'), findsOneWidget);
      expect(
        find.byTooltip('Back to library'),
        findsNothing,
        reason: 'no navigation for a batch',
      );
    });

    testWidgets('the same PDF again says so and opens the existing document', (
      tester,
    ) async {
      picker.next = [ImportRequest(writeFakePdf(src, 'Dup.pdf').path)];
      await pumpApp(tester, size: phone, overrides: fakes());
      await tapImport(tester);
      await pumpUntil(tester, find.byTooltip('Back to library'));
      await tester.tap(find.byTooltip('Back to library'));
      await tester.pumpAndSettle();
      picker.next = [ImportRequest(writeFakePdf(src, 'Dup again.pdf').path)];
      await tapImport(tester);
      await pumpUntil(tester, find.text('Already in your library. Opened it.'));
      expect(
        inspector.inspected.length,
        1,
        reason: 'the second copy was never even opened',
      );
    });

    testWidgets(
      'a file that is not a PDF is reported and the library is unchanged',
      (tester) async {
        inspector.failure = PdfOpenException(PdfOpenFailure.unreadable);
        picker.next = [ImportRequest(writeFakePdf(src, 'notes.pdf').path)];
        await pumpApp(tester, size: phone, overrides: fakes());
        await tapImport(tester);
        await pumpUntil(
          tester,
          find.textContaining("Couldn't import notes.pdf"),
        );
        expect(
          find.textContaining('could not be opened as a PDF'),
          findsOneWidget,
        );
        expect(find.text('Nothing on the desk yet'), findsOneWidget);
      },
    );

    testWidgets('one bad file among good ones still imports the good ones', (
      tester,
    ) async {
      final bad = writeFakePdf(src, 'bad.pdf', seed: 'bad');
      final good = writeFakePdf(src, 'good.pdf', seed: 'good');
      inspector = _FailsFor();
      picker.next = [ImportRequest(bad.path), ImportRequest(good.path)];
      await pumpApp(
        tester,
        size: phone,
        overrides: [
          pdfInspectorProvider.overrideWithValue(inspector),
          pdfPickerProvider.overrideWithValue(picker),
        ],
      );
      await tapImport(tester);
      await pumpUntil(tester, find.textContaining('Imported 1 PDF.'));
      expect(find.textContaining("Couldn't import bad.pdf"), findsOneWidget);
      expect(find.text('good'), findsOneWidget);
    });

    testWidgets('the picker failing shows a message instead of crashing', (
      tester,
    ) async {
      await pumpApp(
        tester,
        size: phone,
        overrides: [pdfPickerProvider.overrideWithValue(_ThrowingPicker())],
      );
      await tapImport(tester);
      await tester.pump();
      expect(find.text("Couldn't open the file picker."), findsOneWidget);
    });
  });

  group('passwords', () {
    testWidgets('a protected PDF asks for its password, then opens', (
      tester,
    ) async {
      inspector = FakeInspector(password: 'secret');
      picker.next = [ImportRequest(writeFakePdf(src, 'locked.pdf').path)];
      await pumpApp(tester, size: phone, overrides: fakes());
      await tapImport(tester);
      await pumpUntil(tester, find.text('Password needed'));
      expect(find.textContaining('"locked.pdf" is protected'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.tap(find.text('Open'));
      await pumpUntil(tester, find.textContaining('did not work'));

      await tester.enterText(find.byType(TextField), 'secret');
      await tester.tap(find.text('Open'));
      await pumpUntil(tester, find.byTooltip('Back to library'));
    });

    testWidgets('cancelling the password prompt rejects the file', (
      tester,
    ) async {
      inspector = FakeInspector(password: 'secret');
      picker.next = [ImportRequest(writeFakePdf(src, 'locked.pdf').path)];
      await pumpApp(tester, size: phone, overrides: fakes());
      await tapImport(tester);
      await pumpUntil(tester, find.text('Password needed'));
      await tester.tap(find.text('Cancel'));
      await pumpUntil(tester, find.textContaining('password protected'));
      expect(find.text('Nothing on the desk yet'), findsOneWidget);
    });

    testWidgets('the password field can be revealed', (tester) async {
      inspector = FakeInspector(password: 'secret');
      picker.next = [ImportRequest(writeFakePdf(src, 'locked.pdf').path)];
      await pumpApp(tester, size: phone, overrides: fakes());
      await tapImport(tester);
      await pumpUntil(tester, find.text('Password needed'));
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isTrue,
      );
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isFalse,
      );
    });
  });

  group('progress', () {
    testWidgets('a running import shows its progress and disables Import', (
      tester,
    ) async {
      await pumpApp(tester, size: desktop, overrides: fakes());
      final container = ProviderScope.containerOf(
        tester.element(find.text('Aether')),
      );
      container
          .read(importProgressProvider.notifier)
          .set(const ImportProgress(total: 3, done: 1, current: 'Big.pdf'));
      await tester.pump();
      expect(find.text('Importing 2 of 3: Big.pdf'), findsOneWidget);
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.widgetWithText(FilledButton, 'Import PDF'),
            )
            .onPressed,
        isNull,
      );
    });
  });

  group('the library list', () {
    final docs = [
      const Document(
        id: 'd1',
        title: 'MapReduce',
        sourceHash: 'h1',
        pageCount: 13,
      ),
      const Document(
        id: 'd2',
        title: 'Attention is all you need',
        sourceHash: 'h2',
        pageCount: 15,
      ),
    ];

    testWidgets(
      'lists documents, with a placeholder where there is no thumbnail',
      (tester) async {
        await pumpApp(tester, size: phone, docs: docs);
        expect(find.text('MapReduce'), findsOneWidget);
        expect(find.textContaining('15 pages · Added'), findsOneWidget);
        expect(find.byType(Image), findsNWidgets(2));
      },
    );

    testWidgets('search narrows the list and says when nothing matches', (
      tester,
    ) async {
      await pumpApp(tester, size: phone, docs: docs);
      await tester.enterText(find.byType(TextField), 'attention');
      await tester.pump();
      expect(find.text('MapReduce'), findsNothing);
      expect(find.text('Attention is all you need'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump();
      expect(find.text('No documents match "zzz".'), findsOneWidget);
    });

    testWidgets('rename changes the title', (tester) async {
      await pumpApp(tester, size: phone, docs: docs);
      await tester.tap(find.byTooltip('More').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Renamed paper');
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await pumpUntil(tester, find.text('Renamed paper'));
    });

    testWidgets('delete removes the document and Undo brings it back', (
      tester,
    ) async {
      await pumpApp(tester, size: phone, docs: docs);
      await tester.tap(find.byTooltip('More').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await pumpUntil(tester, find.textContaining('Deleted'));
      expect(
        find.text('MapReduce').evaluate().length +
            find.text('Attention is all you need').evaluate().length,
        1,
      );
      await tester.pump(
        const Duration(milliseconds: 600),
      ); // snackbar slides in
      await tester.tap(find.text('Undo'));
      await pumpUntil(tester, find.text('Attention is all you need'));
      expect(find.text('MapReduce'), findsOneWidget);
    });
  });

  group('opening documents', () {
    testWidgets(
      'a document whose file is missing says so instead of showing blank pages',
      (tester) async {
        await pumpApp(
          tester,
          size: desktop,
          docs: const [
            Document(
              id: 'd1',
              title: 'Gone',
              sourceHash: 'nohash',
              pageCount: 2,
            ),
          ],
          location: '/doc/d1',
        );
        await pumpUntil(
          tester,
          find.text('The PDF for this document is missing from this device.'),
        );
      },
    );

    testWidgets('an unknown document says so', (tester) async {
      await pumpApp(tester, size: desktop, location: '/doc/nope');
      await pumpUntil(
        tester,
        find.text('This document is no longer in your library.'),
      );
    });
  });
}

/// Fails only for files whose content says "bad".
class _FailsFor extends FakeInspector {
  @override
  Future<PdfInfo> inspect(String path, {PasswordProvider? password}) async {
    if (File(path).readAsStringSync().contains('fake bad')) {
      throw PdfOpenException(PdfOpenFailure.unreadable);
    }
    return super.inspect(path, password: password);
  }
}

class _ThrowingPicker implements PdfPicker {
  @override
  Future<List<ImportRequest>> pick() async =>
      throw StateError('no dialog available');
}
