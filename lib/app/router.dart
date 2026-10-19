import 'package:flutter/widgets.dart' show GlobalKey, NavigatorState;
import 'package:go_router/go_router.dart';

import '../features/canvas/canvas_screen.dart';
import '../features/library/library_screen.dart';
import '../features/settings/settings_screen.dart';

/// For showing messages and dialogs from outside any widget (a PDF dropped on
/// the window, or sent to the app).
final rootNavigatorKey = GlobalKey<NavigatorState>();

GoRouter buildRouter({String initialLocation = '/'}) => GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: initialLocation,
  // An unknown location (a stale link, a file URI handed to us by the system)
  // goes to the library rather than an error screen.
  onException: (context, state, router) => router.go('/'),
  routes: [
    GoRoute(path: '/', builder: (_, _) => const LibraryScreen()),
    GoRoute(
      path: '/doc/:id',
      builder: (_, state) => CanvasScreen(docId: state.pathParameters['id']!),
    ),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
  ],
);
