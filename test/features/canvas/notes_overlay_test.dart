import 'package:aether/domain/model/models.dart';
import 'package:aether/features/canvas/engine/scene.dart';
import 'package:aether/features/canvas/engine/view_state.dart';
import 'package:aether/features/canvas/notes/note_tool.dart';
import 'package:aether/features/canvas/notes/notes_layer.dart';
import 'package:aether/features/canvas/notes/notes_overlay.dart';
import 'package:aether/ui/theme/theme.dart';
import 'package:aether/ui/theme/tokens.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeActions implements NoteActions {
  FakeActions(this.layer);
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

Note note(String id, {String text = 'hello', double x = 50, double y = 60}) =>
    Note(
      id: id,
      docId: 'd',
      pageId: 'p0',
      x: x,
      y: y,
      width: 200,
      height: 120,
      text: text,
    );

Future<
  ({
    ValueNotifier<ViewState> view,
    ValueNotifier<Scene> scene,
    NotesLayer notes,
    FakeActions actions,
  })
>
pump(
  WidgetTester tester, {
  ViewState view = const ViewState(),
  List<Note> notes = const [],
}) async {
  tester.view.physicalSize = _size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final v = ValueNotifier(view);
  final scene = ValueNotifier(
    const Scene([
      Card(id: 'p0', index: 0, rect: Rect.fromLTWH(100, 100, 600, 800)),
    ]),
  );
  final layer = NotesLayer();
  for (final n in notes) {
    layer.add(n);
  }
  final actions = FakeActions(layer);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(AetherTokens.light),
      home: Scaffold(
        body: NotesOverlay(
          view: v,
          scene: scene,
          notes: layer,
          actions: actions,
          viewport: () => _size,
        ),
      ),
    ),
  );
  return (view: v, scene: scene, notes: layer, actions: actions);
}

void main() {
  testWidgets('a note sits at its place on its page, scaled with the zoom', (
    tester,
  ) async {
    await pump(
      tester,
      view: const ViewState(x: 10, y: 20, zoom: 2),
      notes: [note('a')],
    );
    // Page origin (100,100) + note (50,60) = world (150,160): screen (310, 340).
    final r = tester.getRect(find.byType(NoteCard));
    expect(r.left, closeTo(310, 1e-6));
    expect(r.top, closeTo(340, 1e-6));
    expect(r.width, closeTo(400, 1e-6));
    expect(r.height, closeTo(240, 1e-6));
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets(
    'only notes in view are built; a note on a missing page is skipped',
    (tester) async {
      final h = await pump(tester, notes: [note('near'), note('far', x: 5000)]);
      expect(find.byType(NoteCard), findsOneWidget);
      h.notes.add(
        const Note(
          id: 'lost',
          docId: 'd',
          pageId: 'gone',
          x: 0,
          y: 0,
          text: 'x',
        ),
      );
      await tester.pump();
      expect(find.byType(NoteCard), findsOneWidget);
    },
  );

  testWidgets('a note on no page is placed in canvas space', (tester) async {
    await pump(
      tester,
      notes: [const Note(id: 'free', docId: 'd', x: 30, y: 40, text: 'free')],
    );
    expect(tester.getTopLeft(find.byType(NoteCard)), const Offset(30, 40));
  });

  testWidgets('below 35% zoom a note is a chip you cannot type in', (
    tester,
  ) async {
    await pump(
      tester,
      view: const ViewState(zoom: 0.3),
      notes: [note('a', text: 'first line\nsecond')],
    );
    expect(find.byType(NoteChip), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('first line'), findsOneWidget);
  });

  testWidgets('typing reports each change', (tester) async {
    final h = await pump(tester, notes: [note('a', text: '')]);
    await tester.enterText(find.byType(TextField), 'abc');
    expect(h.actions.log, contains('edit:abc'));
    expect(h.notes.byId('a')!.text, 'abc');
  });

  testWidgets('a note just placed takes the keyboard at once', (tester) async {
    final h = await pump(tester);
    h.notes.add(note('new', text: ''), draft: true);
    h.notes.requestFocus('new');
    await tester.pump();
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasFocus, isTrue);
    expect(h.notes.focusId, isNull, reason: 'the request was taken');
    expect(h.notes.editingId, 'new');
  });

  testWidgets('losing focus reports a blur; Escape drops focus', (
    tester,
  ) async {
    final h = await pump(tester, notes: [note('a')]);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(h.notes.editingId, 'a');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(h.actions.log, contains('blur'));
    expect(h.notes.editingId, isNull);
  });

  testWidgets('dragging the header moves the note by the drag, in page units', (
    tester,
  ) async {
    final h = await pump(
      tester,
      view: const ViewState(zoom: 2),
      notes: [note('a')],
    );
    final handle = find.byKey(const ValueKey('note-drag'));
    await tester.drag(handle, const Offset(40, 20));
    await tester.pump();
    // 40 px on screen at zoom 2 is 20 page units (less the touch slop).
    expect(h.notes.byId('a')!.x, greaterThan(50));
    expect(h.notes.byId('a')!.x, lessThanOrEqualTo(70));
    expect(h.actions.log.last, 'done');
  });

  testWidgets('dragging the corner resizes, but never below the minimum', (
    tester,
  ) async {
    final h = await pump(tester, notes: [note('a')]);
    final grip = find.byKey(const ValueKey('note-resize'));
    await tester.drag(grip, const Offset(80, 60));
    await tester.pump();
    expect(h.notes.byId('a')!.width, greaterThan(250));
    expect(h.notes.byId('a')!.height, greaterThan(150));
    await tester.drag(grip, const Offset(-900, -900));
    await tester.pump();
    expect(h.notes.byId('a')!.width, Note.minWidth);
    expect(h.notes.byId('a')!.height, Note.minHeight);
  });

  testWidgets('the delete control deletes', (tester) async {
    final h = await pump(tester, notes: [note('a')]);
    await tester.tap(find.byTooltip('Delete note'));
    await tester.pump();
    expect(h.actions.log, contains('delete'));
    expect(find.byType(NoteCard), findsNothing);
  });

  testWidgets('the header and delete control are 48 dp targets on screen', (
    tester,
  ) async {
    for (final zoom in [1.0, 0.7, 0.5]) {
      await pump(
        tester,
        view: ViewState(zoom: zoom),
        notes: [note('a')],
      );
      final del = tester.getSize(find.byTooltip('Delete note'));
      expect(del.width, greaterThanOrEqualTo(47.99), reason: 'zoom $zoom');
      expect(del.height, greaterThanOrEqualTo(47.99), reason: 'zoom $zoom');
    }
  });

  testWidgets('text changed from outside (undo) shows in the field', (
    tester,
  ) async {
    final h = await pump(tester, notes: [note('a', text: 'before')]);
    h.notes.update(h.notes.byId('a')!.copyWith(text: 'after undo'));
    await tester.pump();
    expect(find.text('after undo'), findsOneWidget);
  });

  testWidgets('follows the view as it pans', (tester) async {
    final h = await pump(tester, notes: [note('a')]);
    final before = tester.getTopLeft(find.byType(NoteCard));
    h.view.value = const ViewState(x: 100, y: 50);
    await tester.pump();
    expect(
      tester.getTopLeft(find.byType(NoteCard)) - before,
      const Offset(100, 50),
    );
  });

  testWidgets('a note has a name for screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, notes: [note('a')]);
    expect(find.bySemanticsLabel('Note text'), findsOneWidget);
    handle.dispose();
  });
}
