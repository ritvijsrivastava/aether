import 'dart:ui';

import 'package:aether/domain/model/models.dart';
import 'package:aether/features/canvas/engine/scene.dart';
import 'package:aether/features/canvas/engine/view_state.dart';
import 'package:aether/features/canvas/input/tool_gestures.dart';
import 'package:aether/features/canvas/notes/note_tool.dart';
import 'package:aether/features/canvas/notes/notes_layer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

Note note(String id, {String? page = 'p0', String text = '', double x = 10}) =>
    Note(id: id, docId: 'd', pageId: page, x: x, y: 20, text: text);

ToolPoint pt(double x, double y) => ToolPoint(
  position: Offset(x, y),
  time: Duration.zero,
  kind: PointerDeviceKind.stylus,
);

class FakeNoteSink implements NoteSink {
  final List<({String? pageId, double x, double y})> placed = [];
  @override
  String beginNote({String? pageId, required double x, required double y}) {
    placed.add((pageId: pageId, x: x, y: y));
    return 'n${placed.length}';
  }
}

void main() {
  group('NotesLayer', () {
    test('keeps notes by page and tells listeners', () {
      final l = NotesLayer();
      var n = 0;
      l.addListener(() => n++);
      l.add(note('a'));
      l.add(note('b', page: null));
      l.update(note('a', text: 'x'));
      expect(n, 3);
      expect(l.forPage('p0').single.text, 'x');
      expect(l.forPage(null).single.id, 'b');
      expect(l.count, 2);
    });

    test('a draft is a note that is not saved yet, until it is promoted', () {
      final l = NotesLayer()..add(note('d'), draft: true);
      expect(l.isDraft('d'), isTrue);
      l.promote('d');
      expect(l.isDraft('d'), isFalse);
      l.promote('d'); // already a note: nothing happens
    });

    test('reloading saved notes keeps the drafts being typed into', () {
      final l = NotesLayer()
        ..add(note('saved'))
        ..add(note('draft'), draft: true);
      l.replaceSaved([note('other')]);
      expect({for (final n in l.all) n.id}, {'other', 'draft'});
      expect(l.isDraft('draft'), isTrue);
    });

    test('update ignores a note that is gone; remove forgets focus', () {
      final l = NotesLayer()..add(note('a'), draft: true);
      l.requestFocus('a');
      l.setEditing('a');
      l.remove('a');
      l.update(note('a', text: 'ghost'));
      expect(l.byId('a'), isNull);
      expect(l.focusId, isNull);
      expect(l.editingId, isNull);
      l.remove('a'); // twice is fine
    });

    test('a focus request is cleared once taken', () {
      final l = NotesLayer()..add(note('a'));
      l.requestFocus('a');
      expect(l.focusId, 'a');
      l.focusTaken('other');
      expect(l.focusId, 'a');
      l.focusTaken('a');
      expect(l.focusId, isNull);
    });
  });

  group('NoteToolController', () {
    late ValueNotifier<ViewState> view;
    late ValueNotifier<Scene> scene;
    late FakeNoteSink sink;
    late NoteToolController tool;
    setUp(() {
      view = ValueNotifier(const ViewState());
      scene = ValueNotifier(
        const Scene([
          Card(id: 'p0', index: 0, rect: Rect.fromLTWH(100, 100, 600, 800)),
        ]),
      );
      sink = FakeNoteSink();
      tool = NoteToolController(view: view, scene: scene, sink: sink);
    });

    test('a tap on a page puts a note there, in page space', () {
      tool.start(pt(250, 300));
      tool.end(pt(250, 300));
      expect(sink.placed.single, (pageId: 'p0', x: 150.0, y: 200.0));
    });

    test('a tap off every page puts a note in canvas space', () {
      tool.start(pt(20, 30));
      tool.end(pt(20, 30));
      expect(sink.placed.single, (pageId: null, x: 20.0, y: 30.0));
    });

    test('follows pan and zoom', () {
      view.value = const ViewState(x: 50, y: 0, zoom: 2);
      // screen (450, 400) is world (200, 200): page (100, 100).
      tool.start(pt(450, 400));
      tool.end(pt(450, 400));
      expect(sink.placed.single, (pageId: 'p0', x: 100.0, y: 100.0));
    });

    test('a drag, a cancel, or no sink places nothing', () {
      tool.start(pt(250, 300));
      tool.move(pt(300, 300));
      tool.end(pt(300, 300));
      tool.start(pt(250, 300));
      tool.cancel();
      tool.end(pt(250, 300));
      tool.sink = null;
      tool.start(pt(250, 300));
      tool.end(pt(250, 300));
      expect(sink.placed, isEmpty);
    });

    test('a wobble within 8 dp is still a tap', () {
      tool.start(pt(250, 300));
      tool.move(pt(254, 303));
      tool.end(pt(254, 303));
      expect(sink.placed, hasLength(1));
      expect(
        sink.placed.single.x,
        150,
        reason: 'placed where the pen went down',
      );
    });
  });
}
