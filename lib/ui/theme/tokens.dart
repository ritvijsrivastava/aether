import 'package:flutter/material.dart';

/// Design tokens from DESIGN.md. The single source of truth for colour,
/// shape, depth and type; Material's ColorScheme and TextTheme are derived
/// from these in `theme.dart`.
@immutable
class AetherTokens extends ThemeExtension<AetherTokens> {
  const AetherTokens({
    required this.brightness,
    required this.desk,
    required this.canvas,
    required this.panel,
    required this.paper,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.ruleStrong,
    required this.hairline,
    required this.hoverWash,
    required this.gridDot,
    required this.indigo,
    required this.indigoPressed,
    required this.indigoWash,
    required this.indigoText,
    required this.onIndigo,
    required this.danger,
    required this.shadowColor,
  });

  final Brightness brightness;

  // Surfaces.
  final Color desk, canvas, panel, paper;

  // Text and lines.
  final Color ink, inkMuted, inkFaint, ruleStrong, hairline, hoverWash, gridDot;

  // The one chrome accent.
  final Color indigo, indigoPressed, indigoWash, indigoText, onIndigo;

  /// Destructive actions and errors. Not in the prototype; derived from its
  /// only red (the link hover colour) and a lifted variant for dark.
  final Color danger;

  /// Base colour for all shadows (warm brown in light, black in dark).
  final Color shadowColor;

  // Meaning colours: identical in both themes, reserved for user marks.
  static const Color claim = Color(0xFFF4877E);
  static const Color method = Color(0xFFF2C94C);
  static const Color question = Color(0xFF6FB1EE);
  static const Color notePaper = Color(0xFFFDF0B5);

  /// Text on a meaning colour or on [notePaper]. Always dark, in both themes.
  static const Color onMark = Color(0xFF2B2723);

  // Radii.
  static const double rHighlight = 5;
  static const double rPaper = 8;
  static const double rSelection = 10;
  static const double rCard = 14;
  static const double rTool = 16;
  static const double rPanel = 24;
  static const double rPill = 999;

  // Spacing (4 px base).
  static const double s1 = 4, s2 = 8, s3 = 12, s4 = 16, s6 = 24;

  /// Minimum touch target on every platform (Material, 48 dp).
  static const double minTarget = 48;

  // Motion.
  static const Duration medium = Duration(milliseconds: 200);

  bool get isDark => brightness == Brightness.dark;

  // Shadows (DESIGN.md "Shadow Vocabulary").
  List<BoxShadow> get float => [
    BoxShadow(
      color: shadowColor.withValues(alpha: isDark ? .45 : .16),
      blurRadius: 16,
      offset: const Offset(0, 2),
    ),
  ];

  List<BoxShadow> get paperShadow => [
    BoxShadow(
      color: shadowColor.withValues(alpha: isDark ? .35 : .08),
      blurRadius: 6,
      offset: const Offset(0, 2),
    ),
    BoxShadow(
      color: shadowColor.withValues(alpha: isDark ? .45 : .12),
      blurRadius: 32,
      offset: const Offset(0, 12),
    ),
  ];

  List<BoxShadow> get sticky => [
    BoxShadow(
      color: shadowColor.withValues(alpha: isDark ? .35 : .10),
      blurRadius: 4,
      offset: const Offset(0, 2),
    ),
    BoxShadow(
      color: shadowColor.withValues(alpha: isDark ? .45 : .14),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];

  List<BoxShadow> get handle => [
    BoxShadow(
      color: shadowColor.withValues(alpha: isDark ? .45 : .18),
      blurRadius: 6,
      offset: const Offset(0, 1),
    ),
  ];

  List<BoxShadow> get action => [
    BoxShadow(
      color: shadowColor.withValues(alpha: isDark ? .55 : .25),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  static const light = AetherTokens(
    brightness: Brightness.light,
    desk: Color(0xFFF6F3EE),
    canvas: Color(0xFFECE8E1),
    panel: Color(0xFFFBF9F6),
    paper: Color(0xFFFFFDFA),
    ink: Color(0xFF2B2723),
    inkMuted: Color(0xFF605D5D),
    inkFaint: Color(0xFF6F6B6B), // darkened from the prototype's #7d7979 for AA
    ruleStrong: Color(0xFFBAB6B6),
    hairline: Color(0x1F3C3228),
    hoverWash: Color(0x123C3228),
    gridDot: Color(0x333C3228),
    indigo: Color(0xFF5B5BD6),
    indigoPressed: Color(0xFF4A4AC0),
    indigoWash: Color(0xFFE6E6FB),
    indigoText: Color(0xFF3D3DBD),
    onIndigo: Color(0xFFF6F3EE),
    danger: Color(0xFFAE1800),
    shadowColor: Color(0xFF3C3228),
  );

  static const dark = AetherTokens(
    brightness: Brightness.dark,
    desk: Color(0xFF201E1D),
    canvas: Color(0xFF2A2827),
    panel: Color(0xFF2D2B2A),
    paper: Color(0xFFFFFDFA), // pages stay white in dark mode (decided)
    ink: Color(0xFFF3F2F2),
    inkMuted: Color(0xFFBAB6B6),
    inkFaint: Color(0xFF9A9696),
    ruleStrong: Color(0xFF605D5D),
    hairline: Color(0x1FF3F2F2),
    hoverWash: Color(0x14F3F2F2),
    gridDot: Color(0x29F3F2F2),
    indigo: Color(0xFF9D9DF2),
    indigoPressed: Color(0xFF8888E6),
    indigoWash: Color(0xFF3A3A63),
    indigoText: Color(0xFFA5A5F5),
    onIndigo: Color(0xFF1B1A2E),
    danger: Color(0xFFFF9783),
    shadowColor: Color(0xFF000000),
  );

  @override
  AetherTokens copyWith({Brightness? brightness}) =>
      brightness == Brightness.dark ? dark : light;

  @override
  AetherTokens lerp(ThemeExtension<AetherTokens>? other, double t) {
    if (other is! AetherTokens) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AetherTokens(
      brightness: t < .5 ? brightness : other.brightness,
      desk: l(desk, other.desk),
      canvas: l(canvas, other.canvas),
      panel: l(panel, other.panel),
      paper: l(paper, other.paper),
      ink: l(ink, other.ink),
      inkMuted: l(inkMuted, other.inkMuted),
      inkFaint: l(inkFaint, other.inkFaint),
      ruleStrong: l(ruleStrong, other.ruleStrong),
      hairline: l(hairline, other.hairline),
      hoverWash: l(hoverWash, other.hoverWash),
      gridDot: l(gridDot, other.gridDot),
      indigo: l(indigo, other.indigo),
      indigoPressed: l(indigoPressed, other.indigoPressed),
      indigoWash: l(indigoWash, other.indigoWash),
      indigoText: l(indigoText, other.indigoText),
      onIndigo: l(onIndigo, other.onIndigo),
      danger: l(danger, other.danger),
      shadowColor: l(shadowColor, other.shadowColor),
    );
  }
}

extension AetherTokensContext on BuildContext {
  AetherTokens get tokens => Theme.of(this).extension<AetherTokens>()!;
}
