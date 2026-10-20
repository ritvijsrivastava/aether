import 'package:aether/features/canvas/notes/note_menu.dart';
import 'package:aether/ui/theme/theme.dart';
import 'package:aether/ui/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class Log implements NoteMenuActions {
  final List<String> log = [];
  @override
  void unlinkNote(String id) => log.add('unlink:$id');
  @override
  void copyAll(String id) => log.add('copy:$id');
  @override
  void deleteNote(String id) => log.add('delete:$id');
}

void main() {
  testWidgets('nothing when closed; three buttons when open; each acts', (
    tester,
  ) async {
    final c = NoteMenuController();
    addTearDown(c.dispose);
    final actions = Log();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(AetherTokens.light),
        home: Scaffold(
          body: NoteMenuOverlay(controller: c, actions: actions),
        ),
      ),
    );
    expect(find.byType(Tooltip), findsNothing);
    c.open('n1', const Offset(500, 300));
    await tester.pump();
    expect(find.byTooltip('Unlink'), findsOneWidget);
    expect(find.byTooltip('Copy all'), findsOneWidget);
    expect(find.byTooltip('Delete'), findsOneWidget);
    // The pill sits above the press point.
    final unlink = tester.getRect(find.byTooltip('Unlink'));
    expect(unlink.bottom, lessThan(300));
    expect(unlink.left, greaterThanOrEqualTo(0));

    // Tap outside closes without acting.
    await tester.tapAt(const Offset(100, 550));
    await tester.pump();
    expect(actions.log, isEmpty);
    expect(find.byTooltip('Unlink'), findsNothing);

    // Opening again: the buttons act and close the menu.
    c.open('n2', const Offset(500, 300));
    await tester.pump();
    await tester.tap(find.byTooltip('Copy all'));
    await tester.pump();
    expect(actions.log, ['copy:n2']);
    expect(
      find.byTooltip('Unlink'),
      findsNothing,
      reason: 'closed after acting',
    );
  });

  testWidgets('each button is 48 dp tall and the pill stays on screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = NoteMenuController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(AetherTokens.light),
        home: Scaffold(
          body: NoteMenuOverlay(controller: c, actions: Log()),
        ),
      ),
    );
    c.open('n', const Offset(300, 20));
    await tester.pump();
    for (final label in ['Unlink', 'Copy all', 'Delete']) {
      final r = tester.getRect(find.byTooltip(label));
      expect(r.height, greaterThanOrEqualTo(48), reason: label);
      expect(r.top, greaterThanOrEqualTo(0), reason: '$label on screen');
    }
    // A press near the bottom edge flips the pill below the press point.
    c.open('n', const Offset(300, 795));
    await tester.pump();
    final r = tester.getRect(find.byTooltip('Unlink'));
    expect(r.top, greaterThan(700));
    expect(r.bottom, lessThanOrEqualTo(800));
  });

  test('the controller opens and closes cleanly', () {
    final c = NoteMenuController();
    addTearDown(c.dispose);
    var n = 0;
    c.addListener(() => n++);
    c.open('a', Offset.zero);
    c.open('a', Offset.zero);
    expect(n, 1, reason: 'opening the same one twice is one change');
    expect(c.isOpen, isTrue);
    c.close();
    c.close();
    expect(n, 2);
    expect(c.isOpen, isFalse);
  });
}
