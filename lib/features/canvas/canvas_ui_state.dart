import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/widgets/aether_icon.dart';
import 'palette.dart';

export 'palette.dart' show InkPalette, ToolColours;

enum CanvasTool {
  pan('Pan', 'Move around', AetherIcons.pan, 'H'),
  mark('Mark', 'Highlight text', AetherIcons.mark, 'M'),
  ink('Ink', 'Write or draw', AetherIcons.pen, 'P'),
  erase('Erase', 'Erase', AetherIcons.eraser, 'E'),
  note('Note', 'Tap to add a note', AetherIcons.note, 'N'),
  link(
    'Link',
    'Drag from a note to a highlight to connect them',
    AetherIcons.link,
    'L',
  ),
  select(
    'Select',
    'Circle marks to move, recolor or delete them',
    AetherIcons.lasso,
    'S',
  );

  const CanvasTool(this.label, this.tip, this.icon, this.key);
  final String label, tip, icon, key;

  /// The four tools kept on a phone's bottom bar; the rest live under "More".
  bool get isPrimary =>
      this == mark || this == ink || this == erase || this == note;
}

/// What the Extract list shows: everything, only notes, or only the
/// highlights of one colour.
@immutable
class ExtractFilter {
  const ExtractFilter._(this.kind) : color = null;

  static const all = ExtractFilter._('all');
  static const notes = ExtractFilter._('notes');
  const ExtractFilter.colour(int c) : kind = 'colour', color = c;

  final String kind;
  final int? color;

  bool get isColour => kind == 'colour';

  @override
  bool operator ==(Object other) =>
      other is ExtractFilter && other.kind == kind && other.color == color;

  @override
  int get hashCode => Object.hash(kind, color);
}

class CanvasUiState {
  const CanvasUiState({
    this.tool = CanvasTool.mark,
    this.markColors = ToolColours.markDefault,
    this.inkWidth = InkPalette.defaultWidth,
    this.inkColors = ToolColours.inkDefault,
    this.erasePartial = false,
    this.extractOpen,
    this.extractWidth = 340,
    this.filter = ExtractFilter.all,
  });

  final CanvasTool tool;

  /// The marker's colour (any ARGB) and its last five.
  final ToolColours markColors;
  int get markColor => markColors.current;

  /// Pen size in dp (1 to 8) and colour (ARGB) for the Ink tool.
  final double inkWidth;
  final ToolColours inkColors;
  int get inkColor => inkColors.current;

  /// Erase only the part of a stroke under the eraser (off: whole strokes).
  final bool erasePartial;

  /// null means "use the layout's default" (open in landscape, closed in portrait).
  final bool? extractOpen;
  final double extractWidth;
  final ExtractFilter filter;

  CanvasUiState copyWith({
    CanvasTool? tool,
    ToolColours? markColors,
    double? inkWidth,
    ToolColours? inkColors,
    bool? erasePartial,
    bool? extractOpen,
    double? extractWidth,
    ExtractFilter? filter,
  }) => CanvasUiState(
    tool: tool ?? this.tool,
    markColors: markColors ?? this.markColors,
    inkWidth: inkWidth ?? this.inkWidth,
    inkColors: inkColors ?? this.inkColors,
    erasePartial: erasePartial ?? this.erasePartial,
    extractOpen: extractOpen ?? this.extractOpen,
    extractWidth: extractWidth ?? this.extractWidth,
    filter: filter ?? this.filter,
  );
}

class CanvasUiNotifier extends Notifier<CanvasUiState> {
  static const double minExtract = 280, maxExtract = 480;

  bool _touchedInk = false, _touchedMark = false;

  @override
  CanvasUiState build() {
    _restore();
    return const CanvasUiState();
  }

  /// Brings back the colours of the last session, unless one was already
  /// picked since launch.
  Future<void> _restore() async {
    final store = ref.read(paletteStoreProvider);
    final ink = ToolColours.decode(await store.read(_inkKey));
    final mark = ToolColours.decode(await store.read(_markKey));
    if (!ref.mounted) return;
    state = state.copyWith(
      inkColors: _touchedInk ? null : ink,
      markColors: _touchedMark ? null : mark,
    );
  }

  static const _inkKey = 'palette.ink', _markKey = 'palette.mark';

  void setTool(CanvasTool t) => state = state.copyWith(tool: t);

  /// Picking a marker colour also switches to Mark.
  void setMarkColor(int argb) {
    _touchedMark = true;
    state = state.copyWith(
      markColors: state.markColors.use(argb),
      tool: CanvasTool.mark,
    );
    ref.read(paletteStoreProvider).write(_markKey, state.markColors.encode());
  }

  void setInkWidth(double w) => state = state.copyWith(
    inkWidth: w.clamp(InkPalette.minWidth, InkPalette.maxWidth),
  );

  void setErasePartial(bool v) => state = state.copyWith(erasePartial: v);

  void setInkColor(int argb) {
    _touchedInk = true;
    state = state.copyWith(inkColors: state.inkColors.use(argb));
    ref.read(paletteStoreProvider).write(_inkKey, state.inkColors.encode());
  }

  void setExtractOpen(bool v) => state = state.copyWith(extractOpen: v);

  void setExtractWidth(double w) =>
      state = state.copyWith(extractWidth: w.clamp(minExtract, maxExtract));

  void setFilter(ExtractFilter f) => state = state.copyWith(filter: f);
}

final canvasUiProvider = NotifierProvider<CanvasUiNotifier, CanvasUiState>(
  CanvasUiNotifier.new,
);
