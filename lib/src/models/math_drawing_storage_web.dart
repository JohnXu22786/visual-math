import 'package:idb_shim/idb_browser.dart';

import 'math_drawing_document.dart';
import 'math_drawing_storage_error.dart';

const _databaseName = 'visual_math_documents';
const _storeName = 'drawings';

Future<Database> _open() => idbFactoryBrowser.open(
  _databaseName,
  version: 1,
  onUpgradeNeeded: (event) => event.database.createObjectStore(_storeName),
);

Future<List<String>> listDocumentNames() async {
  final database = await _open();
  try {
    final transaction = database.transaction(_storeName, idbModeReadOnly);
    final keys = await transaction.objectStore(_storeName).getAllKeys();
    await transaction.completed;
    return keys.cast<String>()..sort();
  } finally {
    database.close();
  }
}

Future<Object?> loadDocumentSource(String name) async {
  final database = await _open();
  try {
    final transaction = database.transaction(_storeName, idbModeReadOnly);
    final value = await transaction.objectStore(_storeName).getObject(name);
    await transaction.completed;
    return value;
  } finally {
    database.close();
  }
}

Future<MathDrawingDocument?> loadDocument(String name) async {
  final database = await _open();
  try {
    final transaction = database.transaction(_storeName, idbModeReadOnly);
    final value = await transaction.objectStore(_storeName).getObject(name);
    await transaction.completed;
    if (value is! String) return null;
    final document = MathDrawingDocument.decode(value);
    return document.name == name
        ? document
        : MathDrawingDocument(
            name: name,
            drawing: document.drawing,
            extensions: document.extensions,
          );
  } finally {
    database.close();
  }
}

Future<void> saveDocument(
  MathDrawingDocument document, {
  required bool overwrite,
}) async {
  final database = await _open();
  try {
    final transaction = database.transaction(_storeName, idbModeReadWrite);
    final store = transaction.objectStore(_storeName);
    final existing = await store.getObject(document.name);
    if (existing != null && !overwrite) {
      transaction.abort();
      throw DuplicateDrawingException(document.name);
    }
    await store.put(document.encode(), document.name);
    await transaction.completed;
  } finally {
    database.close();
  }
}

Future<void> deleteDocument(String name) async {
  final database = await _open();
  try {
    final transaction = database.transaction(_storeName, idbModeReadWrite);
    await transaction.objectStore(_storeName).delete(name);
    await transaction.completed;
  } finally {
    database.close();
  }
}

Future<Map<String, String>> importLegacyDocuments(
  Map<String, String> documents,
) async {
  final remaining = <String, String>{};
  final database = await _open();
  try {
    final transaction = database.transaction(_storeName, idbModeReadWrite);
    final store = transaction.objectStore(_storeName);
    for (final entry in documents.entries) {
      if (await store.getObject(entry.key) == null) {
        await store.put(entry.value, entry.key);
      } else {
        remaining[entry.key] = entry.value;
      }
    }
    await transaction.completed;
    return remaining;
  } finally {
    database.close();
  }
}
