import 'package:flutter/widgets.dart';

/// Material window-size classes, measured on the window (not the device), so
/// Linux window resizing, Android split-screen and foldables all just work.
enum WindowClass {
  /// Under 600 dp: phones.
  compact,

  /// 600 to 1100 dp: tablets, small desktop windows.
  medium,

  /// Over 1100 dp: desktop.
  expanded;

  static const double mediumFrom = 600;
  static const double expandedFrom = 1100;

  static WindowClass of(double width) {
    if (width < mediumFrom) return WindowClass.compact;
    if (width < expandedFrom) return WindowClass.medium;
    return WindowClass.expanded;
  }

  static WindowClass ofContext(BuildContext context) =>
      of(MediaQuery.sizeOf(context).width);
}
