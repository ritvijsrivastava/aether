import '../features/canvas/palette.dart';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/hlc/hlc.dart';
import '../core/id/id_generator.dart';
import '../data/db/database.dart';
import '../data/pdf/pdf_password_cache.dart';
import '../data/pdf/pdf_storage.dart';
import '../domain/commands/command_bus.dart';
import '../features/library/import/pdf_importer.dart';
import '../features/library/import/pdf_inspector.dart';
import '../features/library/import/pdf_picker.dart';
import '../features/library/library_actions.dart';
import '../data/db/drift_op_store.dart';
import '../domain/model/models.dart';
import '../domain/ops/op.dart';
import '../domain/ops/op_store.dart';

/// Overridden in `main()` with the opened on-disk database (and in tests with
/// an in-memory one).
final databaseProvider = Provider<AetherDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);

final opStoreProvider = Provider<OpStore>(
  (ref) => DriftOpStore(ref.watch(databaseProvider)),
);

/// Overridden in `main()` once the library folder exists.
final pdfStorageProvider = Provider<PdfStorage>(
  (ref) => throw UnimplementedError('pdfStorageProvider must be overridden'),
);

/// The device's clock. Overridden in `main()`, where it is seeded with the
/// newest timestamp already in the log so it never goes backwards.
final hlcClockProvider = Provider<HlcClock>(
  (ref) => throw UnimplementedError('hlcClockProvider must be overridden'),
);

final idGeneratorProvider = Provider<IdGenerator>(
  (ref) => const UuidV7Generator(),
);

/// Passwords entered this session, in memory only.
final pdfPasswordsProvider = Provider<PdfPasswordCache>(
  (ref) => PdfPasswordCache(),
);

final pdfInspectorProvider = Provider<PdfInspector>(
  (ref) => const PdfiumInspector(),
);

final pdfPickerProvider = Provider<PdfPicker>((ref) => platformPdfPicker());

/// The command bus for library-level actions (import, rename, delete).
/// Documents open on the canvas have their own, so undo stacks never mix.
final libraryBusProvider = Provider<CommandBus>((ref) {
  final bus = CommandBus(
    store: ref.watch(opStoreProvider),
    clock: ref.watch(hlcClockProvider),
    ids: ref.watch(idGeneratorProvider),
  );
  ref.onDispose(bus.dispose);
  return bus;
});

final libraryActionsProvider = Provider<LibraryActions>(
  (ref) => LibraryActions(
    store: ref.watch(opStoreProvider),
    bus: ref.watch(libraryBusProvider),
  ),
);

final pdfImporterProvider = Provider<PdfImporter>(
  (ref) => PdfImporter(
    store: ref.watch(opStoreProvider),
    bus: ref.watch(libraryBusProvider),
    storage: ref.watch(pdfStorageProvider),
    inspector: ref.watch(pdfInspectorProvider),
    db: ref.watch(databaseProvider),
    ids: ref.watch(idGeneratorProvider),
    passwords: ref.watch(pdfPasswordsProvider),
  ),
);

final deviceIdProvider = FutureProvider<String>(
  (ref) => ref.watch(databaseProvider).deviceId(),
);

/// A document as the library lists it.
@immutable
class LibraryItem {
  const LibraryItem(this.doc, this.added);
  final Document doc;

  /// When it was imported (the time of its first operation).
  final DateTime added;
}

/// All non-deleted documents, newest first. Not reactive yet: invalidate
/// after changes.
final libraryItemsProvider = FutureProvider<List<LibraryItem>>((ref) async {
  final all = await ref
      .watch(opStoreProvider)
      .entities(kind: EntityKind.document);
  final items = [
    for (final e in all)
      LibraryItem(
        Document.fromState(e),
        DateTime.fromMillisecondsSinceEpoch(e.createdHlc?.physicalMs ?? 0),
      ),
  ]..sort((a, b) => b.added.compareTo(a.added));
  return items;
});

final documentsProvider = FutureProvider<List<Document>>(
  (ref) async => [
    for (final i in await ref.watch(libraryItemsProvider.future)) i.doc,
  ],
);

@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.fingerDraws = false,
    this.leftHanded = false,
    this.perfHud = false,
    this.autoHideToolPanel = true,
  });

  final ThemeMode themeMode;

  /// A finger normally pans and zooms; when on it also applies the active tool.
  final bool fingerDraws;

  /// Mirrors the tool rail and Extract panel.
  final bool leftHanded;

  /// Shows frame times over the canvas (for judging smoothness on a device).
  final bool perfHud;

  /// Fold a tool's options away after its first stroke, so they do not
  /// cover the page. Double-tap the tool to bring them back.
  final bool autoHideToolPanel;

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? fingerDraws,
    bool? leftHanded,
    bool? perfHud,
    bool? autoHideToolPanel,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    fingerDraws: fingerDraws ?? this.fingerDraws,
    leftHanded: leftHanded ?? this.leftHanded,
    perfHud: perfHud ?? this.perfHud,
    autoHideToolPanel: autoHideToolPanel ?? this.autoHideToolPanel,
  );
}

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  static const _theme = 'themeMode';
  static const _finger = 'fingerDraws';
  static const _left = 'leftHanded';
  static const _hud = 'perfHud';
  static const _autoHide = 'autoHideToolPanel';

  @override
  Future<AppSettings> build() async {
    final db = ref.watch(databaseProvider);
    final theme = await db.setting(_theme);
    return AppSettings(
      themeMode: ThemeMode.values.firstWhere(
        (m) => m.name == theme,
        orElse: () => ThemeMode.system,
      ),
      fingerDraws: await db.setting(_finger) == '1',
      leftHanded: await db.setting(_left) == '1',
      perfHud: await db.setting(_hud) == '1',
      autoHideToolPanel: await db.setting(_autoHide) != '0',
    );
  }

  AppSettings get _cur => state.value ?? const AppSettings();

  Future<void> setThemeMode(ThemeMode m) async {
    state = AsyncData(_cur.copyWith(themeMode: m));
    await ref.read(databaseProvider).putSetting(_theme, m.name);
  }

  Future<void> setFingerDraws(bool v) async {
    state = AsyncData(_cur.copyWith(fingerDraws: v));
    await ref.read(databaseProvider).putSetting(_finger, v ? '1' : '0');
  }

  Future<void> setPerfHud(bool v) async {
    state = AsyncData(_cur.copyWith(perfHud: v));
    await ref.read(databaseProvider).putSetting(_hud, v ? '1' : '0');
  }

  Future<void> setAutoHideToolPanel(bool v) async {
    state = AsyncData(_cur.copyWith(autoHideToolPanel: v));
    await ref.read(databaseProvider).putSetting(_autoHide, v ? '1' : '0');
  }

  Future<void> setLeftHanded(bool v) async {
    state = AsyncData(_cur.copyWith(leftHanded: v));
    await ref.read(databaseProvider).putSetting(_left, v ? '1' : '0');
  }
}

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

/// Keeps the pen and marker colours in the settings table.
class DbPaletteStore implements PaletteStore {
  DbPaletteStore(this._db);
  final AetherDatabase _db;
  @override
  Future<String?> read(String key) => _db.setting(key);
  @override
  Future<void> write(String key, String value) => _db.putSetting(key, value);
}
