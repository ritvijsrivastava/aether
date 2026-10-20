import 'package:aether/domain/model/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

const phone = Size(360, 800);
const desktop = Size(1280, 720);

void main() {
  group('the library list', () {
    final docs = [
      const Document(id: 'd1', title: 'MapReduce'),
      const Document(id: 'd2', title: 'Attention is all you need'),
    ];

    testWidgets('lists documents', (tester) async {
      await pumpApp(tester, size: phone, docs: docs);
      expect(find.text('MapReduce'), findsOneWidget);
      expect(find.textContaining('Added'), findsNWidgets(2));
    });

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
      'a document with no file on the device opens as a blank board',
      (tester) async {
        await pumpApp(
          tester,
          size: desktop,
          docs: const [Document(id: 'd1', title: 'Gone')],
          location: '/doc/d1',
        );
        await pumpUntil(tester, find.text('Gone'));
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
