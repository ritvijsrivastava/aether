import 'dart:math' as math;

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:meta/meta.dart';

import '../canvas_ui_state.dart';

/// Which barrel-button bits mean "erase while held".
///
/// The bits differ per device (measured in M0): the S Pen's one button is
/// bit 2; a Wacom pen's first button is bit 4 and its second is bit 2. A
/// Wacom button is only visible once the tip is down, so the button is read at
/// pointer-down and holds for that stroke.
@immutable
class PenButtonMap {
  const PenButtonMap({required this.eraseMask});

  /// Any of these bits set in `PointerEvent.buttons` selects Erase.
  final int eraseMask;

  bool isErase(int buttons) => buttons & eraseMask != 0;

  /// Samsung S Pen: its single side button is bit 2.
  static const sPen = PenButtonMap(eraseMask: 0x2);

  /// Wacom on Linux: button 1 is bit 4 (button 2, bit 2, is left unassigned).
  static const wacom = PenButtonMap(eraseMask: 0x4);

  static PenButtonMap forPlatform(TargetPlatform p) =>
      p == TargetPlatform.android ? sPen : wacom;
}

/// How raw pressure becomes line width.
///
/// Real strokes rarely pass 0.6 (the S Pen's light writing is about 0.1 to
/// 0.4), so the curve reaches full width at [peak] and bends by [gamma]
/// (below 1 makes light pressure count for more: the "soft" default).
@immutable
class PressureCurve {
  const PressureCurve({this.peak = 0.6, this.gamma = 0.7, this.floor = 0.2});

  /// Pressure that gives full width.
  final double peak;

  /// Exponent; below 1 is softer, above 1 firmer.
  final double gamma;

  /// Width factor at zero pressure, so a stroke never vanishes.
  final double floor;

  static const soft = PressureCurve();
  static const medium = PressureCurve(peak: 0.8, gamma: 1.0);
  static const firm = PressureCurve(peak: 1.0, gamma: 1.4);

  /// Width factor in [floor, 1] for a pressure in [0, 1].
  double apply(double pressure) {
    final x = (pressure / peak).clamp(0.0, 1.0);
    return floor + (1 - floor) * math.pow(x, gamma);
  }
}

/// Everything about the pen that is a preference or a device quirk, in one
/// place so it can be tuned on the tablet without touching the logic.
@immutable
class PenConfig {
  const PenConfig({
    this.buttons = PenButtonMap.sPen,
    this.pressure = PressureCurve.soft,
  });

  factory PenConfig.forPlatform(TargetPlatform p) =>
      PenConfig(buttons: PenButtonMap.forPlatform(p));

  final PenButtonMap buttons;
  final PressureCurve pressure;

  /// The tool a pointer applies: the eraser end, or the barrel button held at
  /// pointer-down, means Erase whatever tool is chosen; anything else uses the
  /// chosen tool. It lasts for that one stroke.
  CanvasTool resolveTool(
    CanvasTool chosen,
    PointerDeviceKind kind,
    int buttons,
  ) {
    if (kind == PointerDeviceKind.invertedStylus) return CanvasTool.erase;
    if (kind == PointerDeviceKind.stylus && this.buttons.isErase(buttons)) {
      return CanvasTool.erase;
    }
    return chosen;
  }
}
