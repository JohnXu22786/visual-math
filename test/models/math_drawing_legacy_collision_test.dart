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
