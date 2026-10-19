import 'dart:ui' show Size;

import 'package:pdfrx/pdfrx.dart';

import 'tile_math.dart';
import 'tile_scheduler.dart';

/// Renders tiles with pdfium (through pdfrx, which runs it off the UI
/// thread). Each tile is one partial render of a page at a fixed scale.
class PdfiumTileRenderer implements TileRenderer {
  PdfiumTileRenderer(this.document);

  final PdfDocument document;

  @override
  Future<TileImage?> render(TileKey key, CancelToken token) async {
    if (token.isCanceled) return null;
    final page = document.pages[key.page];
    final g = TileGeometry(Size(page.width, page.height), key.lod);
    final px = g.pixelRect(key.tx, key.ty);

    final pdfToken = page.createCancellationToken();
    token.onCancel(pdfToken.cancel);

    PdfImage? raw;
    try {
      raw = await page.render(
        x: px.left.round(),
        y: px.top.round(),
        width: px.width.round(),
        height: px.height.round(),
        fullWidth: g.fullWidth,
        fullHeight: g.fullHeight,
        backgroundColor: 0xffffffff,
        flags: PdfPageRenderFlags.limitedImageCache,
        cancellationToken: pdfToken,
      );
      if (raw == null || token.isCanceled) return null;
      // Upload runs on the engine's IO and raster threads, not the UI thread.
      final image = await raw.createImage();
      if (token.isCanceled) {
        image.dispose();
        return null;
      }
      return TileImage(image);
    } finally {
      raw?.dispose();
    }
  }
}
