import 'dart:ui' show Brightness;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/model/models.dart';

/// Where the colours are kept between launches. The default keeps them in
/// memory only (tests); the app overrides it with the settings table.
abstract interface class PaletteStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class MemoryPaletteStore implements PaletteStore {
  final Map<String, String> _m = {};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
}

final paletteStoreProvider = Provider<PaletteStore>(
  (ref) => MemoryPaletteStore(),
);

/// The pen's colours: the one in use now, and the saved ones beside it.
class ToolColours {
  const ToolColours(this.current, this.recent);

  static const int max = 8;

  final int current;

  /// Saved colours, newest first, no duplicates, at most [max].
  final List<int> recent;

  /// [c] becomes the current colour and moves to the front of the recents.
  ToolColours use(int c) => ToolColours(
    c,
    [c, ...recent.where((r) => r != c)].take(max).toList(growable: false),
  );

  /// [c] becomes the current colour; the saved ones stay as they are.
  ToolColours withCurrent(int c) => ToolColours(c, recent);

  /// The current colour is added to the saved ones (an "auto" pen is not).
  ToolColours savingCurrent() => current == InkPalette.auto
      ? this
      : ToolColours(
          current,
          [
            current,
            ...recent.where((r) => r != current),
          ].take(max).toList(growable: false),
        );

  /// `current;r1,r2,...` in decimal.
  String encode() => '$current;${recent.join(',')}';

  static ToolColours? decode(String? s) {
    if (s == null) return null;
    final parts = s.split(';');
    final cur = int.tryParse(parts.first);
    if (cur == null) return null;
    final recent = <int>[
      if (parts.length > 1)
        for (final p in parts[1].split(','))
          if (int.tryParse(p) != null) int.parse(p),
    ];
    return ToolColours(cur, recent.take(max).toList(growable: false));
  }

  @override
  bool operator ==(Object other) =>
      other is ToolColours &&
      other.current == current &&
      other.recent.length == recent.length &&
      [for (var i = 0; i < recent.length; i++) recent[i] == other.recent[i]]
          .every((e) => e);

  @override
  int get hashCode => Object.hash(current, Object.hashAll(recent));

  /// Ink starts on "auto" (white on the dark board, near-black on the light
  /// one) with three colours beside it.
  static const ToolColours inkDefault = ToolColours(InkPalette.auto, [
    InkPalette.auto,
    Swatch.coral,
    Swatch.amber,
    Swatch.blue,
  ]);
}

abstract final class InkPalette {
  /// Near-black, the pen on a light board.
  static const int warmInk = 0xFF2B2723;

  /// White, the pen on a dark board.
  static const int paperWhite = 0xFFFFFFFF;

  /// "Follow the board": a stand-in (never a real colour, it is fully
  /// transparent) that [resolve] turns into black or white by theme. Stored in
  /// the palette so a theme change flips an unpicked pen; strokes always store
  /// the resolved colour.
  static const int auto = 0;

  static int resolve(int argb, Brightness b) =>
      argb != auto ? argb : (b == Brightness.dark ? paperWhite : warmInk);

  static const double minWidth = 1, maxWidth = 8, defaultWidth = 2.5;
}
