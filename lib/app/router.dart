import 'package:go_router/go_router.dart';

import '../features/canvas/canvas_screen.dart';
import '../features/library/library_screen.dart';
import '../features/settings/settings_screen.dart';

GoRouter buildRouter({String initialLocation = '/'}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(path: '/', builder: (_, _) => const LibraryScreen()),
    GoRoute(
      path: '/doc/:id',
      builder: (_, state) => CanvasScreen(docId: state.pathParameters['id']!),
    ),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
  ],
);
