import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'features/canvas/palette.dart';
import 'core/hlc/hlc.dart';
import 'data/db/database.dart';
import 'data/db/drift_op_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  _registerFontLicenses();
  final db = await openAetherDatabase();
  final clock = HlcClock(
    await db.deviceId(),
    last: await DriftOpStore(db).latestHlc(),
  );
  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        paletteStoreProvider.overrideWithValue(DbPaletteStore(db)),
        hlcClockProvider.overrideWithValue(clock),
      ],
      child: const AetherApp(),
    ),
  );
}

/// Makes the bundled fonts' SIL OFL texts show up in the licenses page.
void _registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (pkg, asset) in [
      ('Figtree', 'assets/fonts/Figtree-OFL.txt'),
      ('Source Serif 4', 'assets/fonts/SourceSerif4-OFL.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([
        pkg,
      ], await rootBundle.loadString(asset));
    }
  });
}
