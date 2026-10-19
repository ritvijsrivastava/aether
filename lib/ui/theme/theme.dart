import 'package:flutter/material.dart';

import 'tokens.dart';

const String kUiFont = 'Figtree';
const String kDocFont = 'SourceSerif4';

/// Role-based text styles from DESIGN.md. Sizes are logical px and scale with
/// the system font size. Nothing is below 12.
class AetherText {
  const AetherText(this.color);
  final Color color;

  TextStyle _s(double size, FontWeight w, {double? height, double? ls}) =>
      TextStyle(
        fontFamily: kUiFont,
        fontSize: size,
        fontWeight: w,
        height: height,
        letterSpacing: ls,
        color: color,
      );

  TextStyle get wordmark => _s(18, FontWeight.w700, ls: -.27);
  TextStyle get panelTitle => _s(20, FontWeight.w700, ls: -.3);
  TextStyle get title => _s(14, FontWeight.w600);
  TextStyle get body => _s(14, FontWeight.w400, height: 1.45);
  TextStyle get label => _s(12, FontWeight.w600);
  TextStyle get button => _s(13, FontWeight.w700);
  TextStyle get caption => _s(12, FontWeight.w400);
  TextStyle get documentBody =>
      TextStyle(fontFamily: kDocFont, fontSize: 17, height: 1.65, color: color);
}

ThemeData buildTheme(AetherTokens t) {
  final dark = t.isDark;
  final scheme = ColorScheme(
    brightness: t.brightness,
    primary: t.indigo,
    onPrimary: t.onIndigo,
    primaryContainer: t.indigoWash,
    onPrimaryContainer: t.indigoText,
    secondary: t.ink,
    onSecondary: t.desk,
    secondaryContainer: t.canvas,
    onSecondaryContainer: t.ink,
    tertiary: t.indigoText,
    onTertiary: t.panel,
    error: t.danger,
    onError: dark ? const Color(0xFF3B0A02) : Colors.white,
    surface: t.panel,
    onSurface: t.ink,
    onSurfaceVariant: t.inkMuted,
    surfaceContainerLowest: t.paper,
    surfaceContainerLow: t.desk,
    surfaceContainer: t.panel,
    surfaceContainerHigh: t.panel,
    surfaceContainerHighest: t.canvas,
    outline: t.inkFaint,
    outlineVariant: t.hairline,
    shadow: t.shadowColor,
    scrim: Colors.black,
    inverseSurface: t.ink,
    onInverseSurface: t.desk,
    inversePrimary: t.indigoText,
    surfaceTint: Colors.transparent,
  );

  final txt = AetherText(t.ink);
  final textTheme = TextTheme(
    headlineSmall: txt.wordmark,
    titleLarge: txt.panelTitle,
    titleMedium: txt.title,
    titleSmall: txt.title,
    bodyLarge: txt.body.copyWith(fontSize: 16),
    bodyMedium: txt.body,
    bodySmall: txt.caption.copyWith(color: t.inkMuted),
    labelLarge: txt.button,
    labelMedium: txt.label,
    labelSmall: txt.label,
  );

  const pill = StadiumBorder();
  const buttonPadding = EdgeInsets.symmetric(horizontal: 14);

  return ThemeData(
    useMaterial3: true,
    brightness: t.brightness,
    colorScheme: scheme,
    fontFamily: kUiFont,
    textTheme: textTheme,
    scaffoldBackgroundColor: t.desk,
    canvasColor: t.desk,
    dividerColor: t.hairline,
    dividerTheme: DividerThemeData(color: t.hairline, thickness: 1, space: 1),
    splashFactory: InkRipple.splashFactory,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    extensions: [t],
    focusColor: t.indigo.withValues(alpha: .24),
    hoverColor: t.hoverWash,
    highlightColor: t.hoverWash,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      },
    ),
    filledButtonTheme: FilledButtonThemeData(
      style:
          FilledButton.styleFrom(
            backgroundColor: t.indigo,
            foregroundColor: t.onIndigo,
            textStyle: txt.button,
            shape: pill,
            minimumSize: const Size(0, 38),
            padding: buttonPadding,
            tapTargetSize: MaterialTapTargetSize.padded,
          ).copyWith(
            overlayColor: WidgetStatePropertyAll(
              t.onIndigo.withValues(alpha: .12),
            ),
          ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.ink,
        textStyle: txt.button,
        shape: pill,
        side: BorderSide(color: t.hairline),
        minimumSize: const Size(0, 38),
        padding: buttonPadding,
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.indigoText,
        textStyle: txt.button,
        shape: pill,
        minimumSize: const Size(0, 38),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: t.ink,
        minimumSize: const Size(AetherTokens.minTarget, AetherTokens.minTarget),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: pill,
      side: BorderSide.none,
      backgroundColor: t.canvas,
      selectedColor: t.ink,
      labelStyle: txt.label,
      secondaryLabelStyle: txt.label.copyWith(color: t.desk),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 6),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        textStyle: txt.label,
        foregroundColor: t.ink,
        side: BorderSide(color: t.hairline),
        selectedBackgroundColor: t.indigoWash,
        selectedForegroundColor: t.indigoText,
        minimumSize: const Size(0, AetherTokens.minTarget),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.onIndigo : t.inkMuted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.indigo : t.canvas,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) =>
            s.contains(WidgetState.selected) ? Colors.transparent : t.inkFaint,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.panel,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AetherTokens.rPanel),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: t.ink,
      contentTextStyle: txt.body.copyWith(color: t.desk),
      actionTextColor: dark ? t.indigoPressed : const Color(0xFFB9B9FF),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AetherTokens.rCard)),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: t.ink,
        borderRadius: BorderRadius.circular(AetherTokens.rSelection),
      ),
      textStyle: txt.label.copyWith(color: t.desk),
      waitDuration: const Duration(milliseconds: 500),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.panel,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AetherTokens.rPanel)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: t.panel,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AetherTokens.rCard)),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: t.desk,
      foregroundColor: t.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
  );
}
