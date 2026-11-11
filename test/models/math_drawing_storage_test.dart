import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visual_math/visual_math.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('migrates legacy preference documents into app-private files', () async {
    final directory = await Directory.systemTemp.createTemp(
      'visual-math-storage-migration-',
    );
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => directory.path);
    const legacyDocumentKey = 'visual_math.documents.v1';
    SharedPreferences.setMockInitialValues({
      legacyDocumentKey: jsonEncode({
        'Legacy':
            MathDrawingDocument(
              name: 'Legacy',
              drawing: MathDrawingSnapshot(
                formulas: const [],
                parameters: const {},
                activeView: ViewMode.mode2D,
                activeTool: ConstructionTool.move,
                viewport2D: Viewport.defaultViewport(),
                camera3D: const Camera3D(),
                projection3D: ProjectionType.parallel,
                scene3D: const [],
              ),
            ).encode(),
      }),
    });
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    const storage = MathDrawingStorage();
    expect(await storage.listNames(), ['Legacy']);
    expect((await storage.load('Legacy'))?.name, 'Legacy');
    expect(
      (await SharedPreferences.getInstance()).getString(legacyDocumentKey),
      isNull,
    );
  });

  test(
    'writes app-private .vm files and requires explicit overwrite',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'visual-math-storage-',
      );
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => directory.path);
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        if (await directory.exists()) await directory.delete(recursive: true);
      });

      const storage = MathDrawingStorage();
      final drawing = MathDrawingSnapshot(
        formulas: [],
        parameters: {},
        activeView: ViewMode.mode2D,
        activeTool: ConstructionTool.move,
        viewport2D: Viewport.defaultViewport(),
        camera3D: const Camera3D(),
        projection3D: ProjectionType.parallel,
        scene3D: const [],
      );
      await storage.save(MathDrawingDocument(name: 'Alpha', drawing: drawing));
      expect(await storage.listNames(), ['Alpha']);
      expect((await storage.load('Alpha'))!.name, 'Alpha');
      final files = Directory('${directory.path}/visual_math')
          .listSync()
          .whereType<File>();
      expect(files.single.path, endsWith('.vm'));
      expect(
        await files.single.readAsString(),
        contains('visual-math-drawing'),
      );
      await expectLater(
        storage.save(MathDrawingDocument(name: 'Alpha', drawing: drawing)),
        throwsStateError,
      );
      await storage.save(
        MathDrawingDocument(name: 'Alpha', drawing: drawing),
        overwrite: true,
      );

      final beta = MathDrawingDocument(name: 'Beta', drawing: drawing);
      Future<Object?> saveWithoutOverwrite() async {
        try {
          await storage.save(beta);
          return null;
        } catch (error) {
          return error;
        }
      }

      final concurrentResults = await Future.wait([
        saveWithoutOverwrite(),
        saveWithoutOverwrite(),
      ]);
      expect(concurrentResults.where((result) => result == null), hasLength(1));
      expect(concurrentResults.whereType<StateError>(), hasLength(1));
    },
  );


}
