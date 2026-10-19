import 'package:uuid/uuid.dart';

/// Source of globally unique, time-ordered ids (UUIDv7).
abstract interface class IdGenerator {
  String next();
}

class UuidV7Generator implements IdGenerator {
  const UuidV7Generator();
  static const _uuid = Uuid();

  @override
  String next() => _uuid.v7();
}

/// Deterministic ids for tests: `id-0001`, `id-0002`, ...
class SequentialIdGenerator implements IdGenerator {
  SequentialIdGenerator([this.prefix = 'id']);
  final String prefix;
  int _n = 0;

  @override
  String next() => '$prefix-${(++_n).toString().padLeft(4, '0')}';
}

/// A fresh device id: 32 lowercase hex chars, no hyphens (safe inside an HLC).
String newDeviceId() => const Uuid().v4().replaceAll('-', '');
