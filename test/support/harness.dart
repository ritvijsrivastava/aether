import 'package:aether/app/app.dart';
import 'package:aether/app/providers.dart';
import 'package:aether/domain/model/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSettings extends SettingsNotifier {
  FakeSettings([this.initial = const AppSettings()]);
  final AppSettings initial;

  @override
  Future<AppSettings> build() async => initial;

  @override
  Future<void> setThemeMode(ThemeMode m) async =>
      state = AsyncData((state.value ?? initial).copyWith(themeMode: m));

  @override
  Future<void> setFingerDraws(bool v) async =>
      state = AsyncData((state.value ?? initial).copyWith(fingerDraws: v));

  @override
  Future<void> setLeftHanded(bool v) async =>
      state = AsyncData((state.value ?? initial).copyWith(leftHanded: v));
}

/// Pumps the real app (router, theme, providers) with no database.
Future<void> pumpApp(
  WidgetTester tester, {
  required Size size,
  String location = '/',
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
  List<Document> docs = const [],
  AppSettings settings = const AppSettings(),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        settingsProvider.overrideWith(() => FakeSettings(settings)),
        documentsProvider.overrideWith((ref) async => docs),
      ],
      child: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
          platformBrightness: brightness,
        ),
        child: AetherApp(initialLocation: location),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}
