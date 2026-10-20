import 'dart:io' show Directory, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'features/canvas/palette.dart';
import 'core/hlc/hlc.dart';
import 'data/db/database.dart';
import 'data/db/drift_op_store.dart';
import 'data/pdf/pdf_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  _registerFontLicenses();
  // Debug and profile builds: let the app create its external files folder so
  // `adb push` test PDFs there are readable by it (a folder created by the
  // shell before the app exists is not).
  if (!kReleaseMode && Platform.isAndroid) await getExternalStorageDirectory();
  final db = await openAetherDatabase();
  final support = await getApplicationSupportDirectory();
  final storage = await PdfStorage.open(
    Directory(p.join(support.path, 'library')),
  );
  await storage.sweepPartials(); // leftovers of an interrupted import
  final clock = HlcClock(
    await db.deviceId(),
    last: await DriftOpStore(db).latestHlc(),
  );
  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        pdfStorageProvider.overrideWithValue(storage),
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
