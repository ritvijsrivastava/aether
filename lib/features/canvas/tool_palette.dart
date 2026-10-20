import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/aether_icon.dart';
import '../../ui/widgets/panel_surface.dart';
import '../../ui/widgets/tool_button.dart';
import 'canvas_ui_state.dart';
import 'erase/erase_options.dart' show EraseClearActions;
import 'tool_panel.dart';

/// The tool buttons, in a column or a row; the content of the movable rail.
class ToolRail extends ConsumerWidget {
  const ToolRail({super.key, this.direction = Axis.vertical});

  final Axis direction;

  static const double button = 48, gap = 2, pad = AetherTokens.s1;

  /// The rail's outer width.
  static const double width = button + pad * 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(canvasUiProvider);
    Widget at(int i) => ToolButton(
      icon: CanvasTool.values[i].icon,
      label: CanvasTool.values[i].label,
      size: button,
      tooltip: '${CanvasTool.values[i].tip} (${CanvasTool.values[i].key})',
      selected: ui.tool == CanvasTool.values[i],
      onPressed: () =>
          ref.read(canvasUiProvider.notifier).pressTool(CanvasTool.values[i]),
    );
    final children = [
      for (var i = 0; i < CanvasTool.values.length; i++) ...[
        if (i > 0) const SizedBox(width: gap, height: gap),
        at(i),
      ],
    ];
    return direction == Axis.vertical
        ? Column(mainAxisSize: MainAxisSize.min, children: children)
        : Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

/// The floating tool rail with a grip handle on top: the user drags it
/// anywhere on the board, and very near the bottom edge it lies down
/// horizontally. The active tool's options hang off it wherever it is.
class MovableToolRail extends ConsumerStatefulWidget {
  const MovableToolRail({super.key, this.onClear});

  final EraseClearActions? onClear;

  @override
  ConsumerState<MovableToolRail> createState() => _MovableToolRailState();
}

class _MovableToolRailState extends ConsumerState<MovableToolRail> {
  /// Top-left of the whole control, kept across rebuilds; null until the
  /// first build puts it in its home corner.
  Offset? _pos;

  /// Height of the grip strip on top of the buttons.
  static const double _handleH = 16;

  /// Within this distance of the bottom edge the rail lies down.
  static const double _bottomZone = 160;

  /// The control's outer size in [direction] order: grip, pad, then buttons.
  Size _controlSize(Axis railDirection) {
    final n = CanvasTool.values.length;
    final buttons = railDirection == Axis.vertical
        ? Size(ToolRail.button, n * ToolRail.button + (n - 1) * ToolRail.gap)
        : Size(n * ToolRail.button + (n - 1) * ToolRail.gap, ToolRail.button);
    return Size(
      math.max(buttons.width, ToolRail.button) + ToolRail.pad * 2,
      buttons.height + ToolRail.pad * 2 + _handleH,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(canvasUiProvider);
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final size = MediaQuery.sizeOf(context);

    final standing = _controlSize(Axis.vertical);
    final lying = _controlSize(Axis.horizontal);
    var pos = _pos ?? _home(size, settings.leftHanded);
    // Very near the bottom edge the rail lies down; elsewhere it stands.
    final liesDown = size.height - (pos.dy + standing.height) < _bottomZone;
    final ctrl = liesDown ? lying : standing;
    pos = Offset(
      pos.dx.clamp(8.0, math.max(8.0, size.width - ctrl.width - 8)),
      pos.dy.clamp(8.0, math.max(8.0, size.height - ctrl.height - 8)),
    );
    final railDirection = liesDown ? Axis.horizontal : Axis.vertical;

    return Stack(
      children: [
        Positioned(
          left: pos.dx,
          top: pos.dy,
          width: ctrl.width,
          height: ctrl.height,
          child: PanelSurface(
            padding: const EdgeInsets.all(ToolRail.pad),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MouseRegion(
                  cursor: SystemMouseCursors.move,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) => setState(() {
                      _pos =
                          (_pos ?? _home(size, settings.leftHanded)) + d.delta;
                    }),
                    child: SizedBox(
                      height: _handleH,
                      child: Center(
                        child: Transform.rotate(
                          angle: railDirection == Axis.vertical
                              ? math.pi / 2
                              : 0,
                          child: AetherIcon(
                            AetherIcons.more,
                            size: 14,
                            color: context.tokens.inkFaint,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                ToolRail(direction: railDirection),
              ],
            ),
          ),
        ),
        // The tool's options follow the rail: beside it when it stands,
        // above it when it lies.
        if (ui.tool.hasPanel)
          liesDown
              ? Positioned(
                  left: pos.dx.clamp(8.0, math.max(8.0, size.width - 280)),
                  bottom: size.height - pos.dy + AetherTokens.s2,
                  child: ToolPanel(onClear: widget.onClear),
                )
              : Positioned(
                  left: pos.dx + ctrl.width / 2 < size.width / 2
                      ? pos.dx + ctrl.width + AetherTokens.s2
                      : null,
                  right: pos.dx + ctrl.width / 2 < size.width / 2
                      ? null
                      : size.width - pos.dx + AetherTokens.s2,
                  top:
                      (pos.dy +
                              _handleH +
                              ToolRail.pad +
                              ui.tool.index * (ToolRail.button + ToolRail.gap))
                          .clamp(8.0, math.max(8.0, size.height - 160)),
                  child: ToolPanel(onClear: widget.onClear),
                ),
      ],
    );
  }

  Offset _home(Size size, bool leftHanded) => leftHanded
      ? Offset(size.width - ToolRail.width - AetherTokens.s3, AetherTokens.s3)
      : const Offset(AetherTokens.s3, AetherTokens.s3);
}

/// Phone bottom toolbar: four primary tools and a "More" tray.
class BottomToolbar extends ConsumerWidget {
  const BottomToolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(canvasUiProvider);
    final t = context.tokens;
    final primary = CanvasTool.values.where((e) => e.isPrimary);
    final moreSelected = !ui.tool.isPrimary;
    return Material(
      color: t.panel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.hairline)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AetherTokens.s1,
              vertical: AetherTokens.s1,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final tool in primary)
                  ToolButton(
                    icon: tool.icon,
                    label: tool.label,
                    tooltip: tool.tip,
                    selected: ui.tool == tool,
                    onPressed: () =>
                        ref.read(canvasUiProvider.notifier).pressTool(tool),
                  ),
                ToolButton(
                  icon: ui.tool.isPrimary
                      ? 'M12 12h.01M19 12h.01M5 12h.01'
                      : ui.tool.icon,
                  label: moreSelected ? ui.tool.label : 'More',
                  tooltip: 'More tools',
                  selected: moreSelected,
                  onPressed: () => showMoreTools(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet with the tools that do not fit on the phone toolbar.
Future<void> showMoreTools(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final ui = ref.watch(canvasUiProvider);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Wrap(
              spacing: AetherTokens.s2,
              runSpacing: AetherTokens.s2,
              children: [
                for (final tool in CanvasTool.values.where((e) => !e.isPrimary))
                  ToolButton(
                    icon: tool.icon,
                    label: tool.label,
                    tooltip: tool.tip,
                    selected: ui.tool == tool,
                    onPressed: () {
                      ref.read(canvasUiProvider.notifier).setTool(tool);
                      Navigator.of(context).pop();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
