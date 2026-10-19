import 'dart:io' show Platform;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../ui/theme/theme.dart';
import '../ui/theme/tokens.dart';

/// Lets PDFs be dropped onto the window (Linux). Elsewhere it is transparent.
class DropZone extends StatefulWidget {
  const DropZone({
    super.key,
    required this.onFiles,
    this.onRejected,
    required this.child,
  });

  /// Paths of the dropped files that are PDFs.
  final void Function(List<String> pdfPaths) onFiles;

  /// Called when something that is not a PDF was dropped.
  final VoidCallback? onRejected;
  final Widget child;

  /// A local file whose name ends in .pdf. (The drop plugin hands over remote
  /// URIs such as smb:// or http:// as they are; those are not importable.)
  static bool isPdf(String path) =>
      !path.contains('://') && path.toLowerCase().endsWith('.pdf');

  @override
  State<DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends State<DropZone> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isLinux) return widget.child;
    final t = context.tokens;
    return DropTarget(
      onDragEntered: (_) => setState(() => _over = true),
      onDragExited: (_) => setState(() => _over = false),
      onDragDone: (d) {
        setState(() => _over = false);
        final paths = [for (final f in d.files) f.path];
        final pdfs = paths.where(DropZone.isPdf).toList();
        if (pdfs.isEmpty) {
          widget.onRejected?.call();
        } else {
          widget.onFiles(pdfs);
        }
      },
      child: Stack(
        children: [
          widget.child,
          if (_over)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  margin: const EdgeInsets.all(AetherTokens.s3),
                  decoration: BoxDecoration(
                    color: t.indigo.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(AetherTokens.rPanel),
                    border: Border.all(color: t.indigo, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Drop PDFs to import',
                    style: AetherText(t.indigoText).panelTitle,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
