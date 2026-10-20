import 'package:aether/domain/model/models.dart';
import 'package:aether/features/canvas/engine/scene.dart';
import 'package:aether/features/canvas/engine/view_state.dart';
import 'package:aether/features/canvas/notes/note_tool.dart';
import 'package:aether/features/canvas/notes/notes_layer.dart';
import 'package:aether/features/canvas/notes/notes_overlay.dart';
import 'package:aether/ui/theme/theme.dart';
import 'package:aether/ui/theme/tokens.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';

class Acts implements NoteActions {
  Acts(this.layer);
  final NotesLayer layer;
  final List<String> log = [];
  @override
  void editNoteText(String id, String text) {
    log.add('edit:$text');
    final n = layer.byId(id);
    if (n != null) layer.update(n.copyWith(text: text));
  }

  @override
  void noteGeometryChanged(
    String id, {
    double? x,
    double? y,
    double? width,
    double? height,
  }) {
    log.add('geo');
    final n = layer.byId(id);
    if (n != null) {
      layer.update(n.copyWith(x: x, y: y, width: width, height: height));
    }
  }

  @override
  Future<void> noteGeometryDone(String id) async => log.add('done');
  @override
  Future<void> noteBlurred(String id) async => log.add('blur');
  @override
  void deleteNote(String id) {
    log.add('delete');
    layer.remove(id);
  }
}

const _size = Size(1000, 800);

Note note(String id, {String text = 'hello', double x = 50, int z = 0}) => Note(
  id: id,
  docId: 'd',
  pageId: 'p0',
  x: x,
  y: 60,
  width: 200,
  height: 120,
  text: text,
  z: z,
);

class Rig {
  Rig(this.notes, this.actions, this.selected, this.copied);
  final NotesLayer notes;
  final Acts actions;
  final List<String> selected;
  final List<String> copied;
}

Future<Rig> pump(
  WidgetTester tester, {
  List<Note> start = const [],
  bool draft = false,
}) async {
  tester.view.physicalSize = _size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final layer = NotesLayer();
  for (final n in start) {
    layer.add(n, draft: draft);
  }
  final acts = Acts(layer);
  final selected = <String>[];
  final copied = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(AetherTokens.light),
      home: Scaffold(
        body: Stack(
          children: [
            // Stands for the canvas under the notes.
            const Positioned.fill(child: ColoredBox(color: Colors.white)),
            NotesOverlay(
              view: ValueNotifier(const ViewState()),
              scene: ValueNotifier(
                const Scene([
                  Card(
                    id: 'p0',
                    index: 0,
                    rect: Rect.fromLTWH(100, 100, 600, 800),
                  ),
                ]),
              ),
              notes: layer,
              actions: acts,
              viewport: () => _size,
              onSelect: selected.add,
              onCopyText: copied.add,
            ),
          ],
        ),
      ),
    ),
  );
  return Rig(layer, acts, selected, copied);
}

// The note 'a' is at page (50,60) + page origin (100,100): screen (150,160),
// 200 x 120. The header is 48 high, so the text area starts at y = 208.
const _body = Offset(250, 250);

Future<void> tap(
  WidgetTester tester,
  Offset at,
  PointerDeviceKind kind, {
  int pointer = 1,
  int atMs = 0,
}) async {
  await tester.sendEventToBinding(
    PointerDownEvent(
      pointer: pointer,
      kind: kind,
      position: at,
      timeStamp: Duration(milliseconds: atMs),
      buttons: kind == PointerDeviceKind.mouse ? kPrimaryButton : 0,
    ),
  );
  await tester.sendEventToBinding(
    PointerUpEvent(
      pointer: pointer,
      kind: kind,
      position: at,
      timeStamp: Duration(milliseconds: atMs + 30),
    ),
  );
}

void main() {
  group('a pen on a note', () {
    testWidgets('a tap selects it and does not open the keyboard', (
      tester,
    ) async {
      final r = await pump(tester, start: [note('a')]);
      await tap(tester, _body, PointerDeviceKind.stylus);
      await tester.pump(const Duration(milliseconds: 500));
      expect(r.selected, ['a']);
      expect(r.notes.editingId, isNull, reason: 'the pen never types');
      expect(r.actions.log, isNot(contains('blur')));
    });

    testWidgets('a double tap opens it for the keyboard', (tester) async {
      final r = await pump(tester, start: [note('a')]);
      await tap(tester, _body, PointerDeviceKind.stylus, pointer: 1);
      await tap(
        tester,
        _body + const Offset(4, 2),
        PointerDeviceKind.stylus,
        pointer: 2,
        atMs: 200,
      );
      await tester.pump();
      expect(r.notes.editingId, 'a');
    });

    testWidgets('two slow taps are two selects, not a double tap', (
      tester,
    ) async {
      final r = await pump(tester, start: [note('a')]);
      await tap(tester, _body, PointerDeviceKind.stylus, pointer: 1);
      await tap(tester, _body, PointerDeviceKind.stylus, pointer: 2, atMs: 900);
      await tester.pump();
      expect(r.selected, ['a', 'a']);
      expect(r.notes.editingId, isNull);
    });

    testWidgets('two taps in different places are not a double tap', (
      tester,
    ) async {
      final r = await pump(tester, start: [note('a')]);
      await tap(tester, _body, PointerDeviceKind.stylus, pointer: 1);
      await tap(
        tester,
        _body + const Offset(100, 0),
        PointerDeviceKind.stylus,
        pointer: 2,
        atMs: 100,
      );
      await tester.pump();
      expect(r.notes.editingId, isNull);
    });

    testWidgets('dragging it with the pen moves it, and selects nothing', (
      tester,
    ) async {
      final r = await pump(tester, start: [note('a')]);
      final g = await tester.startGesture(
        _body,
        kind: PointerDeviceKind.stylus,
      );
      await g.moveBy(const Offset(40, 0));
      await g.moveBy(const Offset(40, 30));
      await g.up();
      await tester.pump();
      final n = r.notes.byId('a')!;
      expect(n.x, closeTo(50 + 80, 1e-6));
      expect(n.y, closeTo(60 + 30, 1e-6));
      expect(r.actions.log.last, 'done', reason: 'saved as one step');
      expect(r.selected, isEmpty);
      expect(r.notes.editingId, isNull);
    });

    testWidgets('the eraser end behaves like the pen tip here', (tester) async {
      final r = await pump(tester, start: [note('a')]);
      await tap(tester, _body, PointerDeviceKind.invertedStylus);
      await tester.pump();
      expect(r.selected, ['a']);
      expect(r.notes.editingId, isNull);
    });

    testWidgets('it drags by the header too, as before', (tester) async {
      final r = await pump(tester, start: [note('a')]);
      final g = await tester.startGesture(
        const Offset(200, 180),
        kind: PointerDeviceKind.stylus,
      );
      await g.moveBy(const Offset(30, 0));
      await g.moveBy(const Offset(30, 0));
      await g.up();
      expect(r.notes.byId('a')!.x, greaterThan(50));
    });
  });

  group('a finger or the mouse on a note', () {
    for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
      testWidgets('$kind: one tap opens it for typing', (tester) async {
        final r = await pump(tester, start: [note('a')]);
        await tap(tester, _body, kind);
        await tester.pump();
        expect(r.notes.editingId, 'a');
        expect(r.selected, isEmpty);
        await tester.enterText(find.byType(TextField), 'typed');
        expect(r.actions.log, contains('edit:typed'));
      });
    }
  });

  group('a note being typed in', () {
    testWidgets('a pen tap elsewhere does not close it', (tester) async {
      final r = await pump(tester, start: [note('a')]);
      await tap(tester, _body, PointerDeviceKind.touch);
      await tester.pump();
      expect(r.notes.editingId, 'a');
      await tap(
        tester,
        const Offset(800, 600),
        PointerDeviceKind.stylus,
        pointer: 2,
      );
      await tester.pump();
      expect(r.notes.editingId, 'a', reason: 'still open');
      expect(r.actions.log, isNot(contains('blur')));
    });

    testWidgets('a finger tap elsewhere closes it, and saves it', (
      tester,
    ) async {
      final r = await pump(tester, start: [note('a')]);
      await tap(tester, _body, PointerDeviceKind.touch);
      await tester.pump();
      await tap(
        tester,
        const Offset(800, 600),
        PointerDeviceKind.touch,
        pointer: 2,
      );
      await tester.pump();
      expect(r.notes.editingId, isNull);
      expect(r.actions.log, contains('blur'));
    });

    testWidgets('a mouse click elsewhere closes it', (tester) async {
      final r = await pump(tester, start: [note('a')]);
      await tap(tester, _body, PointerDeviceKind.mouse);
      await tester.pump();
      await tap(
        tester,
        const Offset(800, 600),
        PointerDeviceKind.mouse,
        pointer: 2,
      );
      await tester.pump();
      expect(r.notes.editingId, isNull);
    });

    testWidgets('a pen tap on the note itself (header or text) keeps it open', (
      tester,
    ) async {
      final r = await pump(tester, start: [note('a')]);
      await tap(tester, _body, PointerDeviceKind.touch);
      await tester.pump();
      await tap(
        tester,
        const Offset(200, 180),
        PointerDeviceKind.stylus,
        pointer: 2,
      );
      await tap(tester, _body, PointerDeviceKind.stylus, pointer: 3);
      await tester.pump();
      expect(r.notes.editingId, 'a');
    });

    testWidgets('a finger tap on its own header does not close it either', (
      tester,
    ) async {
      final r = await pump(tester, start: [note('a')]);
      await tap(tester, _body, PointerDeviceKind.touch);
      await tester.pump();
      await tap(
        tester,
        const Offset(200, 180),
        PointerDeviceKind.touch,
        pointer: 2,
      );
      await tester.pump();
      expect(r.notes.editingId, 'a');
    });

    testWidgets('the pen does not write into the field (no handwriting)', (
      tester,
    ) async {
      await pump(tester, start: [note('a')]);
      await tap(tester, _body, PointerDeviceKind.touch);
      await tester.pump();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.stylusHandwritingEnabled, isFalse);
    });
  });

  group('stacking', () {
    testWidgets('a higher z is in front', (tester) async {
      await pump(
        tester,
        start: [
          note('low', x: 50, z: 0),
          note('high', x: 100, z: 5), // overlaps 'low'
        ],
      );
      final order = [
        for (final e in find.byType(NoteCard).evaluate())
          (e.widget as NoteCard).note.id,
      ];
      expect(order, ['low', 'high'], reason: 'painted back to front');
    });

    testWidgets('changing z reorders them without losing the text', (
      tester,
    ) async {
      final r = await pump(
        tester,
        start: [
          note('a', z: 0),
          note('b', x: 100, z: 1, text: 'bee'),
        ],
      );
      r.notes.update(r.notes.byId('a')!.copyWith(z: 9));
      await tester.pump();
      final order = [
        for (final e in find.byType(NoteCard).evaluate())
          (e.widget as NoteCard).note.id,
      ];
      expect(order, ['b', 'a']);
      expect(find.text('bee'), findsOneWidget);
    });
  });

  group('an empty new note', () {
    testWidgets('survives a pen tap on it', (tester) async {
      final r = await pump(tester, start: [note('d', text: '')], draft: true);
      r.notes.requestFocus('d');
      await tester.pump();
      await tester.pump();
      expect(r.notes.editingId, 'd');
      await tap(
        tester,
        const Offset(200, 180),
        PointerDeviceKind.stylus,
        pointer: 2,
      );
      await tap(tester, _body, PointerDeviceKind.stylus, pointer: 3);
      await tester.pump();
      expect(r.actions.log, isNot(contains('blur')), reason: 'not thrown away');
      expect(r.notes.byId('d'), isNotNull);
    });
  });

  group('selecting text with the pen', () {
    testWidgets(
      'a pen drag selects across lines, and Copy puts it on the clipboard',
      (tester) async {
        final r = await pump(tester, start: [note('a')]);
        // Open the note for typing.
        await tap(tester, _body, PointerDeviceKind.touch);
        await tester.pump();
        expect(r.notes.editingId, 'a');
        // Drag the pen across the text: from a point left of the text to a
        // point past its end, over two lines.
        final field = tester.getRect(find.byType(TextField));
        final from = Offset(field.left + 6, field.top + 12);
        final to = Offset(field.right - 6, field.bottom - 12);
        final g = await tester.startGesture(
          from,
          kind: PointerDeviceKind.stylus,
        );
        await tester.pump();
        await g.moveBy(const Offset(40, 0));
        await tester.pump();
        await g.moveBy(Offset(0, to.dy - from.dy));
        await g.moveBy(const Offset(120, 0));
        await tester.pump();
        await g.up();
        await tester.pump();
        final sel = r.notes.byId('a')!.text; // text is 'hello'
        expect(sel, 'hello', reason: 'sanity: there is text to select');
        expect(
          find.text('Copy'),
          findsOneWidget,
          reason: 'a copy button appears',
        );
        await tester.tap(find.text('Copy'));
        await tester.pump();
        expect(r.copied, hasLength(1));
        expect(
          'hello'.contains(r.copied.single),
          isTrue,
          reason: 'a contiguous run of the text (${r.copied.single})',
        );
        expect(
          r.copied.single.endsWith('o'),
          isTrue,
          reason: 'the drag ran to the end, across both lines',
        );
        expect(find.text('Copy'), findsNothing);
      },
    );

    testWidgets(
      'a pen tap inside the text keeps the note open and selects nothing',
      (tester) async {
        final r = await pump(tester, start: [note('a')]);
        await tap(tester, _body, PointerDeviceKind.touch);
        await tester.pump();
        final field = tester.getRect(find.byType(TextField));
        await tap(
          tester,
          field.center,
          PointerDeviceKind.stylus,
          pointer: 3,
          atMs: 100,
        );
        await tester.pump();
        expect(r.notes.editingId, 'a');
        expect(r.copied, isEmpty);
        expect(find.text('Copy'), findsNothing);
      },
    );

    testWidgets('a finger drag does not select (the caret moves as usual)', (
      tester,
    ) async {
      final r = await pump(tester, start: [note('a')]);
      await tap(tester, _body, PointerDeviceKind.touch);
      await tester.pump();
      final field = tester.getRect(find.byType(TextField));
      final g = await tester.startGesture(
        Offset(field.left + 6, field.top + 12),
        kind: PointerDeviceKind.touch,
      );
      await g.moveBy(Offset(0, field.height / 2));
      await g.up();
      await tester.pump();
      expect(find.text('Copy'), findsNothing, reason: 'no pen-style copy bar');
      expect(r.copied, isEmpty);
    });
  });
}
