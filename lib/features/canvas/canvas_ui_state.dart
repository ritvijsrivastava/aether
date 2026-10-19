import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/model/models.dart';
import '../../ui/widgets/aether_icon.dart';

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

enum ExtractFilter {
  all('All'),
  claim('Claim'),
  method('Method'),
  question('Question'),
  notes('Notes');

  const ExtractFilter(this.label);
  final String label;
}

/// The pen colours: Warm Ink first (the default), then the three meaning
/// colours, which are user-mark colours and so allowed on ink.
abstract final class InkPalette {
  static const int warmInk = 0xFF2B2723;
  static const List<int> colors = [
    warmInk,
    0xFFF4877E, // coral
    0xFFF2C94C, // amber
    0xFF6FB1EE, // blue
  ];
  static const List<String> names = ['Warm ink', 'Coral', 'Amber', 'Blue'];
  static const double minWidth = 1, maxWidth = 8, defaultWidth = 2.5;
}

class CanvasUiState {
  const CanvasUiState({
    this.tool = CanvasTool.mark,
    this.meaning = Meaning.claim,
    this.inkWidth = InkPalette.defaultWidth,
    this.inkColor = InkPalette.warmInk,
    this.erasePartial = false,
    this.extractOpen,
    this.extractWidth = 340,
    this.filter = ExtractFilter.all,
  });

  final CanvasTool tool;
  final Meaning meaning;

  /// Pen size in dp (1 to 8) and colour (ARGB) for the Ink tool.
  final double inkWidth;
  final int inkColor;

  /// Erase only the part of a stroke under the eraser (off: whole strokes).
  final bool erasePartial;

  /// null means "use the layout's default" (open in landscape, closed in portrait).
  final bool? extractOpen;
  final double extractWidth;
  final ExtractFilter filter;

  CanvasUiState copyWith({
    CanvasTool? tool,
    Meaning? meaning,
    double? inkWidth,
    int? inkColor,
    bool? erasePartial,
    bool? extractOpen,
    double? extractWidth,
    ExtractFilter? filter,
  }) => CanvasUiState(
    tool: tool ?? this.tool,
    meaning: meaning ?? this.meaning,
    inkWidth: inkWidth ?? this.inkWidth,
    inkColor: inkColor ?? this.inkColor,
    erasePartial: erasePartial ?? this.erasePartial,
    extractOpen: extractOpen ?? this.extractOpen,
    extractWidth: extractWidth ?? this.extractWidth,
    filter: filter ?? this.filter,
  );
}

class CanvasUiNotifier extends Notifier<CanvasUiState> {
  static const double minExtract = 280, maxExtract = 480;

  @override
  CanvasUiState build() => const CanvasUiState();

  void setTool(CanvasTool t) => state = state.copyWith(tool: t);

  /// Picking a meaning also switches to Mark (prototype behaviour).
  void setMeaning(Meaning m) =>
      state = state.copyWith(meaning: m, tool: CanvasTool.mark);

  void setInkWidth(double w) => state = state.copyWith(
    inkWidth: w.clamp(InkPalette.minWidth, InkPalette.maxWidth),
  );

  void setErasePartial(bool v) => state = state.copyWith(erasePartial: v);

  void setInkColor(int argb) => state = state.copyWith(inkColor: argb);

  void setExtractOpen(bool v) => state = state.copyWith(extractOpen: v);

  void setExtractWidth(double w) =>
      state = state.copyWith(extractWidth: w.clamp(minExtract, maxExtract));

  void setFilter(ExtractFilter f) => state = state.copyWith(filter: f);
}

final canvasUiProvider = NotifierProvider<CanvasUiNotifier, CanvasUiState>(
  CanvasUiNotifier.new,
);
