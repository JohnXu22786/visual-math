import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'math_drawing_document.dart';

/// App-private, cross-platform storage for named `.vm` documents.
/// The shared-preferences implementation maps to platform preferences on
/// native targets and browser-local storage on web.
class MathDrawingStorage {
  static const String _key = 'visual_math.documents.v1';
  const MathDrawingStorage();

  Future<List<String>> listNames() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const [];
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic>)
      throw const FormatException('Saved drawing index is damaged.');
    return value.keys.toList()..sort();
  }

  Future<MathDrawingDocument?> load(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic>)
      throw const FormatException('Saved drawing index is damaged.');
    final content = value[name];
    return content is String ? MathDrawingDocument.decode(content) : null;
  }

  /// Save a document. Existing names require an explicit [overwrite] choice.
  Future<void> save(
    MathDrawingDocument document, {
    bool overwrite = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    final value = raw == null ? <String, dynamic>{} : jsonDecode(raw);
    if (value is! Map<String, dynamic>)
      throw const FormatException('Saved drawing index is damaged.');
    if (value.containsKey(document.name) && !overwrite) {
      throw StateError(
        'A drawing named "${document.name}" already exists. Choose another name or confirm overwrite.',
      );
    }
    value[document.name] = document.encode();
    if (!await prefs.setString(_key, jsonEncode(value)))
      throw StateError('Could not save the drawing.');
  }

  Future<void> delete(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic>)
      throw const FormatException('Saved drawing index is damaged.');
    value.remove(name);
    await prefs.setString(_key, jsonEncode(value));
  }
}
