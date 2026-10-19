import 'package:aether/app/providers.dart';
import 'package:aether/domain/model/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  testWidgets('empty library invites an import', (tester) async {
    await pumpApp(tester, size: const Size(360, 800));
    expect(find.text('Nothing on the desk yet'), findsOneWidget);
    expect(
      find.textContaining('Everything you mark lands in Extract'),
      findsOneWidget,
    );
  });

  testWidgets(
    'phone and tablet use a FAB; desktop puts Import in the app bar',
    (tester) async {
      await pumpApp(tester, size: const Size(360, 800));
      expect(find.byType(FloatingActionButton), findsOneWidget);
      await pumpApp(tester, size: const Size(1280, 720));
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Import PDF'), findsOneWidget);
    },
  );

  testWidgets('documents are listed and open the canvas', (tester) async {
    await pumpApp(
      tester,
      size: const Size(840, 600),
      docs: const [
        Document(id: 'd1', title: 'MapReduce', sourceHash: 'h', pageCount: 13),
        Document(id: 'd2', title: 'One pager', sourceHash: 'h2', pageCount: 1),
      ],
    );
    expect(find.textContaining('13 pages · Added'), findsOneWidget);
    expect(find.textContaining('1 page · Added'), findsOneWidget);
    await tester.tap(find.text('MapReduce'));
    await tester.pumpAndSettle();
    expect(find.text('Copy as Markdown'), findsOneWidget);
  });

  testWidgets('Copy as Markdown is honest when there is nothing to copy', (
    tester,
  ) async {
    await pumpApp(
      tester,
      size: const Size(1280, 720),
      location: '/doc/synthetic-30',
    );
    await tester.tap(find.text('Copy as Markdown'));
    await tester.pump();
    expect(find.text('Nothing to copy yet.'), findsOneWidget);
  });

  testWidgets('settings: theme choice changes the app brightness', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(840, 600), location: '/settings');
    expect(
      Theme.of(tester.element(find.text('Settings').first)).brightness,
      Brightness.light,
    );
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('Settings').first)).brightness,
      Brightness.dark,
    );
  });

  testWidgets('settings: finger draws is off by default and can be enabled', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(840, 600), location: '/settings');
    final tile = find.widgetWithText(SwitchListTile, 'Finger draws');
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    await tester.tap(tile);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
  });

  testWidgets('settings screen has no overflow at 2x text on a phone', (
    tester,
  ) async {
    await pumpApp(
      tester,
      size: const Size(360, 800),
      location: '/settings',
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings: provider defaults', (tester) async {
    const s = AppSettings();
    expect(
      (s.themeMode, s.fingerDraws, s.leftHanded),
      (ThemeMode.system, false, false),
    );
  });

  testWidgets('an unknown location lands on the library, not an error screen', (
    tester,
  ) async {
    await pumpApp(
      tester,
      size: const Size(840, 600),
      location: 'file:///sdcard/Android/data/x/files/paper.pdf',
    );
    await tester.pumpAndSettle();
    expect(find.text('Nothing on the desk yet'), findsOneWidget);
    expect(find.textContaining('Page Not Found'), findsNothing);
  });
}
