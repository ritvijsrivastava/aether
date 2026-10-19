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

class CanvasUiState {
  const CanvasUiState({
    this.tool = CanvasTool.mark,
    this.meaning = Meaning.claim,
    this.extractOpen,
    this.extractWidth = 340,
    this.filter = ExtractFilter.all,
  });

  final CanvasTool tool;
  final Meaning meaning;

  /// null means "use the layout's default" (open in landscape, closed in portrait).
  final bool? extractOpen;
  final double extractWidth;
  final ExtractFilter filter;

  CanvasUiState copyWith({
    CanvasTool? tool,
    Meaning? meaning,
    bool? extractOpen,
    double? extractWidth,
    ExtractFilter? filter,
  }) => CanvasUiState(
    tool: tool ?? this.tool,
    meaning: meaning ?? this.meaning,
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

  void setExtractOpen(bool v) => state = state.copyWith(extractOpen: v);

  void setExtractWidth(double w) =>
      state = state.copyWith(extractWidth: w.clamp(minExtract, maxExtract));

  void setFilter(ExtractFilter f) => state = state.copyWith(filter: f);
}

final canvasUiProvider = NotifierProvider<CanvasUiNotifier, CanvasUiState>(
  CanvasUiNotifier.new,
);
