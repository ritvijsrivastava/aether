import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../ui/adaptive/window_class.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/panel_surface.dart';
import '../extract/extract_panel.dart';
import 'canvas_top_bar.dart';
import 'canvas_ui_state.dart';
import 'specimen_stage.dart';
import 'tool_palette.dart';
import 'zoom_pill.dart';

/// The document workspace. Layout adapts to the window class:
/// compact = full-bleed canvas + bottom toolbar + Extract sheet;
/// medium/expanded = tool rail + side Extract panel.
class CanvasScreen extends ConsumerWidget {
  const CanvasScreen({super.key, required this.docId});
  final String docId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.sizeOf(context);
    final cls = WindowClass.of(size.width);
    final ui = ref.watch(canvasUiProvider);
    final left = ref.watch(settingsProvider).value?.leftHanded ?? false;
    final landscape = size.width > size.height;
    final extractOpen =
        ui.extractOpen ?? (cls == WindowClass.expanded || landscape);

    final docs = ref.watch(documentsProvider).value ?? const [];
    final doc = docs.where((d) => d.id == docId).firstOrNull;
    final title = doc?.title ?? 'Design specimen';
    final pages = doc?.pageCount ?? 0;

    final bar = CanvasTopBar(
      windowClass: cls,
      title: title,
      pageCount: pages,
      extractVisible: extractOpen,
    );

    return Scaffold(
      body: Column(
        children: [
          bar,
          Expanded(
            child: cls == WindowClass.compact
                ? const _CompactBody()
                : _WideBody(
                    expanded: cls == WindowClass.expanded,
                    extractOpen: extractOpen,
                    leftHanded: left,
                  ),
          ),
        ],
      ),
    );
  }
}

class _WideBody extends ConsumerWidget {
  const _WideBody({
    required this.expanded,
    required this.extractOpen,
    required this.leftHanded,
  });

  final bool expanded, extractOpen, leftHanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(canvasUiProvider);
    final width = MediaQuery.sizeOf(context).width;
    // Never let the panel starve the canvas on a narrow window.
    final panelW = math.min(ui.extractWidth, math.max(240.0, width * .45));

    final stage = ClipRRect(
      borderRadius: BorderRadius.circular(AetherTokens.rPanel),
      child: Stack(
        children: [
          const Positioned.fill(
            child: SpecimenStage(leftInset: 88, topInset: 8),
          ),
          Positioned(
            left: leftHanded ? null : AetherTokens.s4,
            right: leftHanded ? AetherTokens.s4 : null,
            top: AetherTokens.s4,
            bottom: AetherTokens.s4,
            child: const Align(
              alignment: Alignment.topCenter,
              child: ToolRail(),
            ),
          ),
          Positioned(
            right: leftHanded ? null : AetherTokens.s4,
            left: leftHanded ? AetherTokens.s4 : null,
            bottom: AetherTokens.s4,
            child: const ZoomPill(),
          ),
        ],
      ),
    );

    final panel = AnimatedContainer(
      duration: AetherTokens.medium,
      curve: Curves.easeOutCubic,
      width: extractOpen ? panelW : 0,
      child: extractOpen
          ? OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: panelW,
              maxWidth: panelW,
              child: PanelSurface(child: const ExtractPanel()),
            )
          : null,
    );

    final handle = expanded && extractOpen
        ? MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) => ref
                  .read(canvasUiProvider.notifier)
                  .setExtractWidth(
                    ui.extractWidth + (leftHanded ? d.delta.dx : -d.delta.dx),
                  ),
              child: const SizedBox(
                width: AetherTokens.s3,
                height: double.infinity,
              ),
            ),
          )
        : const SizedBox(width: AetherTokens.s3);

    final children = leftHanded
        ? [panel, handle, Expanded(child: stage)]
        : [Expanded(child: stage), handle, panel];

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AetherTokens.s3,
        AetherTokens.s3,
        extractOpen ? AetherTokens.s3 : AetherTokens.s3,
        AetherTokens.s3,
      ),
      child: Row(children: children),
    );
  }
}

class _CompactBody extends ConsumerWidget {
  const _CompactBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(canvasUiProvider);
    final open = ui.extractOpen ?? false;
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              const Positioned.fill(
                child: SpecimenStage(leftInset: 0, topInset: 56),
              ),
              const Positioned(
                top: AetherTokens.s3,
                right: AetherTokens.s3,
                child: ZoomPill(),
              ),
              if (ui.tool == CanvasTool.mark)
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 88,
                  child: Center(child: MeaningStrip()),
                ),
              _ExtractSheet(open: open),
            ],
          ),
        ),
        const BottomToolbar(),
      ],
    );
  }
}

/// Draggable Extract sheet with collapsed, half and full snap points.
class _ExtractSheet extends ConsumerWidget {
  const _ExtractSheet({required this.open});
  final bool open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    return LayoutBuilder(
      builder: (context, box) {
        // A peek tall enough for the drag handle and the title row, and short
        // enough that the filter chips below stay cleanly hidden.
        final peek = (68 / box.maxHeight).clamp(.08, .3);
        return DraggableScrollableSheet(
          initialChildSize: open ? .5 : peek,
          minChildSize: peek,
          maxChildSize: .92,
          snap: true,
          snapSizes: [peek, .5, .92],
          builder: (context, controller) => DecoratedBox(
            decoration: BoxDecoration(
              color: t.panel,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AetherTokens.rPanel),
              ),
              boxShadow: t.float,
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AetherTokens.rPanel),
              ),
              child: ExtractPanel(
                scrollController: controller,
                header: Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10),
                    decoration: BoxDecoration(
                      color: t.inkFaint,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
