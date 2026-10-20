import 'package:aether/features/canvas/tool_palette.dart';
import 'package:aether/ui/widgets/panel_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/harness.dart';

/// The rail's drag grip: the only GestureDetector that pans.
final grip = find.byKey(const Key('rail-grip'));

ToolRail rail(WidgetTester tester) =>
    tester.widget<ToolRail>(find.byType(ToolRail));

void main() {
  testWidgets('the rail stands until standing would pass the bottom edge, '
      'then lies down and stands again', (tester) async {
    await pumpApp(tester, size: const Size(900, 600), location: '/doc/board');
    expect(rail(tester).direction, Axis.vertical);
    await tester.drag(grip, const Offset(0, 600)); // to the bottom edge
    await tester.pump();
    expect(rail(tester).direction, Axis.horizontal, reason: 'cannot stand');
    await tester.drag(grip, const Offset(0, -600)); // away from the edge
    await tester.pump();
    expect(rail(tester).direction, Axis.vertical, reason: 'fits standing');
  });

  testWidgets('dragging to the bottom parks the rail on the bottom edge', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(900, 600), location: '/doc/board');
    await tester.drag(grip, const Offset(0, 600));
    await tester.pump();
    expect(rail(tester).direction, Axis.horizontal, reason: 'moved at all');
    final railSurface = find.ancestor(
      of: find.byType(ToolRail),
      matching: find.byType(PanelSurface),
    );
    final at = tester.getTopLeft(railSurface);
    // Lying height: pad 4 + button 48 + pad 4 = 56; the bottom edge is 8 away.
    expect(at.dy, 600 - 8 - 56, reason: 'pinned at the bottom edge');
  });

  testWidgets('the rail never leaves the screen', (tester) async {
    await pumpApp(tester, size: const Size(900, 600), location: '/doc/board');
    await tester.drag(grip, const Offset(-800, -400));
    await tester.pump();
    final box = tester.getTopLeft(find.byType(PanelSurface).first);
    expect(box.dx >= 8 && box.dy >= 8, isTrue, reason: '$box');
    await tester.drag(grip, const Offset(1600, 800));
    await tester.pump();
    final size = tester.getSize(find.byType(PanelSurface).first);
    final at = tester.getTopLeft(find.byType(PanelSurface).first);
    expect(at.dx + size.width <= 892, isTrue, reason: '$at $size');
    expect(at.dy + size.height <= 592, isTrue, reason: '$at $size');
  });
}
