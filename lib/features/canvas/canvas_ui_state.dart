import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/widgets/aether_icon.dart';
import 'palette.dart';

export 'palette.dart' show InkPalette, ToolColours;

enum CanvasTool {
  pan('Pan', 'Move around', AetherIcons.pan, 'H'),
  ink('Ink', 'Write or draw', AetherIcons.pen, 'P'),
  erase('Erase', 'Erase', AetherIcons.eraser, 'E'),
  select(
    'Select',
    'Circle strokes to move, recolor or delete them',
    AetherIcons.lasso,
    'S',
  );

  const CanvasTool(this.label, this.tip, this.icon, this.key);
  final String label, tip, icon, key;

  /// Ink and Erase have an options panel (colours, size, ...).
  bool get hasPanel => this == ink || this == erase;

  /// The tools kept on a phone's bottom bar; the rest live under "More".
  bool get isPrimary => this == ink || this == erase || this == select;
}

class CanvasUiState {
  const CanvasUiState({
    this.tool = CanvasTool.ink,
    this.inkWidth = InkPalette.defaultWidth,
    this.inkColors = ToolColours.inkDefault,
    this.erasePartial = false,
    this.collapsedPanels = const <CanvasTool>{},
  });

  final CanvasTool tool;

  /// Pen size in dp (1 to 8) and colour (ARGB) for the Ink tool.
  final double inkWidth;
  final ToolColours inkColors;
  int get inkColor => inkColors.current;

  /// Tools whose options panel is folded away to a small chip.
  final Set<CanvasTool> collapsedPanels;

  /// Erase only the part of a stroke under the eraser (off: whole strokes).
  final bool erasePartial;

  CanvasUiState copyWith({
    CanvasTool? tool,
    double? inkWidth,
    ToolColours? inkColors,
    bool? erasePartial,
    Set<CanvasTool>? collapsedPanels,
  }) => CanvasUiState(
    tool: tool ?? this.tool,
    inkWidth: inkWidth ?? this.inkWidth,
    inkColors: inkColors ?? this.inkColors,
    erasePartial: erasePartial ?? this.erasePartial,
    collapsedPanels: collapsedPanels ?? this.collapsedPanels,
  );
}

class CanvasUiNotifier extends Notifier<CanvasUiState> {
  bool _touchedInk = false;

  @override
  CanvasUiState build() {
    _restore();
    return const CanvasUiState();
  }

  /// Brings back the ink colours of the last session, unless one was already
  /// picked since launch.
  Future<void> _restore() async {
    final store = ref.read(paletteStoreProvider);
    final ink = ToolColours.decode(await store.read(_inkKey));
    if (!ref.mounted) return;
    state = state.copyWith(inkColors: _touchedInk ? null : ink);
  }

  static const _inkKey = 'palette.ink.v2';

  /// Picks a tool and shows its options (a tool's panel is open whenever the
  /// tool is chosen).
  void setTool(CanvasTool t) => state = state.copyWith(
    tool: t,
    collapsedPanels: {
      for (final c in state.collapsedPanels)
        if (c != t) c,
    },
  );

  /// A press on a tool button: picks the tool; pressing the tool already in
  /// use shows or hides its options (SPEC 22.1).
  void pressTool(CanvasTool t) {
    if (state.tool == t && t.hasPanel) {
      togglePanel(t);
    } else {
      setTool(t);
    }
  }

  /// Folds the panel of [t] away if it is open, opens it if folded.
  void togglePanel(CanvasTool t) =>
      setPanelCollapsed(t, !state.collapsedPanels.contains(t));

  void setPanelCollapsed(CanvasTool t, bool collapsed) {
    if (!t.hasPanel || state.collapsedPanels.contains(t) == collapsed) return;
    state = state.copyWith(
      collapsedPanels: {
        for (final c in state.collapsedPanels)
          if (c != t) c,
        if (collapsed) t,
      },
    );
  }

  void setInkWidth(double w) => state = state.copyWith(
    inkWidth: w.clamp(InkPalette.minWidth, InkPalette.maxWidth),
  );

  void setErasePartial(bool v) => state = state.copyWith(erasePartial: v);

  Timer? _saveTimer;

  /// A colour being dragged in the picker: the pen changes at once and the
  /// choice is stored once it settles (no saved colour is added).
  void setInkLive(int argb) {
    _touchedInk = true;
    state = state.copyWith(inkColors: state.inkColors.withCurrent(argb));
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _persistInk);
  }

  /// Tapping a saved colour: it becomes the pen.
  void pickSavedInk(int argb) {
    _touchedInk = true;
    state = state.copyWith(inkColors: state.inkColors.withCurrent(argb));
    _persistInk();
  }

  /// The "+" next to Saved colours: keeps the current colour.
  void saveInkColour() {
    _touchedInk = true;
    state = state.copyWith(inkColors: state.inkColors.savingCurrent());
    _persistInk();
  }

  void _persistInk() =>
      ref.read(paletteStoreProvider).write(_inkKey, state.inkColors.encode());

  void setInkColor(int argb) {
    _touchedInk = true;
    state = state.copyWith(inkColors: state.inkColors.use(argb));
    ref.read(paletteStoreProvider).write(_inkKey, state.inkColors.encode());
  }
}

final canvasUiProvider = NotifierProvider<CanvasUiNotifier, CanvasUiState>(
  CanvasUiNotifier.new,
);
