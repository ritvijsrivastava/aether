import 'package:flutter/foundation.dart';

import '../../../domain/model/models.dart';

/// The notes of the open document, including drafts.
///
/// A *draft* is a note just placed and still empty: it exists on the page and
/// can be typed into, but nothing is saved for it until it has text. A draft
/// that is left empty simply disappears, with no undo step and no trace.
class NotesLayer extends ChangeNotifier {
  final Map<String, Note> _byId = {};
  final Set<String> _drafts = {};

  /// The note whose text field should take the keyboard focus, set when a note
  /// is placed. The note widget clears it once it has focused.
  String? focusId;

  /// The note being edited right now (set by the widget on focus).
  String? editingId;

  Iterable<Note> get all => _byId.values;
  int get count => _byId.length;
  Note? byId(String id) => _byId[id];
  bool isDraft(String id) => _drafts.contains(id);

  List<Note> forPage(String? pageId) => [
    for (final n in _byId.values)
      if (n.pageId == pageId) n,
  ];

  /// Replaces the saved notes (after loading or an undo) and keeps drafts that
  /// have not been saved yet.
  void replaceSaved(Iterable<Note> saved) {
    final keep = {
      for (final id in _drafts)
        if (_byId[id] != null) id: _byId[id]!,
    };
    _byId.clear();
    for (final n in saved) {
      _byId[n.id] = n;
    }
    _byId.addAll(keep);
    notifyListeners();
  }

  void add(Note n, {bool draft = false}) {
    _byId[n.id] = n;
    draft ? _drafts.add(n.id) : _drafts.remove(n.id);
    notifyListeners();
  }

  /// Changes a note's fields.
  void update(Note n) {
    if (!_byId.containsKey(n.id)) return;
    _byId[n.id] = n;
    notifyListeners();
  }

  /// A draft has been saved: it is a real note now.
  void promote(String id) {
    if (_drafts.remove(id)) notifyListeners();
  }

  void remove(String id) {
    if (_byId.remove(id) == null) return;
    _drafts.remove(id);
    if (focusId == id) focusId = null;
    if (editingId == id) editingId = null;
    notifyListeners();
  }

  void requestFocus(String id) {
    focusId = id;
    notifyListeners();
  }

  void focusTaken(String id) {
    if (focusId == id) focusId = null;
  }

  void setEditing(String? id) {
    if (editingId == id) return;
    editingId = id;
    notifyListeners();
  }
}
