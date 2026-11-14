import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visual_math/src/models/math_drawing_storage_native.dart'
    as backend;
import 'package:visual_math/visual_math.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('preserves legacy collision payload bytes during filename recovery', () async {
    final directory = await Directory.systemTemp.createTemp(
      'drawing-legacy-filename-collision-',
    );
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => directory.path);
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await directory.delete(recursive: true);
    });

    final drawing = MathDrawingSnapshot(
      formulas: const [],
      parameters: const {},
      activeView: ViewMode.mode2D,
      activeTool: ConstructionTool.move,
      viewport2D: Viewport.defaultViewport(),
      camera3D: const Camera3D(),
      projection3D: ProjectionType.parallel,
      scene3D: const [],
    );
    final storageDirectory = Directory('${directory.path}/visual_math');
    await storageDirectory.create();
    const originalName = 'Same';
    String hashFile(String name) =>
        '${storageDirectory.path}/hash-${sha256.convert(utf8.encode(name))}.vm';
    Future<void> writeDocument(String name) async {
      final file = File(hashFile(name));
      await file.writeAsString(
        MathDrawingDocument(name: name, drawing: drawing).encode(),
      );
      await File('${file.path}.name').writeAsString(name);
    }

    final legacy = MathDrawingDocument(
      name: originalName,
      drawing: drawing,
      extensions: const {'legacy': true},
    ).encode().replaceFirst('{', '{"opaque":900719925474099312345,');
    final legacyFilename = base64Url
        .encode(utf8.encode(originalName))
        .replaceAll('=', '');
    await File('${storageDirectory.path}/doc-$legacyFilename.vm')
        .writeAsString(legacy);
    await writeDocument(originalName);
    await writeDocument('$originalName (recovered 1)');

    await backend.listDocumentNames();

    expect(
      await File(hashFile('$originalName (recovered 2)')).readAsBytes(),
      utf8.encode(legacy),
    );
    expect(
      await File('${hashFile('$originalName (recovered 2)')}.name')
          .readAsString(),
      '$originalName (recovered 2)',
    );
  });

  test('repairs recovered name metadata before deleting duplicate legacy files', () async {
    final directory = await Directory.systemTemp.createTemp(
      'drawing-legacy-recovery-metadata-',
    );
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => directory.path);
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await directory.delete(recursive: true);
    });

    final drawing = MathDrawingSnapshot(
      formulas: const [],
      parameters: const {},
      activeView: ViewMode.mode2D,
      activeTool: ConstructionTool.move,
      viewport2D: Viewport.defaultViewport(),
      camera3D: const Camera3D(),
      projection3D: ProjectionType.parallel,
      scene3D: const [],
    );
    final storageDirectory = Directory('${directory.path}/visual_math');
    await storageDirectory.create();
    const originalName = 'Same';
    String hashFile(String name) =>
        '${storageDirectory.path}/hash-${sha256.convert(utf8.encode(name))}.vm';
    Future<void> writeDocument(String name) async {
      final file = File(hashFile(name));
      await file.writeAsString(
        MathDrawingDocument(name: name, drawing: drawing).encode(),
      );
      await File('${file.path}.name').writeAsString(name);
    }

    final legacy = MathDrawingDocument(
      name: originalName,
      drawing: drawing,
      extensions: const {'legacy': true},
    ).encode().replaceFirst('{', '{"opaque":900719925474099312345,');
    final legacyFilename = base64Url
        .encode(utf8.encode(originalName))
        .replaceAll('=', '');
    final source = File('${storageDirectory.path}/doc-$legacyFilename.vm');
    await source.writeAsString(legacy);
    await writeDocument(originalName);
    await writeDocument('$originalName (recovered 1)');
    await File(hashFile('$originalName (recovered 2)')).writeAsString(legacy);

    await backend.listDocumentNames();

    expect(await source.exists(), isFalse);
    expect(
      await File('${hashFile('$originalName (recovered 2)')}.name')
          .readAsString(),
      '$originalName (recovered 2)',
    );
    expect(
      await backend.listDocumentNames(),
      contains('$originalName (recovered 2)'),
    );
  });

  test(
    'recovers a colliding legacy drawing without overwriting existing names',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'drawing-collision-',
      );
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => directory.path);
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await directory.delete(recursive: true);
      });
      final drawing = MathDrawingSnapshot(
        formulas: const [],
        parameters: const {},
        activeView: ViewMode.mode2D,
        activeTool: ConstructionTool.move,
        viewport2D: Viewport.defaultViewport(),
        camera3D: const Camera3D(),
        projection3D: ProjectionType.parallel,
        scene3D: const [],
      );
      final current = MathDrawingDocument(name: 'Same', drawing: drawing);
      final legacy = MathDrawingDocument(
        name: 'Same',
        drawing: drawing,
        extensions: const {'legacy': true},
      ).encode().replaceFirst('{', '{"opaque":900719925474099312345,');
      await backend.saveDocument(current, overwrite: false);
      await backend.saveDocument(
        MathDrawingDocument(name: 'Same (recovered 1)', drawing: drawing),
        overwrite: false,
      );
      const key = 'visual_math.documents.v1';
      SharedPreferences.setMockInitialValues({
        key: jsonEncode({'Same': legacy}),
      });

      const storage = MathDrawingStorage();
      expect((await storage.load('Same'))?.extensions['legacy'], isNull);
      expect(await storage.listNames(), [
        'Same',
        'Same (recovered 1)',
        'Same (recovered 2)',
      ]);
      expect(
        (await storage.load('Same (recovered 2)'))?.extensions['legacy'],
        isTrue,
      );
      expect(
        (await storage.load('Same (recovered 1)'))?.extensions['legacy'],
        isNull,
      );
      final recoveredHash = sha256.convert(utf8.encode('Same (recovered 2)'));
      final recoveredFile = File(
        '${directory.path}/visual_math/hash-$recoveredHash.vm',
      );
      expect(await recoveredFile.readAsString(), legacy);
      expect((await SharedPreferences.getInstance()).getString(key), isNull);
    },
  );
}
