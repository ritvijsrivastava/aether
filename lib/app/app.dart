import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../ui/theme/theme.dart';
import '../ui/theme/tokens.dart';
import 'providers.dart';
import 'router.dart';

class AetherApp extends ConsumerStatefulWidget {
  const AetherApp({super.key, this.initialLocation = '/'});

  final String initialLocation;

  @override
  ConsumerState<AetherApp> createState() => _AetherAppState();
}

class _AetherAppState extends ConsumerState<AetherApp> {
  late final GoRouter _router = buildRouter(
    initialLocation: widget.initialLocation,
  );

  @override
  Widget build(BuildContext context) {
    final mode =
        ref.watch(settingsProvider).value?.themeMode ?? ThemeMode.system;
    return MaterialApp.router(
      title: 'Aether',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(AetherTokens.light),
      darkTheme: buildTheme(AetherTokens.dark),
      themeMode: mode,
      routerConfig: _router,
    );
  }
}
