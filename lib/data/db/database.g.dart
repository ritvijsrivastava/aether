// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $OpsTable extends Ops with TableInfo<$OpsTable, OpRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OpsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _opIdMeta = const VerificationMeta('opId');
  @override
  late final GeneratedColumn<String> opId = GeneratedColumn<String>(
    'op_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityKindMeta = const VerificationMeta(
    'entityKind',
  );
  @override
  late final GeneratedColumn<String> entityKind = GeneratedColumn<String>(
    'entity_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _opKindMeta = const VerificationMeta('opKind');
  @override
  late final GeneratedColumn<String> opKind = GeneratedColumn<String>(
    'op_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fieldMeta = const VerificationMeta('field');
  @override
  late final GeneratedColumn<String> field = GeneratedColumn<String>(
    'field',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _txGroupIdMeta = const VerificationMeta(
    'txGroupId',
  );
  @override
  late final GeneratedColumn<String> txGroupId = GeneratedColumn<String>(
    'tx_group_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _undoOfMeta = const VerificationMeta('undoOf');
  @override
  late final GeneratedColumn<String> undoOf = GeneratedColumn<String>(
    'undo_of',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    opId,
    hlc,
    deviceId,
    entityKind,
    entityId,
    opKind,
    field,
    value,
    txGroupId,
    undoOf,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ops';
  @override
  VerificationContext validateIntegrity(
    Insertable<OpRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('op_id')) {
      context.handle(
        _opIdMeta,
        opId.isAcceptableOrUnknown(data['op_id']!, _opIdMeta),
      );
    } else if (isInserting) {
      context.missing(_opIdMeta);
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('entity_kind')) {
      context.handle(
        _entityKindMeta,
        entityKind.isAcceptableOrUnknown(data['entity_kind']!, _entityKindMeta),
      );
    } else if (isInserting) {
      context.missing(_entityKindMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('op_kind')) {
      context.handle(
        _opKindMeta,
        opKind.isAcceptableOrUnknown(data['op_kind']!, _opKindMeta),
      );
    } else if (isInserting) {
      context.missing(_opKindMeta);
    }
    if (data.containsKey('field')) {
      context.handle(
        _fieldMeta,
        field.isAcceptableOrUnknown(data['field']!, _fieldMeta),
      );
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    }
    if (data.containsKey('tx_group_id')) {
      context.handle(
        _txGroupIdMeta,
        txGroupId.isAcceptableOrUnknown(data['tx_group_id']!, _txGroupIdMeta),
      );
    } else if (isInserting) {
      context.missing(_txGroupIdMeta);
    }
    if (data.containsKey('undo_of')) {
      context.handle(
        _undoOfMeta,
        undoOf.isAcceptableOrUnknown(data['undo_of']!, _undoOfMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {opId};
  @override
  OpRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OpRow(
      opId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}op_id'],
      )!,
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      entityKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_kind'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      opKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}op_kind'],
      )!,
      field: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}field'],
      ),
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      ),
      txGroupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tx_group_id'],
      )!,
      undoOf: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}undo_of'],
      ),
    );
  }

  @override
  $OpsTable createAlias(String alias) {
    return $OpsTable(attachedDatabase, alias);
  }
}

class OpRow extends DataClass implements Insertable<OpRow> {
  final String opId;
  final String hlc;
  final String deviceId;
  final String entityKind;
  final String entityId;
  final String opKind;
  final String? field;

  /// JSON-encoded value (null for non-setField ops).
  final String? value;
  final String txGroupId;
  final String? undoOf;
  const OpRow({
    required this.opId,
    required this.hlc,
    required this.deviceId,
    required this.entityKind,
    required this.entityId,
    required this.opKind,
    this.field,
    this.value,
    required this.txGroupId,
    this.undoOf,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['op_id'] = Variable<String>(opId);
    map['hlc'] = Variable<String>(hlc);
    map['device_id'] = Variable<String>(deviceId);
    map['entity_kind'] = Variable<String>(entityKind);
    map['entity_id'] = Variable<String>(entityId);
    map['op_kind'] = Variable<String>(opKind);
    if (!nullToAbsent || field != null) {
      map['field'] = Variable<String>(field);
    }
    if (!nullToAbsent || value != null) {
      map['value'] = Variable<String>(value);
    }
    map['tx_group_id'] = Variable<String>(txGroupId);
    if (!nullToAbsent || undoOf != null) {
      map['undo_of'] = Variable<String>(undoOf);
    }
    return map;
  }

  OpsCompanion toCompanion(bool nullToAbsent) {
    return OpsCompanion(
      opId: Value(opId),
      hlc: Value(hlc),
      deviceId: Value(deviceId),
      entityKind: Value(entityKind),
      entityId: Value(entityId),
      opKind: Value(opKind),
      field: field == null && nullToAbsent
          ? const Value.absent()
          : Value(field),
      value: value == null && nullToAbsent
          ? const Value.absent()
          : Value(value),
      txGroupId: Value(txGroupId),
      undoOf: undoOf == null && nullToAbsent
          ? const Value.absent()
          : Value(undoOf),
    );
  }

  factory OpRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OpRow(
      opId: serializer.fromJson<String>(json['opId']),
      hlc: serializer.fromJson<String>(json['hlc']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      entityKind: serializer.fromJson<String>(json['entityKind']),
      entityId: serializer.fromJson<String>(json['entityId']),
      opKind: serializer.fromJson<String>(json['opKind']),
      field: serializer.fromJson<String?>(json['field']),
      value: serializer.fromJson<String?>(json['value']),
      txGroupId: serializer.fromJson<String>(json['txGroupId']),
      undoOf: serializer.fromJson<String?>(json['undoOf']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'opId': serializer.toJson<String>(opId),
      'hlc': serializer.toJson<String>(hlc),
      'deviceId': serializer.toJson<String>(deviceId),
      'entityKind': serializer.toJson<String>(entityKind),
      'entityId': serializer.toJson<String>(entityId),
      'opKind': serializer.toJson<String>(opKind),
      'field': serializer.toJson<String?>(field),
      'value': serializer.toJson<String?>(value),
      'txGroupId': serializer.toJson<String>(txGroupId),
      'undoOf': serializer.toJson<String?>(undoOf),
    };
  }

  OpRow copyWith({
    String? opId,
    String? hlc,
    String? deviceId,
    String? entityKind,
    String? entityId,
    String? opKind,
    Value<String?> field = const Value.absent(),
    Value<String?> value = const Value.absent(),
    String? txGroupId,
    Value<String?> undoOf = const Value.absent(),
  }) => OpRow(
    opId: opId ?? this.opId,
    hlc: hlc ?? this.hlc,
    deviceId: deviceId ?? this.deviceId,
    entityKind: entityKind ?? this.entityKind,
    entityId: entityId ?? this.entityId,
    opKind: opKind ?? this.opKind,
    field: field.present ? field.value : this.field,
    value: value.present ? value.value : this.value,
    txGroupId: txGroupId ?? this.txGroupId,
    undoOf: undoOf.present ? undoOf.value : this.undoOf,
  );
  OpRow copyWithCompanion(OpsCompanion data) {
    return OpRow(
      opId: data.opId.present ? data.opId.value : this.opId,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      entityKind: data.entityKind.present
          ? data.entityKind.value
          : this.entityKind,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      opKind: data.opKind.present ? data.opKind.value : this.opKind,
      field: data.field.present ? data.field.value : this.field,
      value: data.value.present ? data.value.value : this.value,
      txGroupId: data.txGroupId.present ? data.txGroupId.value : this.txGroupId,
      undoOf: data.undoOf.present ? data.undoOf.value : this.undoOf,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OpRow(')
          ..write('opId: $opId, ')
          ..write('hlc: $hlc, ')
          ..write('deviceId: $deviceId, ')
          ..write('entityKind: $entityKind, ')
          ..write('entityId: $entityId, ')
          ..write('opKind: $opKind, ')
          ..write('field: $field, ')
          ..write('value: $value, ')
          ..write('txGroupId: $txGroupId, ')
          ..write('undoOf: $undoOf')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    opId,
    hlc,
    deviceId,
    entityKind,
    entityId,
    opKind,
    field,
    value,
    txGroupId,
    undoOf,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OpRow &&
          other.opId == this.opId &&
          other.hlc == this.hlc &&
          other.deviceId == this.deviceId &&
          other.entityKind == this.entityKind &&
          other.entityId == this.entityId &&
          other.opKind == this.opKind &&
          other.field == this.field &&
          other.value == this.value &&
          other.txGroupId == this.txGroupId &&
          other.undoOf == this.undoOf);
}

class OpsCompanion extends UpdateCompanion<OpRow> {
  final Value<String> opId;
  final Value<String> hlc;
  final Value<String> deviceId;
  final Value<String> entityKind;
  final Value<String> entityId;
  final Value<String> opKind;
  final Value<String?> field;
  final Value<String?> value;
  final Value<String> txGroupId;
  final Value<String?> undoOf;
  final Value<int> rowid;
  const OpsCompanion({
    this.opId = const Value.absent(),
    this.hlc = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.entityKind = const Value.absent(),
    this.entityId = const Value.absent(),
    this.opKind = const Value.absent(),
    this.field = const Value.absent(),
    this.value = const Value.absent(),
    this.txGroupId = const Value.absent(),
    this.undoOf = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OpsCompanion.insert({
    required String opId,
    required String hlc,
    required String deviceId,
    required String entityKind,
    required String entityId,
    required String opKind,
    this.field = const Value.absent(),
    this.value = const Value.absent(),
    required String txGroupId,
    this.undoOf = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : opId = Value(opId),
       hlc = Value(hlc),
       deviceId = Value(deviceId),
       entityKind = Value(entityKind),
       entityId = Value(entityId),
       opKind = Value(opKind),
       txGroupId = Value(txGroupId);
  static Insertable<OpRow> custom({
    Expression<String>? opId,
    Expression<String>? hlc,
    Expression<String>? deviceId,
    Expression<String>? entityKind,
    Expression<String>? entityId,
    Expression<String>? opKind,
    Expression<String>? field,
    Expression<String>? value,
    Expression<String>? txGroupId,
    Expression<String>? undoOf,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (opId != null) 'op_id': opId,
      if (hlc != null) 'hlc': hlc,
      if (deviceId != null) 'device_id': deviceId,
      if (entityKind != null) 'entity_kind': entityKind,
      if (entityId != null) 'entity_id': entityId,
      if (opKind != null) 'op_kind': opKind,
      if (field != null) 'field': field,
      if (value != null) 'value': value,
      if (txGroupId != null) 'tx_group_id': txGroupId,
      if (undoOf != null) 'undo_of': undoOf,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OpsCompanion copyWith({
    Value<String>? opId,
    Value<String>? hlc,
    Value<String>? deviceId,
    Value<String>? entityKind,
    Value<String>? entityId,
    Value<String>? opKind,
    Value<String?>? field,
    Value<String?>? value,
    Value<String>? txGroupId,
    Value<String?>? undoOf,
    Value<int>? rowid,
  }) {
    return OpsCompanion(
      opId: opId ?? this.opId,
      hlc: hlc ?? this.hlc,
      deviceId: deviceId ?? this.deviceId,
      entityKind: entityKind ?? this.entityKind,
      entityId: entityId ?? this.entityId,
      opKind: opKind ?? this.opKind,
      field: field ?? this.field,
      value: value ?? this.value,
      txGroupId: txGroupId ?? this.txGroupId,
      undoOf: undoOf ?? this.undoOf,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (opId.present) {
      map['op_id'] = Variable<String>(opId.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (entityKind.present) {
      map['entity_kind'] = Variable<String>(entityKind.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (opKind.present) {
      map['op_kind'] = Variable<String>(opKind.value);
    }
    if (field.present) {
      map['field'] = Variable<String>(field.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (txGroupId.present) {
      map['tx_group_id'] = Variable<String>(txGroupId.value);
    }
    if (undoOf.present) {
      map['undo_of'] = Variable<String>(undoOf.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OpsCompanion(')
          ..write('opId: $opId, ')
          ..write('hlc: $hlc, ')
          ..write('deviceId: $deviceId, ')
          ..write('entityKind: $entityKind, ')
          ..write('entityId: $entityId, ')
          ..write('opKind: $opKind, ')
          ..write('field: $field, ')
          ..write('value: $value, ')
          ..write('txGroupId: $txGroupId, ')
          ..write('undoOf: $undoOf, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EntitiesTable extends Entities
    with TableInfo<$EntitiesTable, EntityRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EntitiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _docIdMeta = const VerificationMeta('docId');
  @override
  late final GeneratedColumn<String> docId = GeneratedColumn<String>(
    'doc_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pageIdMeta = const VerificationMeta('pageId');
  @override
  late final GeneratedColumn<String> pageId = GeneratedColumn<String>(
    'page_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _markTypeMeta = const VerificationMeta(
    'markType',
  );
  @override
  late final GeneratedColumn<String> markType = GeneratedColumn<String>(
    'mark_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bx0Meta = const VerificationMeta('bx0');
  @override
  late final GeneratedColumn<double> bx0 = GeneratedColumn<double>(
    'bx0',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _by0Meta = const VerificationMeta('by0');
  @override
  late final GeneratedColumn<double> by0 = GeneratedColumn<double>(
    'by0',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bx1Meta = const VerificationMeta('bx1');
  @override
  late final GeneratedColumn<double> bx1 = GeneratedColumn<double>(
    'bx1',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _by1Meta = const VerificationMeta('by1');
  @override
  late final GeneratedColumn<double> by1 = GeneratedColumn<double>(
    'by1',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fieldsMeta = const VerificationMeta('fields');
  @override
  late final GeneratedColumn<String> fields = GeneratedColumn<String>(
    'fields',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fieldHlcsMeta = const VerificationMeta(
    'fieldHlcs',
  );
  @override
  late final GeneratedColumn<String> fieldHlcs = GeneratedColumn<String>(
    'field_hlcs',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lifeHlcMeta = const VerificationMeta(
    'lifeHlc',
  );
  @override
  late final GeneratedColumn<String> lifeHlc = GeneratedColumn<String>(
    'life_hlc',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdHlcMeta = const VerificationMeta(
    'createdHlc',
  );
  @override
  late final GeneratedColumn<String> createdHlc = GeneratedColumn<String>(
    'created_hlc',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    docId,
    pageId,
    markType,
    bx0,
    by0,
    bx1,
    by1,
    fields,
    fieldHlcs,
    lifeHlc,
    deleted,
    createdHlc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'entities';
  @override
  VerificationContext validateIntegrity(
    Insertable<EntityRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('doc_id')) {
      context.handle(
        _docIdMeta,
        docId.isAcceptableOrUnknown(data['doc_id']!, _docIdMeta),
      );
    }
    if (data.containsKey('page_id')) {
      context.handle(
        _pageIdMeta,
        pageId.isAcceptableOrUnknown(data['page_id']!, _pageIdMeta),
      );
    }
    if (data.containsKey('mark_type')) {
      context.handle(
        _markTypeMeta,
        markType.isAcceptableOrUnknown(data['mark_type']!, _markTypeMeta),
      );
    }
    if (data.containsKey('bx0')) {
      context.handle(
        _bx0Meta,
        bx0.isAcceptableOrUnknown(data['bx0']!, _bx0Meta),
      );
    }
    if (data.containsKey('by0')) {
      context.handle(
        _by0Meta,
        by0.isAcceptableOrUnknown(data['by0']!, _by0Meta),
      );
    }
    if (data.containsKey('bx1')) {
      context.handle(
        _bx1Meta,
        bx1.isAcceptableOrUnknown(data['bx1']!, _bx1Meta),
      );
    }
    if (data.containsKey('by1')) {
      context.handle(
        _by1Meta,
        by1.isAcceptableOrUnknown(data['by1']!, _by1Meta),
      );
    }
    if (data.containsKey('fields')) {
      context.handle(
        _fieldsMeta,
        fields.isAcceptableOrUnknown(data['fields']!, _fieldsMeta),
      );
    } else if (isInserting) {
      context.missing(_fieldsMeta);
    }
    if (data.containsKey('field_hlcs')) {
      context.handle(
        _fieldHlcsMeta,
        fieldHlcs.isAcceptableOrUnknown(data['field_hlcs']!, _fieldHlcsMeta),
      );
    } else if (isInserting) {
      context.missing(_fieldHlcsMeta);
    }
    if (data.containsKey('life_hlc')) {
      context.handle(
        _lifeHlcMeta,
        lifeHlc.isAcceptableOrUnknown(data['life_hlc']!, _lifeHlcMeta),
      );
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('created_hlc')) {
      context.handle(
        _createdHlcMeta,
        createdHlc.isAcceptableOrUnknown(data['created_hlc']!, _createdHlcMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EntityRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EntityRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      docId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}doc_id'],
      ),
      pageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}page_id'],
      ),
      markType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mark_type'],
      ),
      bx0: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}bx0'],
      ),
      by0: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}by0'],
      ),
      bx1: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}bx1'],
      ),
      by1: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}by1'],
      ),
      fields: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fields'],
      )!,
      fieldHlcs: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}field_hlcs'],
      )!,
      lifeHlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}life_hlc'],
      ),
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      createdHlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_hlc'],
      ),
    );
  }

  @override
  $EntitiesTable createAlias(String alias) {
    return $EntitiesTable(attachedDatabase, alias);
  }
}

class EntityRow extends DataClass implements Insertable<EntityRow> {
  final String id;
  final String kind;
  final String? docId;
  final String? pageId;
  final String? markType;
  final double? bx0;
  final double? by0;
  final double? bx1;
  final double? by1;

  /// JSON map: field name to value.
  final String fields;

  /// JSON map: field name to encoded HLC.
  final String fieldHlcs;
  final String? lifeHlc;
  final bool deleted;
  final String? createdHlc;
  const EntityRow({
    required this.id,
    required this.kind,
    this.docId,
    this.pageId,
    this.markType,
    this.bx0,
    this.by0,
    this.bx1,
    this.by1,
    required this.fields,
    required this.fieldHlcs,
    this.lifeHlc,
    required this.deleted,
    this.createdHlc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || docId != null) {
      map['doc_id'] = Variable<String>(docId);
    }
    if (!nullToAbsent || pageId != null) {
      map['page_id'] = Variable<String>(pageId);
    }
    if (!nullToAbsent || markType != null) {
      map['mark_type'] = Variable<String>(markType);
    }
    if (!nullToAbsent || bx0 != null) {
      map['bx0'] = Variable<double>(bx0);
    }
    if (!nullToAbsent || by0 != null) {
      map['by0'] = Variable<double>(by0);
    }
    if (!nullToAbsent || bx1 != null) {
      map['bx1'] = Variable<double>(bx1);
    }
    if (!nullToAbsent || by1 != null) {
      map['by1'] = Variable<double>(by1);
    }
    map['fields'] = Variable<String>(fields);
    map['field_hlcs'] = Variable<String>(fieldHlcs);
    if (!nullToAbsent || lifeHlc != null) {
      map['life_hlc'] = Variable<String>(lifeHlc);
    }
    map['deleted'] = Variable<bool>(deleted);
    if (!nullToAbsent || createdHlc != null) {
      map['created_hlc'] = Variable<String>(createdHlc);
    }
    return map;
  }

  EntitiesCompanion toCompanion(bool nullToAbsent) {
    return EntitiesCompanion(
      id: Value(id),
      kind: Value(kind),
      docId: docId == null && nullToAbsent
          ? const Value.absent()
          : Value(docId),
      pageId: pageId == null && nullToAbsent
          ? const Value.absent()
          : Value(pageId),
      markType: markType == null && nullToAbsent
          ? const Value.absent()
          : Value(markType),
      bx0: bx0 == null && nullToAbsent ? const Value.absent() : Value(bx0),
      by0: by0 == null && nullToAbsent ? const Value.absent() : Value(by0),
      bx1: bx1 == null && nullToAbsent ? const Value.absent() : Value(bx1),
      by1: by1 == null && nullToAbsent ? const Value.absent() : Value(by1),
      fields: Value(fields),
      fieldHlcs: Value(fieldHlcs),
      lifeHlc: lifeHlc == null && nullToAbsent
          ? const Value.absent()
          : Value(lifeHlc),
      deleted: Value(deleted),
      createdHlc: createdHlc == null && nullToAbsent
          ? const Value.absent()
          : Value(createdHlc),
    );
  }

  factory EntityRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EntityRow(
      id: serializer.fromJson<String>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      docId: serializer.fromJson<String?>(json['docId']),
      pageId: serializer.fromJson<String?>(json['pageId']),
      markType: serializer.fromJson<String?>(json['markType']),
      bx0: serializer.fromJson<double?>(json['bx0']),
      by0: serializer.fromJson<double?>(json['by0']),
      bx1: serializer.fromJson<double?>(json['bx1']),
      by1: serializer.fromJson<double?>(json['by1']),
      fields: serializer.fromJson<String>(json['fields']),
      fieldHlcs: serializer.fromJson<String>(json['fieldHlcs']),
      lifeHlc: serializer.fromJson<String?>(json['lifeHlc']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      createdHlc: serializer.fromJson<String?>(json['createdHlc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'kind': serializer.toJson<String>(kind),
      'docId': serializer.toJson<String?>(docId),
      'pageId': serializer.toJson<String?>(pageId),
      'markType': serializer.toJson<String?>(markType),
      'bx0': serializer.toJson<double?>(bx0),
      'by0': serializer.toJson<double?>(by0),
      'bx1': serializer.toJson<double?>(bx1),
      'by1': serializer.toJson<double?>(by1),
      'fields': serializer.toJson<String>(fields),
      'fieldHlcs': serializer.toJson<String>(fieldHlcs),
      'lifeHlc': serializer.toJson<String?>(lifeHlc),
      'deleted': serializer.toJson<bool>(deleted),
      'createdHlc': serializer.toJson<String?>(createdHlc),
    };
  }

  EntityRow copyWith({
    String? id,
    String? kind,
    Value<String?> docId = const Value.absent(),
    Value<String?> pageId = const Value.absent(),
    Value<String?> markType = const Value.absent(),
    Value<double?> bx0 = const Value.absent(),
    Value<double?> by0 = const Value.absent(),
    Value<double?> bx1 = const Value.absent(),
    Value<double?> by1 = const Value.absent(),
    String? fields,
    String? fieldHlcs,
    Value<String?> lifeHlc = const Value.absent(),
    bool? deleted,
    Value<String?> createdHlc = const Value.absent(),
  }) => EntityRow(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    docId: docId.present ? docId.value : this.docId,
    pageId: pageId.present ? pageId.value : this.pageId,
    markType: markType.present ? markType.value : this.markType,
    bx0: bx0.present ? bx0.value : this.bx0,
    by0: by0.present ? by0.value : this.by0,
    bx1: bx1.present ? bx1.value : this.bx1,
    by1: by1.present ? by1.value : this.by1,
    fields: fields ?? this.fields,
    fieldHlcs: fieldHlcs ?? this.fieldHlcs,
    lifeHlc: lifeHlc.present ? lifeHlc.value : this.lifeHlc,
    deleted: deleted ?? this.deleted,
    createdHlc: createdHlc.present ? createdHlc.value : this.createdHlc,
  );
  EntityRow copyWithCompanion(EntitiesCompanion data) {
    return EntityRow(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      docId: data.docId.present ? data.docId.value : this.docId,
      pageId: data.pageId.present ? data.pageId.value : this.pageId,
      markType: data.markType.present ? data.markType.value : this.markType,
      bx0: data.bx0.present ? data.bx0.value : this.bx0,
      by0: data.by0.present ? data.by0.value : this.by0,
      bx1: data.bx1.present ? data.bx1.value : this.bx1,
      by1: data.by1.present ? data.by1.value : this.by1,
      fields: data.fields.present ? data.fields.value : this.fields,
      fieldHlcs: data.fieldHlcs.present ? data.fieldHlcs.value : this.fieldHlcs,
      lifeHlc: data.lifeHlc.present ? data.lifeHlc.value : this.lifeHlc,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      createdHlc: data.createdHlc.present
          ? data.createdHlc.value
          : this.createdHlc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EntityRow(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('docId: $docId, ')
          ..write('pageId: $pageId, ')
          ..write('markType: $markType, ')
          ..write('bx0: $bx0, ')
          ..write('by0: $by0, ')
          ..write('bx1: $bx1, ')
          ..write('by1: $by1, ')
          ..write('fields: $fields, ')
          ..write('fieldHlcs: $fieldHlcs, ')
          ..write('lifeHlc: $lifeHlc, ')
          ..write('deleted: $deleted, ')
          ..write('createdHlc: $createdHlc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    docId,
    pageId,
    markType,
    bx0,
    by0,
    bx1,
    by1,
    fields,
    fieldHlcs,
    lifeHlc,
    deleted,
    createdHlc,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EntityRow &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.docId == this.docId &&
          other.pageId == this.pageId &&
          other.markType == this.markType &&
          other.bx0 == this.bx0 &&
          other.by0 == this.by0 &&
          other.bx1 == this.bx1 &&
          other.by1 == this.by1 &&
          other.fields == this.fields &&
          other.fieldHlcs == this.fieldHlcs &&
          other.lifeHlc == this.lifeHlc &&
          other.deleted == this.deleted &&
          other.createdHlc == this.createdHlc);
}

class EntitiesCompanion extends UpdateCompanion<EntityRow> {
  final Value<String> id;
  final Value<String> kind;
  final Value<String?> docId;
  final Value<String?> pageId;
  final Value<String?> markType;
  final Value<double?> bx0;
  final Value<double?> by0;
  final Value<double?> bx1;
  final Value<double?> by1;
  final Value<String> fields;
  final Value<String> fieldHlcs;
  final Value<String?> lifeHlc;
  final Value<bool> deleted;
  final Value<String?> createdHlc;
  final Value<int> rowid;
  const EntitiesCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.docId = const Value.absent(),
    this.pageId = const Value.absent(),
    this.markType = const Value.absent(),
    this.bx0 = const Value.absent(),
    this.by0 = const Value.absent(),
    this.bx1 = const Value.absent(),
    this.by1 = const Value.absent(),
    this.fields = const Value.absent(),
    this.fieldHlcs = const Value.absent(),
    this.lifeHlc = const Value.absent(),
    this.deleted = const Value.absent(),
    this.createdHlc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EntitiesCompanion.insert({
    required String id,
    required String kind,
    this.docId = const Value.absent(),
    this.pageId = const Value.absent(),
    this.markType = const Value.absent(),
    this.bx0 = const Value.absent(),
    this.by0 = const Value.absent(),
    this.bx1 = const Value.absent(),
    this.by1 = const Value.absent(),
    required String fields,
    required String fieldHlcs,
    this.lifeHlc = const Value.absent(),
    this.deleted = const Value.absent(),
    this.createdHlc = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       kind = Value(kind),
       fields = Value(fields),
       fieldHlcs = Value(fieldHlcs);
  static Insertable<EntityRow> custom({
    Expression<String>? id,
    Expression<String>? kind,
    Expression<String>? docId,
    Expression<String>? pageId,
    Expression<String>? markType,
    Expression<double>? bx0,
    Expression<double>? by0,
    Expression<double>? bx1,
    Expression<double>? by1,
    Expression<String>? fields,
    Expression<String>? fieldHlcs,
    Expression<String>? lifeHlc,
    Expression<bool>? deleted,
    Expression<String>? createdHlc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (docId != null) 'doc_id': docId,
      if (pageId != null) 'page_id': pageId,
      if (markType != null) 'mark_type': markType,
      if (bx0 != null) 'bx0': bx0,
      if (by0 != null) 'by0': by0,
      if (bx1 != null) 'bx1': bx1,
      if (by1 != null) 'by1': by1,
      if (fields != null) 'fields': fields,
      if (fieldHlcs != null) 'field_hlcs': fieldHlcs,
      if (lifeHlc != null) 'life_hlc': lifeHlc,
      if (deleted != null) 'deleted': deleted,
      if (createdHlc != null) 'created_hlc': createdHlc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EntitiesCompanion copyWith({
    Value<String>? id,
    Value<String>? kind,
    Value<String?>? docId,
    Value<String?>? pageId,
    Value<String?>? markType,
    Value<double?>? bx0,
    Value<double?>? by0,
    Value<double?>? bx1,
    Value<double?>? by1,
    Value<String>? fields,
    Value<String>? fieldHlcs,
    Value<String?>? lifeHlc,
    Value<bool>? deleted,
    Value<String?>? createdHlc,
    Value<int>? rowid,
  }) {
    return EntitiesCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      docId: docId ?? this.docId,
      pageId: pageId ?? this.pageId,
      markType: markType ?? this.markType,
      bx0: bx0 ?? this.bx0,
      by0: by0 ?? this.by0,
      bx1: bx1 ?? this.bx1,
      by1: by1 ?? this.by1,
      fields: fields ?? this.fields,
      fieldHlcs: fieldHlcs ?? this.fieldHlcs,
      lifeHlc: lifeHlc ?? this.lifeHlc,
      deleted: deleted ?? this.deleted,
      createdHlc: createdHlc ?? this.createdHlc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (docId.present) {
      map['doc_id'] = Variable<String>(docId.value);
    }
    if (pageId.present) {
      map['page_id'] = Variable<String>(pageId.value);
    }
    if (markType.present) {
      map['mark_type'] = Variable<String>(markType.value);
    }
    if (bx0.present) {
      map['bx0'] = Variable<double>(bx0.value);
    }
    if (by0.present) {
      map['by0'] = Variable<double>(by0.value);
    }
    if (bx1.present) {
      map['bx1'] = Variable<double>(bx1.value);
    }
    if (by1.present) {
      map['by1'] = Variable<double>(by1.value);
    }
    if (fields.present) {
      map['fields'] = Variable<String>(fields.value);
    }
    if (fieldHlcs.present) {
      map['field_hlcs'] = Variable<String>(fieldHlcs.value);
    }
    if (lifeHlc.present) {
      map['life_hlc'] = Variable<String>(lifeHlc.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (createdHlc.present) {
      map['created_hlc'] = Variable<String>(createdHlc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EntitiesCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('docId: $docId, ')
          ..write('pageId: $pageId, ')
          ..write('markType: $markType, ')
          ..write('bx0: $bx0, ')
          ..write('by0: $by0, ')
          ..write('bx1: $bx1, ')
          ..write('by1: $by1, ')
          ..write('fields: $fields, ')
          ..write('fieldHlcs: $fieldHlcs, ')
          ..write('lifeHlc: $lifeHlc, ')
          ..write('deleted: $deleted, ')
          ..write('createdHlc: $createdHlc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PdfFilesTable extends PdfFiles
    with TableInfo<$PdfFilesTable, PdfFileRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PdfFilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sourceHashMeta = const VerificationMeta(
    'sourceHash',
  );
  @override
  late final GeneratedColumn<String> sourceHash = GeneratedColumn<String>(
    'source_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _byteLengthMeta = const VerificationMeta(
    'byteLength',
  );
  @override
  late final GeneratedColumn<int> byteLength = GeneratedColumn<int>(
    'byte_length',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _importedAtMeta = const VerificationMeta(
    'importedAt',
  );
  @override
  late final GeneratedColumn<int> importedAt = GeneratedColumn<int>(
    'imported_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sourceHash,
    path,
    byteLength,
    importedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pdf_files';
  @override
  VerificationContext validateIntegrity(
    Insertable<PdfFileRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('source_hash')) {
      context.handle(
        _sourceHashMeta,
        sourceHash.isAcceptableOrUnknown(data['source_hash']!, _sourceHashMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceHashMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('byte_length')) {
      context.handle(
        _byteLengthMeta,
        byteLength.isAcceptableOrUnknown(data['byte_length']!, _byteLengthMeta),
      );
    } else if (isInserting) {
      context.missing(_byteLengthMeta);
    }
    if (data.containsKey('imported_at')) {
      context.handle(
        _importedAtMeta,
        importedAt.isAcceptableOrUnknown(data['imported_at']!, _importedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_importedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sourceHash};
  @override
  PdfFileRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PdfFileRow(
      sourceHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_hash'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      byteLength: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}byte_length'],
      )!,
      importedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}imported_at'],
      )!,
    );
  }

  @override
  $PdfFilesTable createAlias(String alias) {
    return $PdfFilesTable(attachedDatabase, alias);
  }
}

class PdfFileRow extends DataClass implements Insertable<PdfFileRow> {
  final String sourceHash;
  final String path;
  final int byteLength;
  final int importedAt;
  const PdfFileRow({
    required this.sourceHash,
    required this.path,
    required this.byteLength,
    required this.importedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_hash'] = Variable<String>(sourceHash);
    map['path'] = Variable<String>(path);
    map['byte_length'] = Variable<int>(byteLength);
    map['imported_at'] = Variable<int>(importedAt);
    return map;
  }

  PdfFilesCompanion toCompanion(bool nullToAbsent) {
    return PdfFilesCompanion(
      sourceHash: Value(sourceHash),
      path: Value(path),
      byteLength: Value(byteLength),
      importedAt: Value(importedAt),
    );
  }

  factory PdfFileRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PdfFileRow(
      sourceHash: serializer.fromJson<String>(json['sourceHash']),
      path: serializer.fromJson<String>(json['path']),
      byteLength: serializer.fromJson<int>(json['byteLength']),
      importedAt: serializer.fromJson<int>(json['importedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sourceHash': serializer.toJson<String>(sourceHash),
      'path': serializer.toJson<String>(path),
      'byteLength': serializer.toJson<int>(byteLength),
      'importedAt': serializer.toJson<int>(importedAt),
    };
  }

  PdfFileRow copyWith({
    String? sourceHash,
    String? path,
    int? byteLength,
    int? importedAt,
  }) => PdfFileRow(
    sourceHash: sourceHash ?? this.sourceHash,
    path: path ?? this.path,
    byteLength: byteLength ?? this.byteLength,
    importedAt: importedAt ?? this.importedAt,
  );
  PdfFileRow copyWithCompanion(PdfFilesCompanion data) {
    return PdfFileRow(
      sourceHash: data.sourceHash.present
          ? data.sourceHash.value
          : this.sourceHash,
      path: data.path.present ? data.path.value : this.path,
      byteLength: data.byteLength.present
          ? data.byteLength.value
          : this.byteLength,
      importedAt: data.importedAt.present
          ? data.importedAt.value
          : this.importedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PdfFileRow(')
          ..write('sourceHash: $sourceHash, ')
          ..write('path: $path, ')
          ..write('byteLength: $byteLength, ')
          ..write('importedAt: $importedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(sourceHash, path, byteLength, importedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PdfFileRow &&
          other.sourceHash == this.sourceHash &&
          other.path == this.path &&
          other.byteLength == this.byteLength &&
          other.importedAt == this.importedAt);
}

class PdfFilesCompanion extends UpdateCompanion<PdfFileRow> {
  final Value<String> sourceHash;
  final Value<String> path;
  final Value<int> byteLength;
  final Value<int> importedAt;
  final Value<int> rowid;
  const PdfFilesCompanion({
    this.sourceHash = const Value.absent(),
    this.path = const Value.absent(),
    this.byteLength = const Value.absent(),
    this.importedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PdfFilesCompanion.insert({
    required String sourceHash,
    required String path,
    required int byteLength,
    required int importedAt,
    this.rowid = const Value.absent(),
  }) : sourceHash = Value(sourceHash),
       path = Value(path),
       byteLength = Value(byteLength),
       importedAt = Value(importedAt);
  static Insertable<PdfFileRow> custom({
    Expression<String>? sourceHash,
    Expression<String>? path,
    Expression<int>? byteLength,
    Expression<int>? importedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sourceHash != null) 'source_hash': sourceHash,
      if (path != null) 'path': path,
      if (byteLength != null) 'byte_length': byteLength,
      if (importedAt != null) 'imported_at': importedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PdfFilesCompanion copyWith({
    Value<String>? sourceHash,
    Value<String>? path,
    Value<int>? byteLength,
    Value<int>? importedAt,
    Value<int>? rowid,
  }) {
    return PdfFilesCompanion(
      sourceHash: sourceHash ?? this.sourceHash,
      path: path ?? this.path,
      byteLength: byteLength ?? this.byteLength,
      importedAt: importedAt ?? this.importedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceHash.present) {
      map['source_hash'] = Variable<String>(sourceHash.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (byteLength.present) {
      map['byte_length'] = Variable<int>(byteLength.value);
    }
    if (importedAt.present) {
      map['imported_at'] = Variable<int>(importedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PdfFilesCompanion(')
          ..write('sourceHash: $sourceHash, ')
          ..write('path: $path, ')
          ..write('byteLength: $byteLength, ')
          ..write('importedAt: $importedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DeviceTable extends Device with TableInfo<$DeviceTable, DeviceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DeviceTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _slotMeta = const VerificationMeta('slot');
  @override
  late final GeneratedColumn<int> slot = GeneratedColumn<int>(
    'slot',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [slot, deviceId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'device';
  @override
  VerificationContext validateIntegrity(
    Insertable<DeviceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('slot')) {
      context.handle(
        _slotMeta,
        slot.isAcceptableOrUnknown(data['slot']!, _slotMeta),
      );
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {slot};
  @override
  DeviceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DeviceRow(
      slot: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}slot'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
    );
  }

  @override
  $DeviceTable createAlias(String alias) {
    return $DeviceTable(attachedDatabase, alias);
  }
}

class DeviceRow extends DataClass implements Insertable<DeviceRow> {
  final int slot;
  final String deviceId;
  const DeviceRow({required this.slot, required this.deviceId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['slot'] = Variable<int>(slot);
    map['device_id'] = Variable<String>(deviceId);
    return map;
  }

  DeviceCompanion toCompanion(bool nullToAbsent) {
    return DeviceCompanion(slot: Value(slot), deviceId: Value(deviceId));
  }

  factory DeviceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DeviceRow(
      slot: serializer.fromJson<int>(json['slot']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'slot': serializer.toJson<int>(slot),
      'deviceId': serializer.toJson<String>(deviceId),
    };
  }

  DeviceRow copyWith({int? slot, String? deviceId}) =>
      DeviceRow(slot: slot ?? this.slot, deviceId: deviceId ?? this.deviceId);
  DeviceRow copyWithCompanion(DeviceCompanion data) {
    return DeviceRow(
      slot: data.slot.present ? data.slot.value : this.slot,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DeviceRow(')
          ..write('slot: $slot, ')
          ..write('deviceId: $deviceId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(slot, deviceId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeviceRow &&
          other.slot == this.slot &&
          other.deviceId == this.deviceId);
}

class DeviceCompanion extends UpdateCompanion<DeviceRow> {
  final Value<int> slot;
  final Value<String> deviceId;
  const DeviceCompanion({
    this.slot = const Value.absent(),
    this.deviceId = const Value.absent(),
  });
  DeviceCompanion.insert({
    this.slot = const Value.absent(),
    required String deviceId,
  }) : deviceId = Value(deviceId);
  static Insertable<DeviceRow> custom({
    Expression<int>? slot,
    Expression<String>? deviceId,
  }) {
    return RawValuesInsertable({
      if (slot != null) 'slot': slot,
      if (deviceId != null) 'device_id': deviceId,
    });
  }

  DeviceCompanion copyWith({Value<int>? slot, Value<String>? deviceId}) {
    return DeviceCompanion(
      slot: slot ?? this.slot,
      deviceId: deviceId ?? this.deviceId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (slot.present) {
      map['slot'] = Variable<int>(slot.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DeviceCompanion(')
          ..write('slot: $slot, ')
          ..write('deviceId: $deviceId')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings
    with TableInfo<$SettingsTable, SettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class SettingRow extends DataClass implements Insertable<SettingRow> {
  final String key;
  final String value;
  const SettingRow({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), value: Value(value));
  }

  factory SettingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SettingRow copyWith({String? key, String? value}) =>
      SettingRow(key: key ?? this.key, value: value ?? this.value);
  SettingRow copyWithCompanion(SettingsCompanion data) {
    return SettingRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingRow(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingRow &&
          other.key == this.key &&
          other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<SettingRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SettingRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ViewStatesTable extends ViewStates
    with TableInfo<$ViewStatesTable, ViewStateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ViewStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _docIdMeta = const VerificationMeta('docId');
  @override
  late final GeneratedColumn<String> docId = GeneratedColumn<String>(
    'doc_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _xMeta = const VerificationMeta('x');
  @override
  late final GeneratedColumn<double> x = GeneratedColumn<double>(
    'x',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _yMeta = const VerificationMeta('y');
  @override
  late final GeneratedColumn<double> y = GeneratedColumn<double>(
    'y',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _zoomMeta = const VerificationMeta('zoom');
  @override
  late final GeneratedColumn<double> zoom = GeneratedColumn<double>(
    'zoom',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [docId, x, y, zoom];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'view_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<ViewStateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('doc_id')) {
      context.handle(
        _docIdMeta,
        docId.isAcceptableOrUnknown(data['doc_id']!, _docIdMeta),
      );
    } else if (isInserting) {
      context.missing(_docIdMeta);
    }
    if (data.containsKey('x')) {
      context.handle(_xMeta, x.isAcceptableOrUnknown(data['x']!, _xMeta));
    } else if (isInserting) {
      context.missing(_xMeta);
    }
    if (data.containsKey('y')) {
      context.handle(_yMeta, y.isAcceptableOrUnknown(data['y']!, _yMeta));
    } else if (isInserting) {
      context.missing(_yMeta);
    }
    if (data.containsKey('zoom')) {
      context.handle(
        _zoomMeta,
        zoom.isAcceptableOrUnknown(data['zoom']!, _zoomMeta),
      );
    } else if (isInserting) {
      context.missing(_zoomMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {docId};
  @override
  ViewStateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ViewStateRow(
      docId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}doc_id'],
      )!,
      x: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}x'],
      )!,
      y: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}y'],
      )!,
      zoom: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}zoom'],
      )!,
    );
  }

  @override
  $ViewStatesTable createAlias(String alias) {
    return $ViewStatesTable(attachedDatabase, alias);
  }
}

class ViewStateRow extends DataClass implements Insertable<ViewStateRow> {
  final String docId;
  final double x;
  final double y;
  final double zoom;
  const ViewStateRow({
    required this.docId,
    required this.x,
    required this.y,
    required this.zoom,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['doc_id'] = Variable<String>(docId);
    map['x'] = Variable<double>(x);
    map['y'] = Variable<double>(y);
    map['zoom'] = Variable<double>(zoom);
    return map;
  }

  ViewStatesCompanion toCompanion(bool nullToAbsent) {
    return ViewStatesCompanion(
      docId: Value(docId),
      x: Value(x),
      y: Value(y),
      zoom: Value(zoom),
    );
  }

  factory ViewStateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ViewStateRow(
      docId: serializer.fromJson<String>(json['docId']),
      x: serializer.fromJson<double>(json['x']),
      y: serializer.fromJson<double>(json['y']),
      zoom: serializer.fromJson<double>(json['zoom']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'docId': serializer.toJson<String>(docId),
      'x': serializer.toJson<double>(x),
      'y': serializer.toJson<double>(y),
      'zoom': serializer.toJson<double>(zoom),
    };
  }

  ViewStateRow copyWith({String? docId, double? x, double? y, double? zoom}) =>
      ViewStateRow(
        docId: docId ?? this.docId,
        x: x ?? this.x,
        y: y ?? this.y,
        zoom: zoom ?? this.zoom,
      );
  ViewStateRow copyWithCompanion(ViewStatesCompanion data) {
    return ViewStateRow(
      docId: data.docId.present ? data.docId.value : this.docId,
      x: data.x.present ? data.x.value : this.x,
      y: data.y.present ? data.y.value : this.y,
      zoom: data.zoom.present ? data.zoom.value : this.zoom,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ViewStateRow(')
          ..write('docId: $docId, ')
          ..write('x: $x, ')
          ..write('y: $y, ')
          ..write('zoom: $zoom')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(docId, x, y, zoom);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ViewStateRow &&
          other.docId == this.docId &&
          other.x == this.x &&
          other.y == this.y &&
          other.zoom == this.zoom);
}

class ViewStatesCompanion extends UpdateCompanion<ViewStateRow> {
  final Value<String> docId;
  final Value<double> x;
  final Value<double> y;
  final Value<double> zoom;
  final Value<int> rowid;
  const ViewStatesCompanion({
    this.docId = const Value.absent(),
    this.x = const Value.absent(),
    this.y = const Value.absent(),
    this.zoom = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ViewStatesCompanion.insert({
    required String docId,
    required double x,
    required double y,
    required double zoom,
    this.rowid = const Value.absent(),
  }) : docId = Value(docId),
       x = Value(x),
       y = Value(y),
       zoom = Value(zoom);
  static Insertable<ViewStateRow> custom({
    Expression<String>? docId,
    Expression<double>? x,
    Expression<double>? y,
    Expression<double>? zoom,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (docId != null) 'doc_id': docId,
      if (x != null) 'x': x,
      if (y != null) 'y': y,
      if (zoom != null) 'zoom': zoom,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ViewStatesCompanion copyWith({
    Value<String>? docId,
    Value<double>? x,
    Value<double>? y,
    Value<double>? zoom,
    Value<int>? rowid,
  }) {
    return ViewStatesCompanion(
      docId: docId ?? this.docId,
      x: x ?? this.x,
      y: y ?? this.y,
      zoom: zoom ?? this.zoom,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (docId.present) {
      map['doc_id'] = Variable<String>(docId.value);
    }
    if (x.present) {
      map['x'] = Variable<double>(x.value);
    }
    if (y.present) {
      map['y'] = Variable<double>(y.value);
    }
    if (zoom.present) {
      map['zoom'] = Variable<double>(zoom.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ViewStatesCompanion(')
          ..write('docId: $docId, ')
          ..write('x: $x, ')
          ..write('y: $y, ')
          ..write('zoom: $zoom, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AetherDatabase extends GeneratedDatabase {
  _$AetherDatabase(QueryExecutor e) : super(e);
  $AetherDatabaseManager get managers => $AetherDatabaseManager(this);
  late final $OpsTable ops = $OpsTable(this);
  late final $EntitiesTable entities = $EntitiesTable(this);
  late final $PdfFilesTable pdfFiles = $PdfFilesTable(this);
  late final $DeviceTable device = $DeviceTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final $ViewStatesTable viewStates = $ViewStatesTable(this);
  late final Index opsHlc = Index(
    'ops_hlc',
    'CREATE INDEX ops_hlc ON ops (hlc)',
  );
  late final Index opsEntity = Index(
    'ops_entity',
    'CREATE INDEX ops_entity ON ops (entity_id)',
  );
  late final Index entitiesDocKind = Index(
    'entities_doc_kind',
    'CREATE INDEX entities_doc_kind ON entities (doc_id, kind)',
  );
  late final Index entitiesPage = Index(
    'entities_page',
    'CREATE INDEX entities_page ON entities (page_id)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    ops,
    entities,
    pdfFiles,
    device,
    settings,
    viewStates,
    opsHlc,
    opsEntity,
    entitiesDocKind,
    entitiesPage,
  ];
}

typedef $$OpsTableCreateCompanionBuilder = OpsCompanion Function({
  required String opId,
  required String hlc,
  required String deviceId,
  required String entityKind,
  required String entityId,
  required String opKind,
  Value<String?> field,
  Value<String?> value,
  required String txGroupId,
  Value<String?> undoOf,
  Value<int> rowid,
});
typedef $$OpsTableUpdateCompanionBuilder = OpsCompanion Function({
  Value<String> opId,
  Value<String> hlc,
  Value<String> deviceId,
  Value<String> entityKind,
  Value<String> entityId,
  Value<String> opKind,
  Value<String?> field,
  Value<String?> value,
  Value<String> txGroupId,
  Value<String?> undoOf,
  Value<int> rowid,
});

class $$OpsTableFilterComposer extends Composer<_$AetherDatabase, $OpsTable> {
  $$OpsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get opId => $composableBuilder(
    column: $table.opId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityKind => $composableBuilder(
    column: $table.entityKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get opKind => $composableBuilder(
    column: $table.opKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get field => $composableBuilder(
    column: $table.field,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get txGroupId => $composableBuilder(
    column: $table.txGroupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get undoOf => $composableBuilder(
    column: $table.undoOf,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OpsTableOrderingComposer extends Composer<_$AetherDatabase, $OpsTable> {
  $$OpsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get opId => $composableBuilder(
    column: $table.opId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityKind => $composableBuilder(
    column: $table.entityKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get opKind => $composableBuilder(
    column: $table.opKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get field => $composableBuilder(
    column: $table.field,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get txGroupId => $composableBuilder(
    column: $table.txGroupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get undoOf => $composableBuilder(
    column: $table.undoOf,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OpsTableAnnotationComposer
    extends Composer<_$AetherDatabase, $OpsTable> {
  $$OpsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get opId =>
      $composableBuilder(column: $table.opId, builder: (column) => column);

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get entityKind => $composableBuilder(
    column: $table.entityKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get opKind =>
      $composableBuilder(column: $table.opKind, builder: (column) => column);

  GeneratedColumn<String> get field =>
      $composableBuilder(column: $table.field, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<String> get txGroupId =>
      $composableBuilder(column: $table.txGroupId, builder: (column) => column);

  GeneratedColumn<String> get undoOf =>
      $composableBuilder(column: $table.undoOf, builder: (column) => column);
}

class $$OpsTableTableManager
    extends
        RootTableManager<
          _$AetherDatabase,
          $OpsTable,
          OpRow,
          $$OpsTableFilterComposer,
          $$OpsTableOrderingComposer,
          $$OpsTableAnnotationComposer,
          $$OpsTableCreateCompanionBuilder,
          $$OpsTableUpdateCompanionBuilder,
          (OpRow, BaseReferences<_$AetherDatabase, $OpsTable, OpRow>),
          OpRow,
          PrefetchHooks Function()
        > {
  $$OpsTableTableManager(_$AetherDatabase db, $OpsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OpsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OpsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OpsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> opId = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> entityKind = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> opKind = const Value.absent(),
                Value<String?> field = const Value.absent(),
                Value<String?> value = const Value.absent(),
                Value<String> txGroupId = const Value.absent(),
                Value<String?> undoOf = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OpsCompanion(
                opId: opId,
                hlc: hlc,
                deviceId: deviceId,
                entityKind: entityKind,
                entityId: entityId,
                opKind: opKind,
                field: field,
                value: value,
                txGroupId: txGroupId,
                undoOf: undoOf,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String opId,
                required String hlc,
                required String deviceId,
                required String entityKind,
                required String entityId,
                required String opKind,
                Value<String?> field = const Value.absent(),
                Value<String?> value = const Value.absent(),
                required String txGroupId,
                Value<String?> undoOf = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OpsCompanion.insert(
                opId: opId,
                hlc: hlc,
                deviceId: deviceId,
                entityKind: entityKind,
                entityId: entityId,
                opKind: opKind,
                field: field,
                value: value,
                txGroupId: txGroupId,
                undoOf: undoOf,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OpsTable, OpRow>(table),
                  BaseReferences<_$AetherDatabase, $OpsTable, OpRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OpsTableProcessedTableManager =
    ProcessedTableManager<
      _$AetherDatabase,
      $OpsTable,
      OpRow,
      $$OpsTableFilterComposer,
      $$OpsTableOrderingComposer,
      $$OpsTableAnnotationComposer,
      $$OpsTableCreateCompanionBuilder,
      $$OpsTableUpdateCompanionBuilder,
      (OpRow, BaseReferences<_$AetherDatabase, $OpsTable, OpRow>),
      OpRow,
      PrefetchHooks Function()
    >;
typedef $$EntitiesTableCreateCompanionBuilder = EntitiesCompanion Function({
  required String id,
  required String kind,
  Value<String?> docId,
  Value<String?> pageId,
  Value<String?> markType,
  Value<double?> bx0,
  Value<double?> by0,
  Value<double?> bx1,
  Value<double?> by1,
  required String fields,
  required String fieldHlcs,
  Value<String?> lifeHlc,
  Value<bool> deleted,
  Value<String?> createdHlc,
  Value<int> rowid,
});
typedef $$EntitiesTableUpdateCompanionBuilder = EntitiesCompanion Function({
  Value<String> id,
  Value<String> kind,
  Value<String?> docId,
  Value<String?> pageId,
  Value<String?> markType,
  Value<double?> bx0,
  Value<double?> by0,
  Value<double?> bx1,
  Value<double?> by1,
  Value<String> fields,
  Value<String> fieldHlcs,
  Value<String?> lifeHlc,
  Value<bool> deleted,
  Value<String?> createdHlc,
  Value<int> rowid,
});

class $$EntitiesTableFilterComposer
    extends Composer<_$AetherDatabase, $EntitiesTable> {
  $$EntitiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get docId => $composableBuilder(
    column: $table.docId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pageId => $composableBuilder(
    column: $table.pageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get markType => $composableBuilder(
    column: $table.markType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bx0 => $composableBuilder(
    column: $table.bx0,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get by0 => $composableBuilder(
    column: $table.by0,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bx1 => $composableBuilder(
    column: $table.bx1,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get by1 => $composableBuilder(
    column: $table.by1,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fields => $composableBuilder(
    column: $table.fields,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fieldHlcs => $composableBuilder(
    column: $table.fieldHlcs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lifeHlc => $composableBuilder(
    column: $table.lifeHlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdHlc => $composableBuilder(
    column: $table.createdHlc,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EntitiesTableOrderingComposer
    extends Composer<_$AetherDatabase, $EntitiesTable> {
  $$EntitiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get docId => $composableBuilder(
    column: $table.docId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pageId => $composableBuilder(
    column: $table.pageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get markType => $composableBuilder(
    column: $table.markType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bx0 => $composableBuilder(
    column: $table.bx0,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get by0 => $composableBuilder(
    column: $table.by0,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bx1 => $composableBuilder(
    column: $table.bx1,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get by1 => $composableBuilder(
    column: $table.by1,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fields => $composableBuilder(
    column: $table.fields,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fieldHlcs => $composableBuilder(
    column: $table.fieldHlcs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lifeHlc => $composableBuilder(
    column: $table.lifeHlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdHlc => $composableBuilder(
    column: $table.createdHlc,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EntitiesTableAnnotationComposer
    extends Composer<_$AetherDatabase, $EntitiesTable> {
  $$EntitiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get docId =>
      $composableBuilder(column: $table.docId, builder: (column) => column);

  GeneratedColumn<String> get pageId =>
      $composableBuilder(column: $table.pageId, builder: (column) => column);

  GeneratedColumn<String> get markType =>
      $composableBuilder(column: $table.markType, builder: (column) => column);

  GeneratedColumn<double> get bx0 =>
      $composableBuilder(column: $table.bx0, builder: (column) => column);

  GeneratedColumn<double> get by0 =>
      $composableBuilder(column: $table.by0, builder: (column) => column);

  GeneratedColumn<double> get bx1 =>
      $composableBuilder(column: $table.bx1, builder: (column) => column);

  GeneratedColumn<double> get by1 =>
      $composableBuilder(column: $table.by1, builder: (column) => column);

  GeneratedColumn<String> get fields =>
      $composableBuilder(column: $table.fields, builder: (column) => column);

  GeneratedColumn<String> get fieldHlcs =>
      $composableBuilder(column: $table.fieldHlcs, builder: (column) => column);

  GeneratedColumn<String> get lifeHlc =>
      $composableBuilder(column: $table.lifeHlc, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<String> get createdHlc => $composableBuilder(
    column: $table.createdHlc,
    builder: (column) => column,
  );
}

class $$EntitiesTableTableManager
    extends
        RootTableManager<
          _$AetherDatabase,
          $EntitiesTable,
          EntityRow,
          $$EntitiesTableFilterComposer,
          $$EntitiesTableOrderingComposer,
          $$EntitiesTableAnnotationComposer,
          $$EntitiesTableCreateCompanionBuilder,
          $$EntitiesTableUpdateCompanionBuilder,
          (
            EntityRow,
            BaseReferences<_$AetherDatabase, $EntitiesTable, EntityRow>,
          ),
          EntityRow,
          PrefetchHooks Function()
        > {
  $$EntitiesTableTableManager(_$AetherDatabase db, $EntitiesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EntitiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EntitiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EntitiesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String?> docId = const Value.absent(),
                Value<String?> pageId = const Value.absent(),
                Value<String?> markType = const Value.absent(),
                Value<double?> bx0 = const Value.absent(),
                Value<double?> by0 = const Value.absent(),
                Value<double?> bx1 = const Value.absent(),
                Value<double?> by1 = const Value.absent(),
                Value<String> fields = const Value.absent(),
                Value<String> fieldHlcs = const Value.absent(),
                Value<String?> lifeHlc = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<String?> createdHlc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EntitiesCompanion(
                id: id,
                kind: kind,
                docId: docId,
                pageId: pageId,
                markType: markType,
                bx0: bx0,
                by0: by0,
                bx1: bx1,
                by1: by1,
                fields: fields,
                fieldHlcs: fieldHlcs,
                lifeHlc: lifeHlc,
                deleted: deleted,
                createdHlc: createdHlc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String kind,
                Value<String?> docId = const Value.absent(),
                Value<String?> pageId = const Value.absent(),
                Value<String?> markType = const Value.absent(),
                Value<double?> bx0 = const Value.absent(),
                Value<double?> by0 = const Value.absent(),
                Value<double?> bx1 = const Value.absent(),
                Value<double?> by1 = const Value.absent(),
                required String fields,
                required String fieldHlcs,
                Value<String?> lifeHlc = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<String?> createdHlc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EntitiesCompanion.insert(
                id: id,
                kind: kind,
                docId: docId,
                pageId: pageId,
                markType: markType,
                bx0: bx0,
                by0: by0,
                bx1: bx1,
                by1: by1,
                fields: fields,
                fieldHlcs: fieldHlcs,
                lifeHlc: lifeHlc,
                deleted: deleted,
                createdHlc: createdHlc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$EntitiesTable, EntityRow>(table),
                  BaseReferences<_$AetherDatabase, $EntitiesTable, EntityRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EntitiesTableProcessedTableManager =
    ProcessedTableManager<
      _$AetherDatabase,
      $EntitiesTable,
      EntityRow,
      $$EntitiesTableFilterComposer,
      $$EntitiesTableOrderingComposer,
      $$EntitiesTableAnnotationComposer,
      $$EntitiesTableCreateCompanionBuilder,
      $$EntitiesTableUpdateCompanionBuilder,
      (EntityRow, BaseReferences<_$AetherDatabase, $EntitiesTable, EntityRow>),
      EntityRow,
      PrefetchHooks Function()
    >;
typedef $$PdfFilesTableCreateCompanionBuilder = PdfFilesCompanion Function({
  required String sourceHash,
  required String path,
  required int byteLength,
  required int importedAt,
  Value<int> rowid,
});
typedef $$PdfFilesTableUpdateCompanionBuilder = PdfFilesCompanion Function({
  Value<String> sourceHash,
  Value<String> path,
  Value<int> byteLength,
  Value<int> importedAt,
  Value<int> rowid,
});

class $$PdfFilesTableFilterComposer
    extends Composer<_$AetherDatabase, $PdfFilesTable> {
  $$PdfFilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sourceHash => $composableBuilder(
    column: $table.sourceHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get byteLength => $composableBuilder(
    column: $table.byteLength,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PdfFilesTableOrderingComposer
    extends Composer<_$AetherDatabase, $PdfFilesTable> {
  $$PdfFilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sourceHash => $composableBuilder(
    column: $table.sourceHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get byteLength => $composableBuilder(
    column: $table.byteLength,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PdfFilesTableAnnotationComposer
    extends Composer<_$AetherDatabase, $PdfFilesTable> {
  $$PdfFilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sourceHash => $composableBuilder(
    column: $table.sourceHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<int> get byteLength => $composableBuilder(
    column: $table.byteLength,
    builder: (column) => column,
  );

  GeneratedColumn<int> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => column,
  );
}

class $$PdfFilesTableTableManager
    extends
        RootTableManager<
          _$AetherDatabase,
          $PdfFilesTable,
          PdfFileRow,
          $$PdfFilesTableFilterComposer,
          $$PdfFilesTableOrderingComposer,
          $$PdfFilesTableAnnotationComposer,
          $$PdfFilesTableCreateCompanionBuilder,
          $$PdfFilesTableUpdateCompanionBuilder,
          (
            PdfFileRow,
            BaseReferences<_$AetherDatabase, $PdfFilesTable, PdfFileRow>,
          ),
          PdfFileRow,
          PrefetchHooks Function()
        > {
  $$PdfFilesTableTableManager(_$AetherDatabase db, $PdfFilesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PdfFilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PdfFilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PdfFilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sourceHash = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<int> byteLength = const Value.absent(),
                Value<int> importedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PdfFilesCompanion(
                sourceHash: sourceHash,
                path: path,
                byteLength: byteLength,
                importedAt: importedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sourceHash,
                required String path,
                required int byteLength,
                required int importedAt,
                Value<int> rowid = const Value.absent(),
              }) => PdfFilesCompanion.insert(
                sourceHash: sourceHash,
                path: path,
                byteLength: byteLength,
                importedAt: importedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PdfFilesTable, PdfFileRow>(table),
                  BaseReferences<_$AetherDatabase, $PdfFilesTable, PdfFileRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PdfFilesTableProcessedTableManager =
    ProcessedTableManager<
      _$AetherDatabase,
      $PdfFilesTable,
      PdfFileRow,
      $$PdfFilesTableFilterComposer,
      $$PdfFilesTableOrderingComposer,
      $$PdfFilesTableAnnotationComposer,
      $$PdfFilesTableCreateCompanionBuilder,
      $$PdfFilesTableUpdateCompanionBuilder,
      (
        PdfFileRow,
        BaseReferences<_$AetherDatabase, $PdfFilesTable, PdfFileRow>,
      ),
      PdfFileRow,
      PrefetchHooks Function()
    >;
typedef $$DeviceTableCreateCompanionBuilder = DeviceCompanion Function({
  Value<int> slot,
  required String deviceId,
});
typedef $$DeviceTableUpdateCompanionBuilder = DeviceCompanion Function({
  Value<int> slot,
  Value<String> deviceId,
});

class $$DeviceTableFilterComposer
    extends Composer<_$AetherDatabase, $DeviceTable> {
  $$DeviceTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get slot => $composableBuilder(
    column: $table.slot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DeviceTableOrderingComposer
    extends Composer<_$AetherDatabase, $DeviceTable> {
  $$DeviceTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get slot => $composableBuilder(
    column: $table.slot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DeviceTableAnnotationComposer
    extends Composer<_$AetherDatabase, $DeviceTable> {
  $$DeviceTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get slot =>
      $composableBuilder(column: $table.slot, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);
}

class $$DeviceTableTableManager
    extends
        RootTableManager<
          _$AetherDatabase,
          $DeviceTable,
          DeviceRow,
          $$DeviceTableFilterComposer,
          $$DeviceTableOrderingComposer,
          $$DeviceTableAnnotationComposer,
          $$DeviceTableCreateCompanionBuilder,
          $$DeviceTableUpdateCompanionBuilder,
          (
            DeviceRow,
            BaseReferences<_$AetherDatabase, $DeviceTable, DeviceRow>,
          ),
          DeviceRow,
          PrefetchHooks Function()
        > {
  $$DeviceTableTableManager(_$AetherDatabase db, $DeviceTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DeviceTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DeviceTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DeviceTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> slot = const Value.absent(),
            Value<String> deviceId = const Value.absent(),
          }) => DeviceCompanion(slot: slot, deviceId: deviceId),
          createCompanionCallback: ({
            Value<int> slot = const Value.absent(),
            required String deviceId,
          }) => DeviceCompanion.insert(slot: slot, deviceId: deviceId),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DeviceTable, DeviceRow>(table),
                  BaseReferences<_$AetherDatabase, $DeviceTable, DeviceRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DeviceTableProcessedTableManager =
    ProcessedTableManager<
      _$AetherDatabase,
      $DeviceTable,
      DeviceRow,
      $$DeviceTableFilterComposer,
      $$DeviceTableOrderingComposer,
      $$DeviceTableAnnotationComposer,
      $$DeviceTableCreateCompanionBuilder,
      $$DeviceTableUpdateCompanionBuilder,
      (DeviceRow, BaseReferences<_$AetherDatabase, $DeviceTable, DeviceRow>),
      DeviceRow,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableCreateCompanionBuilder = SettingsCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$SettingsTableUpdateCompanionBuilder = SettingsCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$SettingsTableFilterComposer
    extends Composer<_$AetherDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$AetherDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$AetherDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$AetherDatabase,
          $SettingsTable,
          SettingRow,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (
            SettingRow,
            BaseReferences<_$AetherDatabase, $SettingsTable, SettingRow>,
          ),
          SettingRow,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$AetherDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => SettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) => SettingsCompanion.insert(key: key, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SettingsTable, SettingRow>(table),
                  BaseReferences<_$AetherDatabase, $SettingsTable, SettingRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AetherDatabase,
      $SettingsTable,
      SettingRow,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (
        SettingRow,
        BaseReferences<_$AetherDatabase, $SettingsTable, SettingRow>,
      ),
      SettingRow,
      PrefetchHooks Function()
    >;
typedef $$ViewStatesTableCreateCompanionBuilder = ViewStatesCompanion Function({
  required String docId,
  required double x,
  required double y,
  required double zoom,
  Value<int> rowid,
});
typedef $$ViewStatesTableUpdateCompanionBuilder = ViewStatesCompanion Function({
  Value<String> docId,
  Value<double> x,
  Value<double> y,
  Value<double> zoom,
  Value<int> rowid,
});

class $$ViewStatesTableFilterComposer
    extends Composer<_$AetherDatabase, $ViewStatesTable> {
  $$ViewStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get docId => $composableBuilder(
    column: $table.docId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get x => $composableBuilder(
    column: $table.x,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get y => $composableBuilder(
    column: $table.y,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get zoom => $composableBuilder(
    column: $table.zoom,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ViewStatesTableOrderingComposer
    extends Composer<_$AetherDatabase, $ViewStatesTable> {
  $$ViewStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get docId => $composableBuilder(
    column: $table.docId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get x => $composableBuilder(
    column: $table.x,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get y => $composableBuilder(
    column: $table.y,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get zoom => $composableBuilder(
    column: $table.zoom,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ViewStatesTableAnnotationComposer
    extends Composer<_$AetherDatabase, $ViewStatesTable> {
  $$ViewStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get docId =>
      $composableBuilder(column: $table.docId, builder: (column) => column);

  GeneratedColumn<double> get x =>
      $composableBuilder(column: $table.x, builder: (column) => column);

  GeneratedColumn<double> get y =>
      $composableBuilder(column: $table.y, builder: (column) => column);

  GeneratedColumn<double> get zoom =>
      $composableBuilder(column: $table.zoom, builder: (column) => column);
}

class $$ViewStatesTableTableManager
    extends
        RootTableManager<
          _$AetherDatabase,
          $ViewStatesTable,
          ViewStateRow,
          $$ViewStatesTableFilterComposer,
          $$ViewStatesTableOrderingComposer,
          $$ViewStatesTableAnnotationComposer,
          $$ViewStatesTableCreateCompanionBuilder,
          $$ViewStatesTableUpdateCompanionBuilder,
          (
            ViewStateRow,
            BaseReferences<_$AetherDatabase, $ViewStatesTable, ViewStateRow>,
          ),
          ViewStateRow,
          PrefetchHooks Function()
        > {
  $$ViewStatesTableTableManager(_$AetherDatabase db, $ViewStatesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ViewStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ViewStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ViewStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> docId = const Value.absent(),
                Value<double> x = const Value.absent(),
                Value<double> y = const Value.absent(),
                Value<double> zoom = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ViewStatesCompanion(
                docId: docId,
                x: x,
                y: y,
                zoom: zoom,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String docId,
                required double x,
                required double y,
                required double zoom,
                Value<int> rowid = const Value.absent(),
              }) => ViewStatesCompanion.insert(
                docId: docId,
                x: x,
                y: y,
                zoom: zoom,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ViewStatesTable, ViewStateRow>(table),
                  BaseReferences<
                    _$AetherDatabase,
                    $ViewStatesTable,
                    ViewStateRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ViewStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AetherDatabase,
      $ViewStatesTable,
      ViewStateRow,
      $$ViewStatesTableFilterComposer,
      $$ViewStatesTableOrderingComposer,
      $$ViewStatesTableAnnotationComposer,
      $$ViewStatesTableCreateCompanionBuilder,
      $$ViewStatesTableUpdateCompanionBuilder,
      (
        ViewStateRow,
        BaseReferences<_$AetherDatabase, $ViewStatesTable, ViewStateRow>,
      ),
      ViewStateRow,
      PrefetchHooks Function()
    >;

class $AetherDatabaseManager {
  final _$AetherDatabase _db;
  $AetherDatabaseManager(this._db);
  $$OpsTableTableManager get ops => $$OpsTableTableManager(_db, _db.ops);
  $$EntitiesTableTableManager get entities =>
      $$EntitiesTableTableManager(_db, _db.entities);
  $$PdfFilesTableTableManager get pdfFiles =>
      $$PdfFilesTableTableManager(_db, _db.pdfFiles);
  $$DeviceTableTableManager get device =>
      $$DeviceTableTableManager(_db, _db.device);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
  $$ViewStatesTableTableManager get viewStates =>
      $$ViewStatesTableTableManager(_db, _db.viewStates);
}
