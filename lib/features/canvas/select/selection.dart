import 'package:flutter/foundation.dart';

enum MarkKind { highlight, ink, note }

/// A mark, by kind and id.
@immutable
class MarkRef {
  const MarkRef(this.kind, this.id);
  final MarkKind kind;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is MarkRef && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => 'MarkRef(${kind.name} $id)';
}

/// The marks selected with the Select tool.
class SelectionState extends ChangeNotifier {
  Set<MarkRef> _refs = {};

  Set<MarkRef> get refs => _refs;
  bool get isEmpty => _refs.isEmpty;
  int get count => _refs.length;
  bool contains(MarkRef r) => _refs.contains(r);

  Iterable<String> idsOf(MarkKind k) => [
    for (final r in _refs)
      if (r.kind == k) r.id,
  ];

  void set(Iterable<MarkRef> refs) {
    final next = refs.toSet();
    if (setEquals(next, _refs)) return;
    _refs = next;
    notifyListeners();
  }

  void clear() => set(const []);

  /// Drops marks that no longer exist (deleted, or undone away).
  void prune(bool Function(MarkRef) exists) {
    final keep = _refs.where(exists).toSet();
    if (keep.length != _refs.length) {
      _refs = keep;
      notifyListeners();
    }
  }
}
