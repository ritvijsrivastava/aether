import 'package:aether/features/canvas/radial_menu.dart';
import 'package:aether/ui/theme/theme.dart';
import 'package:aether/ui/theme/tokens.dart';
import 'package:aether/ui/widgets/aether_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RadialMenuController', () {
    late RadialMenuController c;
    late List<String> picked;
    setUp(() {
      picked = [];
      c = RadialMenuController();
      c.items = [
        RadialItem(
          icon: AetherIcons.paste,
          label: 'Paste',
          onPick: () => picked.add('paste'),
        ),
        RadialItem(
          icon: AetherIcons.note,
          label: 'Note',
          onPick: () => picked.add('note'),
        ),
      ];
    });

    test('open, point and release pick the item swiped to', () {
      const view = Size(800, 600);
      c.open(const Offset(400, 300), c.items);
      expect(c.isOpen, isTrue);
      // The first item sits straight above the centre.
      final itemAt =
          c.centre(view) - const Offset(0, RadialMenuController.radius);
      c.pointTo(itemAt, view);
      expect(c.hovered, 0);
      c.release(view);
      expect(picked, ['paste']);
      expect(c.isOpen, isFalse);
    });

    test('the second item is clockwise from the first', () {
      const view = Size(800, 600);
      c.open(const Offset(400, 300), c.items);
      final centre = c.centre(view);
      // 90 degrees to the right of the top item.
      c.pointTo(centre + const Offset(RadialMenuController.radius, 0), view);
      expect(c.hovered, 1);
      c.release(view);
      expect(picked, ['note']);
    });

    test('releasing in the centre cancels', () {
      const view = Size(800, 600);
      c.open(const Offset(400, 300), c.items);
      c.pointTo(const Offset(400, 300), view);
      expect(c.hovered, isNull);
      c.release(view);
      expect(picked, isEmpty);
    });

    test('pointing far away hovers nothing', () {
      const view = Size(800, 600);
      c.open(const Offset(400, 300), c.items);
      c.pointTo(const Offset(400, 300) - const Offset(0, 400), view);
      expect(c.hovered, isNull);
      c.pointTo(
        const Offset(400, 300) + const Offset(0, RadialMenuController.radius),
        view,
      );
      expect(c.hovered, isNotNull, reason: 'the bottom item is reachable');
    });

    test('the anchor is pulled inboard so the ring fits the screen', () {
      const view = Size(800, 600);
      c.open(const Offset(5, 5), c.items);
      final centre = c.centre(view);
      expect(centre.dx, greaterThanOrEqualTo(RadialMenuController.radius));
      expect(centre.dy, greaterThanOrEqualTo(RadialMenuController.radius));
      c.open(const Offset(795, 595), c.items);
      final c2 = c.centre(view);
      expect(
        c2.dx,
        lessThanOrEqualTo(view.width - RadialMenuController.radius),
      );
      expect(
        c2.dy,
        lessThanOrEqualTo(view.height - RadialMenuController.radius),
      );
    });

    test('close with nothing picked', () {
      c.open(Offset.zero, c.items);
      c.close();
      expect(c.isOpen, isFalse);
      expect(picked, isEmpty);
    });

    test('hovering only notifies on change', () {
      const view = Size(800, 600);
      c.open(const Offset(400, 300), c.items);
      var n = 0;
      c.addListener(() => n++);
      final top = c.centre(view) - const Offset(0, RadialMenuController.radius);
      c.pointTo(top, view);
      c.pointTo(top + const Offset(4, 0), view);
      expect(n, 1, reason: 'the same item twice is one change');
      c.pointTo(const Offset(400, 300), view);
      expect(n, 2);
    });
  });

  group('RadialMenuOverlay', () {
    testWidgets('nothing when closed; discs and labels when open', (
      tester,
    ) async {
      final c = RadialMenuController();
      addTearDown(c.dispose);
      final picked = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(AetherTokens.light),
          home: Scaffold(body: RadialMenuOverlay(controller: c)),
        ),
      );
      expect(find.text('Paste'), findsNothing);
      c.open(const Offset(400, 300), [
        RadialItem(
          icon: AetherIcons.paste,
          label: 'Paste',
          onPick: () => picked.add('paste'),
        ),
        RadialItem(
          icon: AetherIcons.note,
          label: 'Note here',
          onPick: () => picked.add('note'),
        ),
      ]);
      await tester.pump();
      expect(find.text('Paste'), findsOneWidget);
      expect(find.text('Note here'), findsOneWidget);
      expect(find.byType(AetherIcon), findsNWidgets(2));
      // It sits around the fitted anchor.
      final paste = tester.getRect(find.text('Paste'));
      expect(paste.top, lessThan(300), reason: 'above the centre');
      // Nothing in the overlay takes pointers.
      final gesture = await tester.startGesture(const Offset(400, 300));
      await gesture.up();
      expect(picked, isEmpty);
      c.close();
      await tester.pump();
      expect(find.text('Paste'), findsNothing);
    });

    testWidgets('a hovered disc is marked so the painter can fill it', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      final c = RadialMenuController();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(AetherTokens.light),
          home: Scaffold(body: RadialMenuOverlay(controller: c)),
        ),
      );
      c.open(const Offset(400, 300), [
        RadialItem(icon: AetherIcons.paste, label: 'Paste', onPick: () {}),
        RadialItem(icon: AetherIcons.note, label: 'Note here', onPick: () {}),
      ]);
      await tester.pump();
      c.pointTo(
        const Offset(400, 300 - RadialMenuController.radius),
        const Size(800, 600),
      );
      await tester.pump();
      expect(c.hovered, 0);
      c.pointTo(
        const Offset(400 + RadialMenuController.radius, 300),
        const Size(800, 600),
      );
      await tester.pump();
      expect(c.hovered, 1);
      h.dispose();
    });
  });
}
