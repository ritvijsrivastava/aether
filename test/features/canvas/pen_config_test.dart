import 'package:aether/features/canvas/canvas_ui_state.dart';
import 'package:aether/features/canvas/input/pen_config.dart';
import 'package:aether/features/canvas/input/tool_gestures.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PressureCurve', () {
    test('a stroke never vanishes and never exceeds full width', () {
      for (final c in [
        PressureCurve.soft,
        PressureCurve.medium,
        PressureCurve.firm,
      ]) {
        expect(c.apply(0), closeTo(c.floor, 1e-9));
        expect(c.apply(1), closeTo(1, 1e-9));
        expect(c.apply(5), closeTo(1, 1e-9), reason: 'clamped');
        expect(c.apply(-1), closeTo(c.floor, 1e-9), reason: 'clamped');
      }
    });

    test('is monotonic', () {
      for (final c in [PressureCurve.soft, PressureCurve.firm]) {
        var prev = -1.0;
        for (var i = 0; i <= 100; i++) {
          final w = c.apply(i / 100);
          expect(w, greaterThanOrEqualTo(prev));
          prev = w;
        }
      }
    });

    test(
      'soft reaches full width at a firm press (0.3); firm needs much more',
      () {
        expect(PressureCurve.soft.apply(0.3), closeTo(1, 1e-9));
        expect(PressureCurve.firm.apply(0.3), lessThan(0.6));
      },
    );

    test(
      'natural writing on the S9 (0.06 to 0.2) spans a clear range of widths',
      () {
        // Measured from real strokes: light 0.06, typical 0.12, firm 0.2.
        final light = PressureCurve.soft.apply(0.06);
        final typical = PressureCurve.soft.apply(0.12);
        final firm = PressureCurve.soft.apply(0.2);
        expect(light, inInclusiveRange(0.4, 0.55));
        expect(typical, inInclusiveRange(0.55, 0.75));
        expect(firm, inInclusiveRange(0.75, 0.95));
        expect(
          firm - light,
          greaterThan(0.3),
          reason: 'pressure visibly changes the line',
        );
      },
    );

    test('light pressure counts for more on soft than on firm', () {
      expect(
        PressureCurve.soft.apply(0.2),
        greaterThan(PressureCurve.firm.apply(0.2)),
      );
    });
  });

  group('ToolPoint', () {
    test('no pressure means full width, whatever the curve', () {
      const p = ToolPoint(
        position: Offset.zero,
        time: Duration.zero,
        kind: PointerDeviceKind.mouse,
      );
      expect(p.widthFactor(PressureCurve.firm), 1.0);
    });

    test('pressure goes through the curve', () {
      const p = ToolPoint(
        position: Offset.zero,
        time: Duration.zero,
        kind: PointerDeviceKind.stylus,
        pressure: 0.3,
      );
      expect(p.widthFactor(PressureCurve.soft), PressureCurve.soft.apply(0.3));
    });
  });

  group('PenConfig.resolveTool', () {
    const sPen = PenConfig(buttons: PenButtonMap.sPen);
    const wacom = PenConfig(buttons: PenButtonMap.wacom);
    const stylus = PointerDeviceKind.stylus;

    test('the eraser end always erases', () {
      for (final t in CanvasTool.values) {
        expect(
          sPen.resolveTool(t, PointerDeviceKind.invertedStylus, 1),
          CanvasTool.erase,
        );
      }
    });

    test('the S Pen button is bit 2', () {
      expect(sPen.resolveTool(CanvasTool.ink, stylus, 2), CanvasTool.erase);
      expect(sPen.resolveTool(CanvasTool.ink, stylus, 1), CanvasTool.ink);
      expect(sPen.resolveTool(CanvasTool.ink, stylus, 4), CanvasTool.ink);
    });

    test('the Wacom first button is bit 4, the second does nothing', () {
      expect(wacom.resolveTool(CanvasTool.mark, stylus, 5), CanvasTool.erase);
      expect(wacom.resolveTool(CanvasTool.mark, stylus, 3), CanvasTool.mark);
    });

    test('only a pen uses the button rules', () {
      for (final k in [
        PointerDeviceKind.mouse,
        PointerDeviceKind.touch,
        PointerDeviceKind.trackpad,
      ]) {
        expect(sPen.resolveTool(CanvasTool.mark, k, 2), CanvasTool.mark);
      }
    });

    test('the platform picks the button map', () {
      expect(
        PenButtonMap.forPlatform(TargetPlatform.android).eraseMask,
        PenButtonMap.sPen.eraseMask,
      );
      expect(
        PenButtonMap.forPlatform(TargetPlatform.linux).eraseMask,
        PenButtonMap.wacom.eraseMask,
      );
    });
  });
}
