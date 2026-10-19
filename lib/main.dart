import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'data/db/database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  _registerFontLicenses();
  // Debug and profile builds: let the app create its external files folder so
  // `adb push` test PDFs there are readable by it (a folder created by the
  // shell before the app exists is not).
  if (!kReleaseMode && Platform.isAndroid) await getExternalStorageDirectory();
  final db = await openAetherDatabase();
  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
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
