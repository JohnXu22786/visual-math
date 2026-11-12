import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'math_drawing_document.dart';
import 'math_drawing_storage_error.dart';

Future<Directory> _documentsDirectory() async {
  final app = await getApplicationDocumentsDirectory();
  final directory = Directory(
    '${app.path}${Platform.pathSeparator}visual_math',
  );
  await directory.create(recursive: true);
  await _recoverOverwriteBackups(directory);
  await _migrateFileNames(directory);
  await _recoverMalformedConflicts(directory);
  return directory;
}

Future<void> _storeTail = Future<void>.value();

Future<T> _locked<T>(Future<T> Function() operation) async {
  final previous = _storeTail;
  final done = Completer<void>();
  _storeTail = done.future;
  await previous;
  try {
    return await operation();
  } finally {
    done.complete();
  }
}

File _nameFile(File file) => File('${file.path}.name');

String _fileName(String name) => 'hash-${sha256.convert(utf8.encode(name))}.vm';

String? _legacyName(String base) {
  if (!base.startsWith('doc-') || !base.endsWith('.vm')) return null;
  final encoded = base.substring(4, base.length - 3);
  try {
    final name = utf8.decode(base64Url.decode(base64Url.normalize(encoded)));
    if (base64Url.encode(utf8.encode(name)).replaceAll('=', '') == encoded) {
      return name;
    }
  } on FormatException {
    // Ignore files that do not use the legacy filename format.
  }
  return null;
}

Future<void> _recoverOverwriteBackups(Directory directory) async {
  final backupName = RegExp(r'^hash-[0-9a-f]{64}\.vm\.backup$');
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is! File || !backupName.hasMatch(entity.uri.pathSegments.last)) {
      continue;
    }
    final target = File(entity.path.substring(0, entity.path.length - 7));
    if (await target.exists()) {
      await entity.delete();
    } else {
      await entity.rename(target.path);
    }
  }
}

Future<void> _migrateFileNames(Directory directory) async {
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is! File || _legacyName(entity.uri.pathSegments.last) == null) {
      continue;
    }
    final String source;
    final String name;
    try {
      source = utf8.decode(await entity.readAsBytes());
      name = MathDrawingDocument.decode(source).name;
    } on FormatException {
      // Keep malformed files under their reversible legacy names.
      continue;
    }
    final target = File(
      '${directory.path}${Platform.pathSeparator}${_fileName(name)}',
    );
    if (!await target.exists()) {
      await _nameFile(target).writeAsString(name, flush: true);
      await entity.rename(target.path);
      continue;
    }
    if (base64Encode(await target.readAsBytes()) ==
        base64Encode(utf8.encode(source))) {
      await entity.delete();
      continue;
    }
    // Keep a distinct, accessible copy when an older app changed the file.
    var index = 1;
    while (true) {
      final recoveredName = '$name (recovered $index)';
      final recovered = File(
        '${directory.path}${Platform.pathSeparator}${_fileName(recoveredName)}',
      );
      final json = jsonDecode(source) as Map<String, dynamic>;
      json['name'] = recoveredName;
      final contents = jsonEncode(json);
      if (await recovered.exists()) {
        if (base64Encode(await recovered.readAsBytes()) ==
            base64Encode(utf8.encode(contents))) {
          await entity.delete();
          break;
        }
      } else if ((await _legacyFiles(directory, recoveredName)).isEmpty) {
        final temp = File('${recovered.path}.migration.tmp');
        await _nameFile(recovered).writeAsString(recoveredName, flush: true);
        try {
          await temp.writeAsString(contents, flush: true);
          await temp.rename(recovered.path);
          await entity.delete();
        } finally {
          if (await temp.exists()) await temp.delete();
        }
        break;
      }
      index++;
    }
  }
}

Future<void> _recoverMalformedConflicts(Directory directory) async {
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is! File) continue;
    final name = _legacyName(entity.uri.pathSegments.last);
    if (name == null) continue;
    try {
      MathDrawingDocument.decode(utf8.decode(await entity.readAsBytes()));
      continue;
    } on FormatException {
      // The original filename is the only source of this damaged file's name.
    }
    final target = File(
      '${directory.path}${Platform.pathSeparator}${_fileName(name)}',
    );
    if (!await target.exists()) continue;
    var index = 1;
    while (true) {
      final recoveredName = '$name (recovered $index)';
      final recovered = File(
        '${directory.path}${Platform.pathSeparator}${_fileName(recoveredName)}',
      );
      if (!await recovered.exists() &&
          (await _legacyFiles(directory, recoveredName)).isEmpty) {
        await _nameFile(recovered).writeAsString(recoveredName, flush: true);
        await entity.rename(recovered.path);
        break;
      }
      index++;
    }
  }
}

Future<List<File>> _legacyFiles(Directory directory, String name) async {
  final files = <File>[];
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is! File) continue;
    final encodedName = _legacyName(entity.uri.pathSegments.last);
    if (encodedName == null) continue;
    try {
      if (MathDrawingDocument.decode(utf8.decode(await entity.readAsBytes()))
              .name ==
          name) {
        files.add(entity);
      }
    } on FormatException {
      if (encodedName == name) files.add(entity);
    }
  }
  return files;
}

Future<List<String>> listDocumentNames() => _locked(_listDocumentNames);

Future<List<String>> _listDocumentNames() async {
  final directory = await _documentsDirectory();
  final names = <String>{};
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.vm')) continue;
    try {
      names.add(
        MathDrawingDocument.decode(utf8.decode(await entity.readAsBytes()))
            .name,
      );
    } on FormatException {
      var name = _legacyName(entity.uri.pathSegments.last);
      final nameFile = _nameFile(entity);
      if (name == null && await nameFile.exists()) {
        try {
          final savedName = utf8.decode(await nameFile.readAsBytes());
          if (_fileName(savedName) == entity.uri.pathSegments.last)
            name = savedName;
        } on FormatException {
          // A damaged name file cannot identify the document.
        }
      }
      if (name != null) names.add(name);
    }
  }
  return names.toList()..sort();
}

Future<File> _fileFor(String name) async => File(
  '${(await _documentsDirectory()).path}${Platform.pathSeparator}${_fileName(name)}',
);

Future<MathDrawingDocument?> loadDocument(String name) =>
    _locked(() => _loadDocument(name));

Future<MathDrawingDocument?> _loadDocument(String name) async {
  final file = await _fileFor(name);
  if (await file.exists())
    return MathDrawingDocument.decode(utf8.decode(await file.readAsBytes()));
  final legacy = await _legacyFiles(file.parent, name);
  if (legacy.isEmpty) return null;
  return MathDrawingDocument.decode(
    utf8.decode(await legacy.first.readAsBytes()),
  );
}

Future<void> saveDocument(
  MathDrawingDocument document, {
  required bool overwrite,
}) => _locked(() => _saveDocument(document, overwrite: overwrite));

Future<void> _saveDocument(
  MathDrawingDocument document, {
  required bool overwrite,
}) async {
  final target = await _fileFor(document.name);
  final legacy = await _legacyFiles(target.parent, document.name);
  if ((await target.exists() || legacy.isNotEmpty) && !overwrite) {
    throw DuplicateDrawingException(document.name);
  }
  final temp = File(
    '${target.path}.${pid}.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  await _nameFile(target).writeAsString(document.name, flush: true);
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
  for (final file in legacy) {
    if (await file.exists()) await file.delete();
  }
}

Future<void> deleteDocument(String name) =>
    _locked(() => _deleteDocument(name));

Future<void> _deleteDocument(String name) async {
  final file = await _fileFor(name);
  if (await file.exists()) await file.delete();
  final nameFile = _nameFile(file);
  if (await nameFile.exists()) await nameFile.delete();
  final legacy = await _legacyFiles(file.parent, name);
  for (final file in legacy) {
    await file.delete();
  }
}

Future<Map<String, String>> importLegacyDocuments(
  Map<String, String> documents,
) => _locked(() => _importLegacyDocuments(documents));

Future<Map<String, String>> _importLegacyDocuments(
  Map<String, String> documents,
) async {
  final remaining = <String, String>{};
  for (final entry in documents.entries) {
    final target = await _fileFor(entry.key);
    if (await target.exists() ||
        (await _legacyFiles(target.parent, entry.key)).isNotEmpty) {
      remaining[entry.key] = entry.value;
      continue;
    }
    final temp = File(
      '${target.path}.${pid}.${DateTime.now().microsecondsSinceEpoch}.migration.tmp',
    );
    await _nameFile(target).writeAsString(entry.key, flush: true);
    await temp.writeAsString(entry.value, flush: true);
    try {
      await temp.rename(target.path);
    } catch (_) {
      if (!await target.exists()) rethrow;
      remaining[entry.key] = entry.value;
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }
  return remaining;
}
