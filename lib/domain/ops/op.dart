import 'package:meta/meta.dart';

import '../../core/hlc/hlc.dart';

enum EntityKind { document, page, mark, link, category }

enum OpKind { create, setField, delete, restore }

/// An operation before it is stamped with an id, clock value and device.
@immutable
class OpDraft {
  const OpDraft.create(this.entityKind, this.entityId)
    : kind = OpKind.create,
      field = null,
      value = null;

  const OpDraft.set(
    this.entityKind,
    this.entityId,
    String this.field,
    this.value,
  ) : kind = OpKind.setField;

  const OpDraft.delete(this.entityKind, this.entityId)
    : kind = OpKind.delete,
      field = null,
      value = null;

  const OpDraft.restore(this.entityKind, this.entityId)
    : kind = OpKind.restore,
      field = null,
      value = null;

  final EntityKind entityKind;
  final String entityId;
  final OpKind kind;
  final String? field;

  /// JSON-encodable: null, bool, num, String, List or Map thereof.
  final Object? value;
}

/// One immutable entry in the append-only operation log.
@immutable
class Op {
  const Op({
    required this.opId,
    required this.hlc,
    required this.entityKind,
    required this.entityId,
    required this.kind,
    required this.txGroupId,
    this.field,
    this.value,
    this.undoOf,
  });

  factory Op.fromJson(Map<String, Object?> j) => Op(
    opId: j['opId']! as String,
    hlc: Hlc.parse(j['hlc']! as String),
    entityKind: EntityKind.values.byName(j['entityKind']! as String),
    entityId: j['entityId']! as String,
    kind: OpKind.values.byName(j['kind']! as String),
    txGroupId: j['txGroupId']! as String,
    field: j['field'] as String?,
    value: j['value'],
    undoOf: j['undoOf'] as String?,
  );

  final String opId;
  final Hlc hlc;
  final EntityKind entityKind;
  final String entityId;
  final OpKind kind;

  /// Groups the ops of one user action so undo is atomic.
  final String txGroupId;
  final String? field;
  final Object? value;

  /// For an undo transaction: the [txGroupId] it reverses.
  final String? undoOf;

  Map<String, Object?> toJson() => {
    'opId': opId,
    'hlc': hlc.encode(),
    'entityKind': entityKind.name,
    'entityId': entityId,
    'kind': kind.name,
    'txGroupId': txGroupId,
    if (field != null) 'field': field,
    if (value != null) 'value': value,
    if (undoOf != null) 'undoOf': undoOf,
  };
}
