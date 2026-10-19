import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/id/id_generator.dart';
import '../../../data/db/database.dart';
import '../../../data/pdf/pdf_password_cache.dart';
import '../../../data/pdf/pdf_storage.dart';
import '../../../domain/commands/command.dart';
import '../../../domain/commands/command_bus.dart';
import '../../../domain/model/models.dart';
import '../../../domain/ops/entity_state.dart';
import '../../../domain/ops/op.dart';
import '../../../domain/ops/op_store.dart';
import '../../canvas/engine/scene.dart';
import '../../canvas/pdf/pdf_source.dart';
import 'pdf_inspector.dart';

/// One file to import.
class ImportRequest {
  const ImportRequest(this.path, {this.deleteSourceAfter = false});

  final String path;

  /// The source is a temporary copy made for us (Android picker or share
  /// intent), so it is removed once imported or rejected.
  final bool deleteSourceAfter;

  String get displayName => p.basename(path);
}

class ImportResult {
  const ImportResult({
    required this.docId,
    required this.title,
    required this.created,
  });

  final String docId;
  final String title;

  /// False when the same file was already in the library and was reused.
  final bool created;
}

/// Brings a PDF into the library: stores it once by content hash, validates
/// and describes it with pdfium, and creates its document and page entities as
/// one undoable command.
class PdfImporter {
  PdfImporter({
    required this.store,
    required this.bus,
    required this.storage,
    required this.inspector,
    required this.db,
    required this.ids,
    this.passwords,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final OpStore store;
  final CommandBus bus;
  final PdfStorage storage;
  final PdfInspector inspector;
  final AetherDatabase db;
  final IdGenerator ids;

  /// Where a password that worked is remembered for this session, so opening
  /// the document next does not ask again.
  final PdfPasswordCache? passwords;
  final DateTime Function() _now;

  /// Throws [PdfOpenException] for files that are not (openable) PDFs; other
  /// I/O errors propagate as they are. The library is unchanged on failure.
  Future<ImportResult> import(
    ImportRequest req, {
    PasswordProvider? password,
  }) async {
    StoredCopy? copy;
    try {
      copy = await storage.copyIn(File(req.path).openRead());
      final hash = copy.hash;

      // The same bytes again: reuse the existing document.
      final existing = await _documentWithHash(hash, includeDeleted: false);
      if (existing != null) {
        await storage.discard(copy);
        copy = null;
        return ImportResult(
          docId: existing.id,
          title: Document.fromState(existing).title,
          created: false,
        );
      }

      final alreadyStored = storage.hasPdf(hash);
      final dest = await storage.commit(copy);
      copy = null;

      final PdfInfo info;
      final attempt = password == null
          ? null
          : (passwords ?? PdfPasswordCache()).attempt(hash, password);
      try {
        info = await inspector.inspect(dest, password: attempt?.provide);
        attempt?.accepted();
      } catch (_) {
        // Do not keep a file we cannot open, unless something (even a
        // deleted document that undo could bring back) still refers to it.
        if (!alreadyStored &&
            await _documentWithHash(hash, includeDeleted: true) == null) {
          await storage.delete(hash);
        }
        rethrow;
      }

      final title = _titleFrom(req.path);
      final docId = ids.next();
      final layout = Scene.column(info.pageSizes);
      final factory = CommandFactory(store);
      await bus.run(
        Command.group('Import $title', [
          factory.create(
            EntityKind.document,
            docId,
            Document(
              id: docId,
              title: title,
              sourceHash: hash,
              pageCount: info.pageSizes.length,
            ).toFields(),
            label: 'Import',
          ),
          for (final card in layout.cards)
            factory.create(
              EntityKind.page,
              ids.next(),
              PageRef(
                id: '',
                docId: docId,
                index: card.index,
                width: card.rect.width,
                height: card.rect.height,
                cardX: card.rect.left,
                cardY: card.rect.top,
              ).toFields(),
              label: 'Import',
            ),
        ]),
      );

      await db.putPdfFile(
        sourceHash: hash,
        path: dest,
        byteLength: File(dest).lengthSync(),
        importedAt: _now(),
      );
      final png = info.thumbnailPng;
      if (png != null) await storage.writeThumbnail(hash, png);
      return ImportResult(docId: docId, title: title, created: true);
    } finally {
      if (copy != null) await storage.discard(copy);
      if (req.deleteSourceAfter) {
        try {
          final f = File(req.path);
          if (f.existsSync()) await f.delete();
          // A temporary copy lives alone in its own folder: remove that too.
          // (Non-recursive, so it only goes if it is empty.)
          await f.parent.delete();
        } catch (_) {}
      }
    }
  }

  Future<EntityState?> _documentWithHash(
    String hash, {
    required bool includeDeleted,
  }) async {
    final docs = await store.entities(
      kind: EntityKind.document,
      includeDeleted: includeDeleted,
    );
    for (final d in docs) {
      if (d.field<String>(F.sourceHash) == hash) return d;
    }
    return null;
  }

  /// The file name without a trailing `.pdf`. Stripped by hand: `path` treats a
  /// bare ".pdf" as a hidden file with no extension.
  static String _titleFrom(String path) {
    final base = p.basename(path);
    var name =
        (base.toLowerCase().endsWith('.pdf')
                ? base.substring(0, base.length - 4)
                : p.basenameWithoutExtension(path))
            .trim();
    if (name.isEmpty) name = 'Untitled';
    return name;
  }
}
