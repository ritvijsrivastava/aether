import 'package:aether/app/providers.dart';
import 'package:aether/domain/model/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  testWidgets('empty library invites a first board', (tester) async {
    await pumpApp(tester, size: const Size(360, 800));
    expect(find.text('No boards yet'), findsOneWidget);
    expect(find.textContaining('Tap New board'), findsOneWidget);
  });

  testWidgets(
    'phone and tablet use a FAB; desktop puts New board in the app bar',
    (tester) async {
      await pumpApp(tester, size: const Size(360, 800));
      expect(find.byType(FloatingActionButton), findsOneWidget);
      await pumpApp(tester, size: const Size(1280, 720));
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.widgetWithText(FilledButton, 'New board'), findsOneWidget);
    },
  );

  testWidgets('documents are listed and open the canvas', (tester) async {
    await pumpApp(
      tester,
      size: const Size(840, 600),
      docs: const [
        Document(id: 'd1', title: 'MapReduce'),
        Document(id: 'd2', title: 'One pager'),
      ],
    );
    expect(find.textContaining('Added'), findsNWidgets(2));
    await tester.tap(find.text('MapReduce'));
    await tester.pumpAndSettle();
    expect(
      find.byTooltip('Undo'),
      findsOneWidget,
      reason: 'the canvas top bar',
    );
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
    expect((s.themeMode, s.leftHanded), (ThemeMode.system, false));
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
    expect(find.text('No boards yet'), findsOneWidget);
    expect(find.textContaining('Page Not Found'), findsNothing);
  });
}
