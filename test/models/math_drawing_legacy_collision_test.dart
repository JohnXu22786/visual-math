import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visual_math/src/models/math_drawing_storage_native.dart'
    as backend;
import 'package:visual_math/visual_math.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'keeps the legacy index when an existing drawing has the same name',
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
      ).encode();
      await backend.saveDocument(current, overwrite: false);
      const key = 'visual_math.documents.v1';
      SharedPreferences.setMockInitialValues({
        key: jsonEncode({'Same': legacy}),
      });

      const storage = MathDrawingStorage();
      expect((await storage.load('Same'))?.extensions['legacy'], isNull);
      final retained = (await SharedPreferences.getInstance()).getString(key);
      expect(retained, isNotNull);
      expect((jsonDecode(retained!) as Map)['Same'], legacy);
    },
  );
}
