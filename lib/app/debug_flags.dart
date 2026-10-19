/// Absolute path of a PDF to open from the library in debug builds, set with
/// `--dart-define=AETHER_DEBUG_PDF=/path/file.pdf`. Stand-in for the file
/// picker until import lands (2c). Empty means the button is hidden.
const String kDebugPdfPath = String.fromEnvironment('AETHER_DEBUG_PDF');
