import '../features/canvas/palette.dart';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/hlc/hlc.dart';
import '../core/id/id_generator.dart';
import '../data/db/database.dart';
import '../domain/commands/command_bus.dart';
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
/// The device's clock. Overridden in `main()`, where it is seeded with the
/// newest timestamp already in the log so it never goes backwards.
final hlcClockProvider = Provider<HlcClock>(
  (ref) => throw UnimplementedError('hlcClockProvider must be overridden'),
);

final idGeneratorProvider = Provider<IdGenerator>(
  (ref) => const UuidV7Generator(),
);

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
    ids: ref.watch(idGeneratorProvider),
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
    this.leftHanded = false,
    this.perfHud = false,
    this.eraseWidth = 28.0,
  });

  final ThemeMode themeMode;

  /// Mirrors the tool rail.
  final bool leftHanded;

  /// Shows frame times over the canvas (for judging smoothness on a device).
  final bool perfHud;

  /// The eraser's tip diameter in dp (its radius is half of this).
  final double eraseWidth;

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? leftHanded,
    bool? perfHud,
    double? eraseWidth,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    leftHanded: leftHanded ?? this.leftHanded,
    perfHud: perfHud ?? this.perfHud,
    eraseWidth: eraseWidth ?? this.eraseWidth,
  );
}

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  static const _theme = 'themeMode';
  static const _left = 'leftHanded';
  static const _hud = 'perfHud';
  static const _eraseWidth = 'eraseWidth';

  @override
  Future<AppSettings> build() async {
    final db = ref.watch(databaseProvider);
    final theme = await db.setting(_theme);
    return AppSettings(
      themeMode: ThemeMode.values.firstWhere(
        (m) => m.name == theme,
        orElse: () => ThemeMode.system,
      ),
      leftHanded: await db.setting(_left) == '1',
      perfHud: await db.setting(_hud) == '1',
      eraseWidth: double.tryParse(await db.setting(_eraseWidth) ?? '') ?? 28.0,
    );
  }

  AppSettings get _cur => state.value ?? const AppSettings();

  Future<void> setThemeMode(ThemeMode m) async {
    state = AsyncData(_cur.copyWith(themeMode: m));
    await ref.read(databaseProvider).putSetting(_theme, m.name);
  }

  Future<void> setPerfHud(bool v) async {
    state = AsyncData(_cur.copyWith(perfHud: v));
    await ref.read(databaseProvider).putSetting(_hud, v ? '1' : '0');
  }

  Future<void> setLeftHanded(bool v) async {
    state = AsyncData(_cur.copyWith(leftHanded: v));
    await ref.read(databaseProvider).putSetting(_left, v ? '1' : '0');
  }

  Future<void> setEraseWidth(double w) async {
    state = AsyncData(_cur.copyWith(eraseWidth: w));
    await ref.read(databaseProvider).putSetting(_eraseWidth, '$w');
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
