import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'math_drawing_document.dart';
export 'math_drawing_storage_error.dart';
import 'math_drawing_storage_native.dart'
    if (dart.library.js_interop) 'math_drawing_storage_web.dart'
    as backend;

/// App-private `.vm` document storage. Native platforms use files; web uses
/// IndexedDB. The API keeps list, read, atomic write, and overwrite policy common.
class MathDrawingStorage {
  static const _legacyDocumentsKey = 'visual_math.documents.v1';
  static Future<void>? _migration;

  const MathDrawingStorage();

  Future<List<String>> listNames() async {
    await _ensureLegacyDocumentsMigrated();
    return backend.listDocumentNames();
  }

  Future<MathDrawingDocument?> load(String name) async {
    await _ensureLegacyDocumentsMigrated();
    return backend.loadDocument(name);
  }

  Future<void> save(
    MathDrawingDocument document, {
    bool overwrite = false,
  }) async {
    await _ensureLegacyDocumentsMigrated();
    await backend.saveDocument(document, overwrite: overwrite);
  }

  Future<void> delete(String name) async {
    await _ensureLegacyDocumentsMigrated();
    await backend.deleteDocument(name);
  }

  static Future<void> _ensureLegacyDocumentsMigrated() {
    final current = _migration;
    if (current != null) return current;
    final migration = _migrateLegacyDocuments();
    _migration = migration;
    return migration.catchError((Object error, StackTrace stack) {
      _migration = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  static Future<void> _migrateLegacyDocuments() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_legacyDocumentsKey);
    if (raw == null) return;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> ||
        decoded.values.any((value) => value is! String)) {
      throw const FormatException('Saved drawing index is damaged.');
    }
    final remaining = await backend.importLegacyDocuments(
      decoded.cast<String, String>(),
    );
    // Reserve all original keys so a recovery cannot take another legacy name.
    for (final entry in remaining.entries.toList()) {
      if (await backend.loadDocumentSource(entry.key) == entry.value) {
        remaining.remove(entry.key);
        continue;
      }
      var index = 1;
      while (true) {
        final name = '${entry.key} (recovered $index)';
        index++;
        if (decoded.containsKey(name)) continue;
        final source = entry.value;
        final existing = await backend.loadDocumentSource(name);
        if (existing == source) break;
        if (existing != null) continue;
        final rejected = await backend.importLegacyDocuments({name: source});
        if (rejected.isEmpty) break;
      }
      remaining.remove(entry.key);
    }
    final saved = remaining.isEmpty
        ? await preferences.remove(_legacyDocumentsKey)
        : await preferences.setString(
            _legacyDocumentsKey,
            jsonEncode(remaining),
          );
    if (!saved) {
      throw StateError('Migrated drawings but could not remove the old index.');
    }
  }
}
