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
        'Legacy': MathDrawingDocument(
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
    'migrates old filenames and keeps case-folding collisions separate',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'visual-math-casefold-',
      );
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => directory.path);
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        if (await directory.exists()) await directory.delete(recursive: true);
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
      SharedPreferences.setMockInitialValues({});
      final oldDir = Directory('${directory.path}/visual_math');
      await oldDir.create();
      await File('${oldDir.path}/doc-QUFB.vm').writeAsString(
        MathDrawingDocument(name: 'AAA', drawing: drawing).encode(),
      );
      const storage = MathDrawingStorage();
      expect((await storage.load('AAA'))?.name, 'AAA');
      await storage.save(MathDrawingDocument(name: 'AA[', drawing: drawing));
      expect(await storage.listNames(), ['AAA', 'AA[']);
      final paths = oldDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.vm'))
          .map((f) => f.path.toLowerCase())
          .toSet();
      expect(paths, hasLength(2));
      expect((await storage.load('AA['))?.name, 'AA[');
      // A legacy case collision can leave a mismatched encoded filename.
      await File('${oldDir.path}/doc-QUFB.vm').writeAsString(
        MathDrawingDocument(name: 'AA[', drawing: drawing).encode(),
      );
      await storage.delete('AA[');
      expect((await storage.load('AAA'))?.name, 'AAA');
      expect(await storage.load('AA['), isNull);
      final remaining = oldDir.listSync().whereType<File>().singleWhere(
        (file) => file.path.endsWith('.vm'),
      );
      await remaining.writeAsString('damaged');
      expect(await storage.listNames(), ['AAA']);
      await expectLater(storage.load('AAA'), throwsFormatException);
      await storage.delete('AAA');
      expect(await storage.listNames(), isEmpty);
      final longName = 'a' * 180;
      final oldName = base64Url
          .encode(utf8.encode(longName))
          .replaceAll('=', '');
      await File('${oldDir.path}/doc-$oldName.vm').writeAsString(
        MathDrawingDocument(name: longName, drawing: drawing).encode(),
      );
      expect((await storage.load(longName))?.name, longName);
      await File('${oldDir.path}/doc-$oldName.vm').writeAsString(
        MathDrawingDocument(
          name: longName,
          drawing: drawing,
          extensions: const {'older': true},
        ).encode(),
      );
      final recoveredName = '$longName (recovered 1)';
      expect(await storage.listNames(), [longName, recoveredName]);
      expect((await storage.load(recoveredName))?.extensions['older'], isTrue);
      await File('${oldDir.path}/doc-$oldName.vm').writeAsString('damaged');
      final damagedName = '$longName (recovered 2)';
      expect(await storage.listNames(), [longName, recoveredName, damagedName]);
      await expectLater(storage.load(damagedName), throwsFormatException);
      await storage.delete(longName);
      expect((await storage.load(recoveredName))?.extensions['older'], isTrue);
      await storage.save(MathDrawingDocument(name: 'AAA', drawing: drawing));
      final aaaFile = oldDir.listSync().whereType<File>().firstWhere(
        (f) =>
            f.path.endsWith('.vm') &&
            f.readAsStringSync().contains('\"name\": \"AAA\"'),
      );
      await aaaFile.writeAsBytes([255]);
      await File('${oldDir.path}/doc-QUFB.vm').writeAsString(
        MathDrawingDocument(name: 'AAA', drawing: drawing).encode(),
      );
      expect(
        await storage.listNames(),
        containsAll(['AAA', 'AAA (recovered 1)']),
      );
      expect(
        (await storage.load('AAA (recovered 1)'))?.name,
        'AAA (recovered 1)',
      );
    },
  );

  test(
    'recovers interrupted overwrites without replacing completed writes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'drawing-recovery-',
      );
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => directory.path);
      SharedPreferences.setMockInitialValues({});
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      const storage = MathDrawingStorage();
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
      final original = MathDrawingDocument(name: 'Alpha', drawing: drawing);
      await storage.save(original);
      final folder = Directory('${directory.path}/visual_math');
      final target = folder.listSync().whereType<File>().singleWhere(
        (file) => file.path.endsWith('.vm'),
      );
      final backup = await target.rename('${target.path}.backup');
      expect(await storage.listNames(), ['Alpha']);
      expect((await storage.load('Alpha'))?.name, 'Alpha');
      expect(await backup.exists(), isFalse);

      await target.copy(backup.path);
      final replacement = MathDrawingDocument(
        name: 'Alpha',
        drawing: drawing,
        extensions: const {'updated': true},
      );
      await target.writeAsString(replacement.encode());
      expect((await storage.load('Alpha'))?.extensions['updated'], isTrue);
      await storage.delete('Alpha');
      expect(await storage.listNames(), isEmpty);
    },
  );

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
          .whereType<File>()
          .where((f) => f.path.endsWith('.vm'));
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
