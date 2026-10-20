import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../domain/text/page_text.dart';
import '../../../domain/text/page_text_source.dart';
import '../../../domain/text/text_selection.dart';
import '../engine/scene.dart';
import '../input/tool_gestures.dart';
import '../engine/view_state.dart';
import 'mark_layers.dart';

/// What the arbiter asks of the Mark tool. Offsets are screen space.
abstract interface class MarkGestures {
  void markStart(Offset screen);
  void markMove(Offset screen);
  void markEnd(Offset screen);
  void markCancel();
}

/// Plugs the Mark tool into the tool router.
class MarkHandler implements ToolHandler {
  MarkHandler(this.marks);
  final MarkGestures marks;

  @override
  void start(ToolPoint p) => marks.markStart(p.position);
  @override
  void move(ToolPoint p) => marks.markMove(p.position);
  @override
  void end(ToolPoint p) => marks.markEnd(p.position);
  @override
  void cancel() => marks.markCancel();
}

/// Where a finished highlight goes. Both return the new highlight's id
/// immediately (the write is queued behind it), so the tool can refer to it
/// at once.
abstract interface class MarkSink {
  String addHighlight({
    required String pageId,
    required MarkSelection selection,
    required int color,
    PageText? text,
  });

  /// Replaces [oldId] with [selection] as one undoable step (a double tap
  /// widening a word to its sentence).
  String replaceHighlight({
    required String oldId,
    required String pageId,
    required MarkSelection selection,
    required int color,
    PageText? text,
  });
}

/// The Mark tool: turns a drag over a page into a highlight (SPEC §8).
///
/// - Drag from a word: snaps to words and follows the pointer across lines.
/// - Drag from empty paper, or on a page with no text: a free rectangle.
/// - Tap a word: that word. Double-tap: its sentence (replacing the word).
///
/// Works in page space on the card where the drag started, so leaving the
/// page mid-drag keeps extending the selection on that page.
class MarkToolController implements MarkGestures {
  MarkToolController({
    required this.view,
    required this.scene,
    required this.live,
    required this.color,
    this.text,
    this.sink,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final ValueListenable<ViewState> view;
  final ValueListenable<Scene> scene;

  /// Receives the in-progress highlight for drawing; null when idle.
  final ValueNotifier<LiveMark?> live;

  /// The colour to mark with, read at the moment of release.
  final int Function() color;

  /// Set once a document's text is available. Without it the tool does
  /// nothing.
  PageTextSource? text;
  MarkSink? sink;

  final DateTime Function() _now;

  /// Pointer-down finds a word within this many dp (SPEC 7: about 10 dp).
  static const double tolerancePx = 10;

  /// Movement beyond this many dp makes a press a drag, not a tap.
  static const double tapSlopPx = 6;

  /// Two taps this close in time and space are a double tap.
  static const Duration doubleTapWindow = Duration(milliseconds: 350);
  static const double doubleTapSlopPx = 24;

  // The drag in progress.
  int _token = 0; // changes with every gesture; stale async results are dropped
  Card? _card;
  Offset _downScreen = Offset.zero;
  Offset _downPage = Offset.zero;
  Offset _latestScreen = Offset.zero;
  bool _moved = false;
  bool _active = false;
  PageText? _pageText;
  MarkDrag? _drag;
  Future<void>? _loading;
  DateTime _startedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Marks that had to wait for a page's text, the wait of the last one, and
  /// the longest wait. A wait means the text was not ready at pointer-down
  /// (the page was not warmed yet); the numbers are shown in the performance
  /// overlay so the S9 can say whether warming is enough.
  int waits = 0;
  Duration lastWait = Duration.zero, maxWait = Duration.zero;

  /// One line for the performance overlay.
  String get stats => waits == 0
      ? 'text always ready'
      : 'text waited $waits× · last ${lastWait.inMilliseconds} ms'
            ' · max ${maxWait.inMilliseconds} ms';

  // The last completed tap, for double-tap detection.
  _Tap? _lastTap;

  bool get isActive => _active;

  Card? _cardAt(Offset world) {
    final cards = scene.value.cards;
    for (var i = cards.length - 1; i >= 0; i--) {
      if (cards[i].rect.contains(world)) return cards[i];
    }
    return null;
  }

  Offset _page(Offset screen) =>
      view.value.screenToWorld(screen) - _card!.rect.topLeft;

  @override
  void markStart(Offset screen) {
    _reset();
    if (text == null || sink == null) return;
    final card = _cardAt(view.value.screenToWorld(screen));
    if (card == null) return;
    _active = true;
    _token++;
    _card = card;
    _downScreen = _latestScreen = screen;
    _downPage = _page(screen);
    _startedAt = _now();

    final source = text!;
    final ready = source.peek(card.index);
    if (ready != null) {
      _begin(ready);
    } else {
      final token = _token;
      _loading = source.pageText(card.index).then((t) {
        if (token == _token && _active) {
          lastWait = _now().difference(_startedAt);
          waits++;
          if (lastWait > maxWait) maxWait = lastWait;
          _begin(t);
        }
      });
    }
  }

  void _begin(PageText t) {
    _pageText = t;
    _drag = MarkDrag(
      t,
      _downPage.dx,
      _downPage.dy,
      tolerance: tolerancePx / view.value.zoom,
    );
    if (_moved) _extend();
  }

  void _extend() {
    final d = _drag;
    final card = _card;
    if (d == null || card == null) return;
    final p = _page(_latestScreen);
    final sel = d.update(p.dx, p.dy);
    live.value = sel == null ? null : LiveMark(card.id, sel, color());
  }

  @override
  void markMove(Offset screen) {
    if (!_active) return;
    _latestScreen = screen;
    if (!_moved && (screen - _downScreen).distance > tapSlopPx) _moved = true;
    if (_moved) _extend();
  }

  @override
  void markEnd(Offset screen) {
    if (!_active) return;
    _latestScreen = screen;
    if ((screen - _downScreen).distance > tapSlopPx) _moved = true;
    final token = _token;
    final loading = _loading;
    if (_drag == null && loading != null) {
      // Released before the page's text arrived: wait for it, then finish.
      loading.whenComplete(() {
        if (token == _token) _finish();
      });
      return;
    }
    _finish();
  }

  void _finish() {
    final card = _card, drag = _drag, t = _pageText, sink = this.sink;
    final moved = _moved;
    final at = _downScreen;
    _reset();
    if (card == null || drag == null || sink == null) return;
    if (moved) {
      _commitDrag(sink, card, drag.selection, t);
      return;
    }
    // A tap.
    if (!drag.isText) return; // a tap on empty paper is nothing
    final now = _now();
    final prev = _lastTap;
    if (prev != null &&
        prev.cardId == card.id &&
        now.difference(prev.time) <= doubleTapWindow &&
        (at - prev.at).distance <= doubleTapSlopPx) {
      final sentence = TextSelector.sentenceAt(t!, drag.anchorWord);
      _lastTap = null;
      if (sentence != null) {
        sink.replaceHighlight(
          oldId: prev.highlightId,
          pageId: card.id,
          selection: sentence,
          color: color(),
          text: t,
        );
        return;
      }
    }
    final id = _commitDrag(sink, card, drag.selection, t);
    _lastTap = id == null ? null : _Tap(now, at, card.id, id);
  }

  String? _commitDrag(
    MarkSink sink,
    Card card,
    MarkSelection? selection,
    PageText? t,
  ) {
    if (selection == null) return null;
    return sink.addHighlight(
      pageId: card.id,
      selection: selection,
      color: color(),
      text: t,
    );
  }

  @override
  void markCancel() => _reset();

  void _reset() {
    _active = false;
    _token++;
    _card = null;
    _drag = null;
    _pageText = null;
    _loading = null;
    _moved = false;
    if (live.value != null) live.value = null;
  }

  // --- warming ---------------------------------------------------------------

  Timer? _warmTimer;

  /// Extracts the text of the pages in view ahead of the first touch, so a
  /// pointer-down can start selecting at once. Call when the view changes; it
  /// waits for the view to settle.
  void warmVisible({Size? viewport}) {
    final source = text;
    if (source == null || viewport == null) return;
    _warmTimer?.cancel();
    _warmTimer = Timer(const Duration(milliseconds: 120), () {
      final world = view.value.worldRect(viewport);
      var n = 0;
      for (final c in scene.value.visible(world)) {
        source.pageText(c.index);
        if (++n >= 4) break;
      }
    });
  }

  void dispose() {
    _warmTimer?.cancel();
    _reset();
  }
}

class _Tap {
  const _Tap(this.time, this.at, this.cardId, this.highlightId);
  final DateTime time;
  final Offset at;
  final String cardId, highlightId;
}
