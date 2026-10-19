import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/database.dart';
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

final deviceIdProvider = FutureProvider<String>(
  (ref) => ref.watch(databaseProvider).deviceId(),
);

/// All non-deleted documents. Not reactive yet; invalidate after changes.
final documentsProvider = FutureProvider<List<Document>>((ref) async {
  final all = await ref
      .watch(opStoreProvider)
      .entities(kind: EntityKind.document);
  return [for (final e in all) Document.fromState(e)];
});

@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.fingerDraws = false,
    this.leftHanded = false,
  });

  final ThemeMode themeMode;

  /// A finger normally pans and zooms; when on it also applies the active tool.
  final bool fingerDraws;

  /// Mirrors the tool rail and Extract panel.
  final bool leftHanded;

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? fingerDraws,
    bool? leftHanded,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    fingerDraws: fingerDraws ?? this.fingerDraws,
    leftHanded: leftHanded ?? this.leftHanded,
  );
}

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  static const _theme = 'themeMode';
  static const _finger = 'fingerDraws';
  static const _left = 'leftHanded';

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

  Future<void> setLeftHanded(bool v) async {
    state = AsyncData(_cur.copyWith(leftHanded: v));
    await ref.read(databaseProvider).putSetting(_left, v ? '1' : '0');
  }
}

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
