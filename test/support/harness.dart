import 'package:aether/app/app.dart';

import 'dart:io';

import 'package:aether/app/providers.dart';
import 'package:aether/core/hlc/hlc.dart';
import 'package:aether/core/id/id_generator.dart';
import 'package:aether/data/db/database.dart';
import 'package:aether/data/db/drift_op_store.dart';
import 'package:aether/data/pdf/pdf_storage.dart';
import 'package:aether/domain/commands/command.dart';
import 'package:aether/domain/commands/command_bus.dart';
import 'package:aether/domain/ops/op.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:aether/domain/model/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
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
  Future<void> setPerfHud(bool v) async =>
      state = AsyncData((state.value ?? initial).copyWith(perfHud: v));

  @override
  Future<void> setLeftHanded(bool v) async =>
      state = AsyncData((state.value ?? initial).copyWith(leftHanded: v));
}

/// Seeds [docs] into [db] as documents (no pages, no PDF files).
Future<void> seedDocuments(AetherDatabase db, List<Document> docs) async {
  final store = DriftOpStore(db);
  var t = 1000;
  final bus = CommandBus(
    store: store,
    clock: HlcClock('seed', now: () => t++),
    ids: SequentialIdGenerator('seed'),
  );
  final f = CommandFactory(store);
  for (final d in docs) {
    await bus.run(f.create(EntityKind.document, d.id, d.toFields()));
  }
}

/// Pumps the real app (router, theme, providers) over an in-memory database
/// seeded with [docs] and a throwaway library folder.
Future<void> pumpApp(
  WidgetTester tester, {
  required Size size,
  String location = '/',
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
  List<Document> docs = const [],
  AppSettings settings = const AppSettings(),
  AetherDatabase? db,
  List<Override> overrides = const [],

  /// Use this library folder instead of an empty throwaway one.
  PdfStorage? storage,
}) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final database = db ?? AetherDatabase(NativeDatabase.memory());
  if (db == null) addTearDown(database.close);
  final root = Directory.systemTemp.createTempSync('aether_lib_');
  Directory('${root.path}/pdfs').createSync(recursive: true);
  Directory('${root.path}/thumbs').createSync(recursive: true);
  final library = storage ?? PdfStorage(root);
  addTearDown(() => root.deleteSync(recursive: true));
  await tester.runAsync(() => seedDocuments(database, docs));

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
        databaseProvider.overrideWithValue(database),
        pdfStorageProvider.overrideWithValue(library),
        hlcClockProvider.overrideWithValue(HlcClock('test')),
        ...overrides,
      ],
      child: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
          platformBrightness: brightness,
        ),
        child: AetherApp(initialLocation: location, listenForFiles: false),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Pumps with real-time waits between frames until [finder] matches.
///
/// Real file and database I/O does not finish under the fake clock, so each
/// step gives a short real wait (in its own `runAsync`, handing control back
/// in between) and then pumps a frame.
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int maxMs = 5000,
}) async {
  for (var waited = 0; waited < maxMs; waited += 25) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 25));
  }
  fail('Timed out waiting for $finder');
}
