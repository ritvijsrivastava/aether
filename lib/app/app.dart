import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/library/import/import_flow.dart';
import '../features/library/import/pdf_importer.dart';
import '../ui/theme/theme.dart';
import '../ui/theme/tokens.dart';
import 'drop_zone.dart';
import 'incoming_files.dart';
import 'providers.dart';
import 'router.dart';

class AetherApp extends ConsumerStatefulWidget {
  const AetherApp({
    super.key,
    this.initialLocation = '/',
    this.listenForFiles = true,
  });

  final String initialLocation;

  /// Listen for PDFs sent to the app (Android). Off in tests.
  final bool listenForFiles;

  @override
  ConsumerState<AetherApp> createState() => _AetherAppState();
}

class _AetherAppState extends ConsumerState<AetherApp> {
  late final GoRouter _router = buildRouter(
    initialLocation: widget.initialLocation,
  );
  StreamSubscription<ImportRequest>? _incoming;

  // Files sent together arrive one by one; gather them into a single import.
  final List<ImportRequest> _batch = [];
  Timer? _batchTimer;

  @override
  void initState() {
    super.initState();
    if (widget.listenForFiles && Platform.isAndroid) {
      _incoming = IncomingFiles.stream().listen(_collect);
    }
  }

  void _collect(ImportRequest r) {
    _batch.add(r);
    _batchTimer?.cancel();
    _batchTimer = Timer(const Duration(milliseconds: 400), () {
      final requests = List.of(_batch);
      _batch.clear();
      _import(requests);
    });
  }

  void _import(List<ImportRequest> requests) {
    final context = rootNavigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    runImport(context: context, ref: ref, requests: requests);
  }

  void _rejected() {
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(content: Text('Only PDF files can be imported.')),
      );
  }

  @override
  void dispose() {
    _incoming?.cancel();
    _batchTimer?.cancel();
    super.dispose();
  }

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
      builder: (context, child) => DropZone(
        onFiles: (paths) => _import([for (final p in paths) ImportRequest(p)]),
        onRejected: _rejected,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
