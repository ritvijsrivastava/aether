/// Asks the user for a password; returns null if they give up.
typedef PasswordProvider = Future<String?> Function();

/// Passwords of protected PDFs the user has already entered in this session,
/// by content hash, so opening a document just imported does not ask again.
///
/// In memory only: nothing is written to disk, and everything is forgotten
/// when the app closes.
class PdfPasswordCache {
  final Map<String, String> _byHash = {};

  String? of(String hash) => _byHash[hash];

  void forget(String hash) => _byHash.remove(hash);

  /// A password source for opening the PDF with [hash]: the remembered
  /// password first (once), then [prompt]. Call [PasswordAttempt.accepted]
  /// when the PDF opened, so the password that worked is remembered.
  PasswordAttempt attempt(String hash, PasswordProvider prompt) =>
      PasswordAttempt._(this, hash, prompt);
}

class PasswordAttempt {
  PasswordAttempt._(this._cache, this._hash, this._prompt);

  final PdfPasswordCache _cache;
  final String _hash;
  final PasswordProvider _prompt;
  String? _lastTried;
  bool _usedRemembered = false;

  /// How many times the user was prompted (not counting the remembered one).
  int prompts = 0;

  /// Pass to pdfium. Called again, with a different answer, while wrong.
  Future<String?> provide() async {
    final remembered = _cache.of(_hash);
    if (remembered != null && !_usedRemembered) {
      _usedRemembered = true;
      return _lastTried = remembered;
    }
    // A remembered password that no longer works must not stick.
    if (_usedRemembered && _lastTried == remembered) _cache.forget(_hash);
    prompts++;
    return _lastTried = await _prompt();
  }

  /// The PDF opened: remember the password that did it (if one was needed).
  void accepted() {
    final p = _lastTried;
    if (p != null && p.isNotEmpty) _cache._byHash[_hash] = p;
  }
}
