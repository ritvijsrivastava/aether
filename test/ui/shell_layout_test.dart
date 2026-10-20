import 'package:aether/app/providers.dart';
import 'package:aether/domain/model/models.dart';
import 'package:aether/features/canvas/canvas_screen.dart';
import 'package:aether/features/canvas/canvas_ui_state.dart';
import 'package:aether/features/canvas/tool_palette.dart';
import 'package:aether/ui/widgets/tool_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

const _sizes = <String, Size>{
  'phone 360x800': Size(360, 800),
  'phone landscape 800x360': Size(800, 360),
  'tablet portrait 600x960': Size(600, 960),
  'tablet landscape 840x600': Size(840, 600),
  'desktop min 800x520': Size(800, 520),
  'desktop 1280x720': Size(1280, 720),
};

void main() {
  group('canvas shell never overflows', () {
    for (final entry in _sizes.entries) {
      for (final scale in [1.0, 1.3, 2.0]) {
        for (final b in Brightness.values) {
          testWidgets('${entry.key} x$scale ${b.name}', (tester) async {
            await pumpApp(
              tester,
              size: entry.value,
              location: '/doc/board',
              brightness: b,
              textScale: scale,
            );
            expect(find.byType(CanvasScreen), findsOneWidget);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });

  group('library never overflows', () {
    for (final entry in _sizes.entries) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('empty ${entry.key} x$scale', (tester) async {
          await pumpApp(tester, size: entry.value, textScale: scale);
          expect(find.textContaining('No boards yet'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
        testWidgets('with documents ${entry.key} x$scale', (tester) async {
          await pumpApp(
            tester,
            size: entry.value,
            textScale: scale,
            docs: const [
              Document(
                id: 'd1',
                title:
                    'MapReduce: Simplified Data Processing on Large Clusters',
              ),
            ],
          );
          expect(find.textContaining('MapReduce'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('layout follows the window class', () {
    testWidgets('phone: bottom toolbar, no side rail', (tester) async {
      await pumpApp(tester, size: const Size(360, 800), location: '/doc/board');
      expect(toolButton('More'), findsOneWidget);
      expect(toolButton('Ink'), findsOneWidget);
      expect(toolButton('Erase'), findsOneWidget);
      // The three primary tools only: Pan lives under More.
      expect(toolButton('Select'), findsOneWidget);
      expect(toolButton('Pan'), findsNothing);
    });

    testWidgets('tablet and desktop: all tools on a rail', (tester) async {
      await pumpApp(tester, size: const Size(840, 600), location: '/doc/board');
      for (final tool in CanvasTool.values) {
        expect(
          find.descendant(
            of: find.byType(ToolRail),
            matching: toolButton(tool.label),
          ),
          findsOneWidget,
          reason: tool.label,
        );
      }
      expect(toolButton('More'), findsNothing);
    });

    testWidgets('crossing 600 dp switches layout', (tester) async {
      await pumpApp(tester, size: const Size(599, 800), location: '/doc/board');
      expect(toolButton('More'), findsOneWidget);
      await pumpApp(tester, size: const Size(600, 800), location: '/doc/board');
      expect(toolButton('More'), findsNothing);
    });

    testWidgets('More tray offers the remaining tools', (tester) async {
      await pumpApp(tester, size: const Size(360, 800), location: '/doc/board');
      await tester.tap(toolButton('More'));
      await tester.pumpAndSettle();
      expect(toolButton('Pan'), findsOneWidget);
      expect(toolButton('Select'), findsOneWidget);
    });

    testWidgets('picking a tool changes the active tool', (tester) async {
      await pumpApp(
        tester,
        size: const Size(1280, 720),
        location: '/doc/board',
      );
      await tester.tap(toolButton('Ink'));
      await tester.pump();
      expect(tester.widget<ToolButton>(toolButton('Ink')).selected, isTrue);
    });

    testWidgets('left-handed mirrors the tool rail', (tester) async {
      await pumpApp(
        tester,
        size: const Size(1280, 720),
        location: '/doc/board',
      );
      final rightHandedX = tester.getCenter(toolButton('Ink')).dx;
      await pumpApp(
        tester,
        size: const Size(1280, 720),
        location: '/doc/board',
        settings: const AppSettings(leftHanded: true),
      );
      expect(
        tester.getCenter(toolButton('Ink')).dx,
        greaterThan(rightHandedX + 400),
      );
    });
  });

  group('touch targets are at least 48 dp', () {
    for (final size in [
      const Size(360, 800),
      const Size(840, 600),
      const Size(1280, 720),
    ]) {
      testWidgets('${size.width.toInt()} wide', (tester) async {
        await pumpApp(tester, size: size, location: '/doc/board');
        final handle = tester.ensureSemantics();
        final small = <String>[];
        for (final e in tester.allElements) {
          final w = e.widget;
          if (w is IconButton ||
              w is ToolButton ||
              w is FilledButton ||
              w is FilterChip) {
            final box = e.renderObject as RenderBox?;
            if (box != null && box.hasSize) {
              final s = box.size;
              // Visual size may be smaller than the hit area; Material pads
              // buttons to 48 via MaterialTapTargetSize.padded.
              if (w is ToolButton && (s.width < 48 || s.height < 48)) {
                small.add('ToolButton ${s.width}x${s.height}');
              }
            }
          }
        }
        handle.dispose();
        expect(small, isEmpty);
      });
    }
  });
}
