import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/model/models.dart';
import '../../../ui/theme/theme.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/aether_icon.dart';
import '../engine/scene.dart';
import '../engine/view_state.dart';
import 'note_tool.dart';
import 'notes_layer.dart';

/// Below this zoom a note is a small chip you cannot edit (SPEC 5.6).
const double noteChipZoom = 0.35;

/// The notes, as real widgets placed in the canvas: each sits at its place on
/// its page, scaled with the zoom, and only those in view are built.
///
/// This sits above the canvas's pointer handling (a sibling, not a child), so
/// a touch on a note goes to the note and never reaches the pan and tool
/// logic below it (SPEC 7.1).
class NotesOverlay extends StatelessWidget {
  const NotesOverlay({
    super.key,
    required this.view,
    required this.scene,
    required this.notes,
    required this.actions,
    required this.viewport,
  });

  final ValueNotifier<ViewState> view;
  final ValueNotifier<Scene> scene;
  final NotesLayer notes;
  final NoteActions actions;

  /// The canvas size, for building only what is in view.
  final Size Function() viewport;

  /// Where a note's top-left is in world space, or null if its page is gone.
  static Offset? worldOrigin(Note n, Scene s) {
    if (n.pageId == null) return Offset(n.x, n.y);
    final card = s.byId(n.pageId!);
    return card == null ? null : card.rect.topLeft + Offset(n.x, n.y);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([view, scene, notes]),
      builder: (context, _) {
        final v = view.value;
        final s = scene.value;
        final visible = v.worldRect(viewport()).inflate(40 / v.zoom);
        final children = <Widget>[];
        for (final n in notes.all) {
          final o = worldOrigin(n, s);
          if (o == null) continue;
          if (!(o & Size(n.width, n.height)).overlaps(visible)) continue;
          children.add(
            Positioned(
              key: ValueKey(n.id),
              left: o.dx * v.zoom + v.x,
              top: o.dy * v.zoom + v.y,
              child: Transform.scale(
                scale: v.zoom,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: n.width,
                  height: n.height,
                  child: v.zoom < noteChipZoom
                      ? NoteChip(note: n)
                      : NoteCard(
                          note: n,
                          zoom: v.zoom,
                          notes: notes,
                          actions: actions,
                        ),
                ),
              ),
            ),
          );
        }
        return Stack(clipBehavior: Clip.hardEdge, children: children);
      },
    );
  }
}

/// A note too small to edit: its first line on a sticky chip.
class NoteChip extends StatelessWidget {
  const NoteChip({super.key, required this.note});
  final Note note;

  @override
  Widget build(BuildContext context) {
    final first = note.text
        .split('\n')
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AetherTokens.notePaper,
        borderRadius: BorderRadius.circular(AetherTokens.rCard),
        boxShadow: context.tokens.sticky,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          first,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: kUiFont,
            fontSize: 28,
            height: 1.2,
            color: AetherTokens.onMark,
          ),
        ),
      ),
    );
  }
}

/// One sticky note: a header you drag it by, a delete control, the text, and
/// a corner to resize from.
class NoteCard extends StatefulWidget {
  const NoteCard({
    super.key,
    required this.note,
    required this.zoom,
    required this.notes,
    required this.actions,
  });

  final Note note;
  final double zoom;
  final NotesLayer notes;
  final NoteActions actions;

  @override
  State<NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<NoteCard> {
  late final TextEditingController _text = TextEditingController(
    text: widget.note.text,
  );
  final FocusNode _focus = FocusNode(debugLabel: 'note');
  bool _hadFocus = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
    _takeRequestedFocus();
  }

  void _focusChanged() {
    final has = _focus.hasFocus;
    if (has == _hadFocus) return;
    _hadFocus = has;
    if (has) {
      widget.notes.setEditing(widget.note.id);
    } else {
      if (widget.notes.editingId == widget.note.id) {
        widget.notes.setEditing(null);
      }
      widget.actions.noteBlurred(widget.note.id);
    }
  }

  void _takeRequestedFocus() {
    if (widget.notes.focusId != widget.note.id) return;
    widget.notes.focusTaken(widget.note.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(NoteCard old) {
    super.didUpdateWidget(old);
    // The text changed from outside (an undo): show it, keeping the caret at
    // the end of what the user sees.
    if (widget.note.text != _text.text) {
      _text.value = TextEditingValue(
        text: widget.note.text,
        selection: TextSelection.collapsed(offset: widget.note.text.length),
      );
    }
    _takeRequestedFocus();
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_focusChanged)
      ..dispose();
    _text.dispose();
    super.dispose();
  }

  /// The header is at least 48 dp tall on screen (a fingertip), so it is
  /// that many dp divided by the zoom in page points, within sane limits.
  double get _header =>
      (AetherTokens.minTarget / widget.zoom).clamp(36.0, 96.0);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final n = widget.note;
    final z = widget.zoom;
    final header = _header;
    final actions = widget.actions;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AetherTokens.notePaper,
        borderRadius: BorderRadius.circular(AetherTokens.rCard),
        boxShadow: t.sticky,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AetherTokens.rCard),
        child: Stack(
          children: [
            Positioned.fill(
              top: header,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Focus(
                  onKeyEvent: (node, e) {
                    if (e is KeyDownEvent &&
                        e.logicalKey == LogicalKeyboardKey.escape) {
                      _focus.unfocus();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Semantics(
                    label: 'Note text',
                    textField: true,
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      keyboardType: TextInputType.multiline,
                      cursorColor: AetherTokens.onMark,
                      onChanged: (v) => actions.editNoteText(n.id, v),
                      style: const TextStyle(
                        fontFamily: kUiFont,
                        fontSize: 15,
                        height: 1.4,
                        color: AetherTokens.onMark,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isCollapsed: true,
                        contentPadding: EdgeInsets.zero,
                        filled: false,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Header: the label, which is also the handle to drag by.
            Positioned(
              left: 0,
              top: 0,
              right: header,
              height: header,
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: GestureDetector(
                  key: const ValueKey('note-drag'),
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (d) => actions.noteGeometryChanged(
                    n.id,
                    x: n.x + d.delta.dx / z,
                    y: n.y + d.delta.dy / z,
                  ),
                  onPanEnd: (_) => actions.noteGeometryDone(n.id),
                  onPanCancel: () => actions.noteGeometryDone(n.id),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Note',
                        style: AetherText(AetherTokens.onMark).label.copyWith(
                          color: AetherTokens.onMark.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              width: header,
              height: header,
              child: Tooltip(
                message: 'Delete note',
                child: InkResponse(
                  onTap: () => actions.deleteNote(n.id),
                  radius: header / 2,
                  child: Center(
                    child: AetherIcon(
                      AetherIcons.trash,
                      size: 18,
                      color: AetherTokens.onMark.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ),
            ),
            // Resize from the bottom-right corner.
            Positioned(
              right: 0,
              bottom: 0,
              width: header,
              height: header,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeDownRight,
                child: GestureDetector(
                  key: const ValueKey('note-resize'),
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (d) => actions.noteGeometryChanged(
                    n.id,
                    width: (n.width + d.delta.dx / z).clamp(
                      Note.minWidth,
                      double.infinity,
                    ),
                    height: (n.height + d.delta.dy / z).clamp(
                      Note.minHeight,
                      double.infinity,
                    ),
                  ),
                  onPanEnd: (_) => actions.noteGeometryDone(n.id),
                  onPanCancel: () => actions.noteGeometryDone(n.id),
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: CustomPaint(
                        size: const Size(14, 14),
                        painter: _GripPainter(
                          AetherTokens.onMark.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GripPainter extends CustomPainter {
  _GripPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(size.width, 2), Offset(2, size.height), p);
    canvas.drawLine(
      Offset(size.width, size.height * 0.55),
      Offset(size.width * 0.55, size.height),
      p,
    );
  }

  @override
  bool shouldRepaint(_GripPainter old) => old.color != color;
}
