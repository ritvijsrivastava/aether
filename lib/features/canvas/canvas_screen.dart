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
import 'canvas_view.dart';
import 'engine/canvas_controller.dart';
import 'engine/page_surface.dart';
import 'engine/scene.dart';
import 'engine/view_state.dart';
import 'perf_hud.dart';
import 'tool_palette.dart';
import 'zoom_pill.dart';

/// Test documents that need no PDF: `/doc/synthetic-30`, `/doc/synthetic-500`.
/// Numbered placeholder pages of mixed sizes, for judging the engine.
const String syntheticPrefix = 'synthetic-';

int? syntheticCount(String docId) => docId.startsWith(syntheticPrefix)
    ? int.tryParse(docId.substring(syntheticPrefix.length))
    : null;

Scene syntheticScene(int pages) {
  const letter = Size(612, 792),
      landscape = Size(792, 612),
      a4 = Size(595, 842);
  return Scene.column([
    for (var i = 0; i < pages; i++)
      i % 11 == 10 ? landscape : (i % 7 == 6 ? a4 : letter),
  ]);
}

/// The document workspace. Layout adapts to the window class:
/// compact = full-bleed canvas + bottom toolbar + Extract sheet;
/// medium/expanded = tool rail + side Extract panel.
class CanvasScreen extends ConsumerStatefulWidget {
  const CanvasScreen({super.key, required this.docId});
  final String docId;

  @override
  ConsumerState<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends ConsumerState<CanvasScreen>
    with SingleTickerProviderStateMixin {
  late final CanvasController _controller;
  late final PageSurface _surface;

  @override
  void initState() {
    super.initState();
    final n = syntheticCount(widget.docId);
    _controller = CanvasController(
      scene: n == null ? const Scene([]) : syntheticScene(n),
    )..attach(this);
    _surface = SyntheticPageSurface();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final cls = WindowClass.of(size.width);
    final ui = ref.watch(canvasUiProvider);
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final landscape = size.width > size.height;
    final extractOpen =
        ui.extractOpen ?? (cls == WindowClass.expanded || landscape);

    // Fit and zoom aim at the area the floating controls leave free.
    _controller.insets = cls == WindowClass.compact
        ? const EdgeInsets.only(top: 64, bottom: 84)
        : EdgeInsets.fromLTRB(
            settings.leftHanded ? 0 : 88,
            24, // room for the drag handle above the page
            settings.leftHanded ? 88 : 0,
            56, // room for the zoom pill
          );

    final docs = ref.watch(documentsProvider).value ?? const [];
    final doc = docs.where((d) => d.id == widget.docId).firstOrNull;
    final n = syntheticCount(widget.docId);
    final title =
        doc?.title ?? (n != null ? 'Synthetic test, $n pages' : 'Document');
    final pages = doc?.pageCount ?? n ?? 0;

    final canvasView = CanvasView(
      controller: _controller,
      surface: _surface,
      tool: ui.tool,
      fingerDraws: settings.fingerDraws,
      onReady: _controller.fitFirst,
    );
    final canvas = settings.perfHud
        ? Stack(
            fit: StackFit.expand,
            children: [
              canvasView,
              const Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.only(top: AetherTokens.s2),
                  child: PerfHud(),
                ),
              ),
            ],
          )
        : canvasView;

    return Scaffold(
      body: Column(
        children: [
          CanvasTopBar(
            windowClass: cls,
            title: title,
            pageCount: pages,
            extractVisible: extractOpen,
          ),
          Expanded(
            child: cls == WindowClass.compact
                ? _CompactBody(controller: _controller, canvas: canvas)
                : _WideBody(
                    controller: _controller,
                    canvas: canvas,
                    expanded: cls == WindowClass.expanded,
                    extractOpen: extractOpen,
                    leftHanded: settings.leftHanded,
                  ),
          ),
        ],
      ),
    );
  }
}

class _Zoom extends StatelessWidget {
  const _Zoom(this.controller);
  final CanvasController controller;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ViewState>(
    valueListenable: controller.view,
    builder: (context, v, _) => ZoomPill(
      zoom: v.zoom,
      onZoomOut: () => controller.zoomBy(0.8),
      onZoomIn: () => controller.zoomBy(1.25),
      onFit: controller.fitPage,
    ),
  );
}

class _WideBody extends ConsumerWidget {
  const _WideBody({
    required this.controller,
    required this.canvas,
    required this.expanded,
    required this.extractOpen,
    required this.leftHanded,
  });

  final CanvasController controller;
  final Widget canvas;
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
          Positioned.fill(child: canvas),
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
            child: _Zoom(controller),
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
              child: const PanelSurface(child: ExtractPanel()),
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
      padding: const EdgeInsets.all(AetherTokens.s3),
      child: Row(children: children),
    );
  }
}

class _CompactBody extends ConsumerWidget {
  const _CompactBody({required this.controller, required this.canvas});
  final CanvasController controller;
  final Widget canvas;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(canvasUiProvider);
    final open = ui.extractOpen ?? false;
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: canvas),
              Positioned(
                top: AetherTokens.s3,
                right: AetherTokens.s3,
                child: _Zoom(controller),
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
