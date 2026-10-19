// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'spike_db.dart';

// ignore_for_file: type=lint
class $MarksTable extends Marks with TableInfo<$MarksTable, Mark> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MarksTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<Uint8List> payload = GeneratedColumn<Uint8List>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, kind, payload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'marks';
  @override
  VerificationContext validateIntegrity(
    Insertable<Mark> instance, {
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
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Mark map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Mark(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $MarksTable createAlias(String alias) {
    return $MarksTable(attachedDatabase, alias);
  }
}

class Mark extends DataClass implements Insertable<Mark> {
  final String id;
  final String kind;
  final Uint8List payload;
  const Mark({required this.id, required this.kind, required this.payload});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['kind'] = Variable<String>(kind);
    map['payload'] = Variable<Uint8List>(payload);
    return map;
  }

  MarksCompanion toCompanion(bool nullToAbsent) {
    return MarksCompanion(
      id: Value(id),
      kind: Value(kind),
      payload: Value(payload),
    );
  }

  factory Mark.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Mark(
      id: serializer.fromJson<String>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      payload: serializer.fromJson<Uint8List>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'kind': serializer.toJson<String>(kind),
      'payload': serializer.toJson<Uint8List>(payload),
    };
  }

  Mark copyWith({String? id, String? kind, Uint8List? payload}) => Mark(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    payload: payload ?? this.payload,
  );
  Mark copyWithCompanion(MarksCompanion data) {
    return Mark(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Mark(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, kind, $driftBlobEquality.hash(payload));
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Mark &&
          other.id == this.id &&
          other.kind == this.kind &&
          $driftBlobEquality.equals(other.payload, this.payload));
}

class MarksCompanion extends UpdateCompanion<Mark> {
  final Value<String> id;
  final Value<String> kind;
  final Value<Uint8List> payload;
  final Value<int> rowid;
  const MarksCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MarksCompanion.insert({
    required String id,
    required String kind,
    required Uint8List payload,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       kind = Value(kind),
       payload = Value(payload);
  static Insertable<Mark> custom({
    Expression<String>? id,
    Expression<String>? kind,
    Expression<Uint8List>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MarksCompanion copyWith({
    Value<String>? id,
    Value<String>? kind,
    Value<Uint8List>? payload,
    Value<int>? rowid,
  }) {
    return MarksCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      payload: payload ?? this.payload,
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
    if (payload.present) {
      map['payload'] = Variable<Uint8List>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MarksCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$SpikeDb extends GeneratedDatabase {
  _$SpikeDb(QueryExecutor e) : super(e);
  $SpikeDbManager get managers => $SpikeDbManager(this);
  late final $MarksTable marks = $MarksTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [marks];
}

typedef $$MarksTableCreateCompanionBuilder = MarksCompanion Function({
  required String id,
  required String kind,
  required Uint8List payload,
  Value<int> rowid,
});
typedef $$MarksTableUpdateCompanionBuilder = MarksCompanion Function({
  Value<String> id,
  Value<String> kind,
  Value<Uint8List> payload,
  Value<int> rowid,
});

class $$MarksTableFilterComposer extends Composer<_$SpikeDb, $MarksTable> {
  $$MarksTableFilterComposer({
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

  ColumnFilters<Uint8List> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MarksTableOrderingComposer extends Composer<_$SpikeDb, $MarksTable> {
  $$MarksTableOrderingComposer({
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

  ColumnOrderings<Uint8List> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MarksTableAnnotationComposer extends Composer<_$SpikeDb, $MarksTable> {
  $$MarksTableAnnotationComposer({
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

  GeneratedColumn<Uint8List> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$MarksTableTableManager
    extends
        RootTableManager<
          _$SpikeDb,
          $MarksTable,
          Mark,
          $$MarksTableFilterComposer,
          $$MarksTableOrderingComposer,
          $$MarksTableAnnotationComposer,
          $$MarksTableCreateCompanionBuilder,
          $$MarksTableUpdateCompanionBuilder,
          (Mark, BaseReferences<_$SpikeDb, $MarksTable, Mark>),
          Mark,
          PrefetchHooks Function()
        > {
  $$MarksTableTableManager(_$SpikeDb db, $MarksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MarksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MarksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MarksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<Uint8List> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MarksCompanion(
                id: id,
                kind: kind,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String kind,
                required Uint8List payload,
                Value<int> rowid = const Value.absent(),
              }) => MarksCompanion.insert(
                id: id,
                kind: kind,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MarksTable, Mark>(table),
                  BaseReferences<_$SpikeDb, $MarksTable, Mark>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MarksTableProcessedTableManager =
    ProcessedTableManager<
      _$SpikeDb,
      $MarksTable,
      Mark,
      $$MarksTableFilterComposer,
      $$MarksTableOrderingComposer,
      $$MarksTableAnnotationComposer,
      $$MarksTableCreateCompanionBuilder,
      $$MarksTableUpdateCompanionBuilder,
      (Mark, BaseReferences<_$SpikeDb, $MarksTable, Mark>),
      Mark,
      PrefetchHooks Function()
    >;

class $SpikeDbManager {
  final _$SpikeDb _db;
  $SpikeDbManager(this._db);
  $$MarksTableTableManager get marks =>
      $$MarksTableTableManager(_db, _db.marks);
}
