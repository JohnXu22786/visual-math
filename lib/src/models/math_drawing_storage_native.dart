import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'math_drawing_document.dart';
import 'math_drawing_storage_error.dart';

Future<Directory> _documentsDirectory() async {
  final app = await getApplicationDocumentsDirectory();
  final directory = Directory(
    '${app.path}${Platform.pathSeparator}visual_math',
  );
  await directory.create(recursive: true);
  return directory;
}

String _fileName(String name) =>
    'doc-${base64Url.encode(utf8.encode(name)).replaceAll('=', '')}.vm';

final Map<String, Future<void>> _saveTails = {};

Future<List<String>> listDocumentNames() async {
  final directory = await _documentsDirectory();
  final names = <String>[];
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.vm')) continue;
    try {
      names.add(MathDrawingDocument.decode(await entity.readAsString()).name);
    } on FormatException {
      // Keep malformed documents visible by their safe encoded filename.
      final base = entity.uri.pathSegments.last.replaceFirst(
        RegExp(r'\.vm$'),
        '',
      );
      try {
        names.add(utf8.decode(base64Url.decode(base.replaceFirst('doc-', ''))));
      } catch (_) {
        continue;
      }
    }
  }
  names.sort();
  return names;
}

Future<File> _fileFor(String name) async => File(
  '${(await _documentsDirectory()).path}${Platform.pathSeparator}${_fileName(name)}',
);

Future<MathDrawingDocument?> loadDocument(String name) async {
  final file = await _fileFor(name);
  if (!await file.exists()) return null;
  return MathDrawingDocument.decode(await file.readAsString());
}

Future<void> saveDocument(
  MathDrawingDocument document, {
  required bool overwrite,
}) async {
  final previous = _saveTails[document.name] ?? Future<void>.value();
  final completion = Completer<void>();
  _saveTails[document.name] = completion.future;
  await previous;
  try {
    await _saveDocument(document, overwrite: overwrite);
  } finally {
    if (identical(_saveTails[document.name], completion.future)) {
      _saveTails.remove(document.name);
    }
    completion.complete();
  }
}

Future<void> _saveDocument(
  MathDrawingDocument document, {
  required bool overwrite,
}) async {
  final target = await _fileFor(document.name);
  if (await target.exists() && !overwrite) {
    throw DuplicateDrawingException(document.name);
  }
  final temp = File(
    '${target.path}.${pid}.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  await temp.writeAsString(document.encode(), flush: true);
  try {
    await temp.rename(target.path);
  } catch (_) {
    if (!overwrite || !await target.exists()) rethrow;
    final backup = File('${target.path}.backup');
    await target.rename(backup.path);
    try {
      await temp.rename(target.path);
      await backup.delete();
    } catch (_) {
      if (!await target.exists() && await backup.exists())
        await backup.rename(target.path);
      rethrow;
    }
  } finally {
    if (await temp.exists()) await temp.delete();
  }
}

Future<void> deleteDocument(String name) async {
  final file = await _fileFor(name);
  if (await file.exists()) await file.delete();
}

Future<void> importLegacyDocuments(Map<String, String> documents) async {
  for (final entry in documents.entries) {
    final target = await _fileFor(entry.key);
    if (await target.exists()) continue;
    final temp = File(
      '${target.path}.${pid}.${DateTime.now().microsecondsSinceEpoch}.migration.tmp',
    );
    await temp.writeAsString(entry.value, flush: true);
    try {
      await temp.rename(target.path);
    } catch (_) {
      if (!await target.exists()) rethrow;
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }
}
