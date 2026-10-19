import 'page_text.dart';

/// Where the Mark tool gets a page's text from. Pages are 0-based.
abstract interface class PageTextSource {
  /// The page's text if it is already in memory (so a pointer-down can start a
  /// selection without waiting).
  PageText? peek(int pageIndex);

  /// The page's text, extracting it if needed. Never throws; a page that
  /// cannot be read is [PageText.empty].
  Future<PageText> pageText(int pageIndex);
}
