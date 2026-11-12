@TestOn('browser')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_browser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visual_math/src/models/math_drawing_storage_web.dart'
    as backend;
import 'package:visual_math/visual_math.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'recovers colliding legacy drawings in IndexedDB without changing payloads',
    () async {
      final database = await idbFactoryBrowser.open(
        'visual_math_documents',
        version: 1,
        onUpgradeNeeded: (event) =>
            event.database.createObjectStore('drawings'),
      );
      final clear = database.transaction('drawings', idbModeReadWrite);
      await clear.objectStore('drawings').clear();
      await clear.completed;
      database.close();
      addTearDown(() async {
        final db = await idbFactoryBrowser.open('visual_math_documents');
        final transaction = db.transaction('drawings', idbModeReadWrite);
        await transaction.objectStore('drawings').clear();
        await transaction.completed;
        db.close();
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
      await backend.saveDocument(
        MathDrawingDocument(name: 'Same', drawing: drawing),
        overwrite: false,
      );
      await backend.saveDocument(
        MathDrawingDocument(name: 'Same (recovered 1)', drawing: drawing),
        overwrite: false,
      );
      final legacy = MathDrawingDocument(
        name: 'Same',
        drawing: drawing,
        extensions: const {'legacy': true},
      ).encode().replaceFirst('{', '{"opaque":900719925474099312345,');
      const key = 'visual_math.documents.v1';
      SharedPreferences.setMockInitialValues({
        key: jsonEncode({'Same': legacy}),
      });

      const storage = MathDrawingStorage();
      expect(await storage.listNames(), [
        'Same',
        'Same (recovered 1)',
        'Same (recovered 2)',
      ]);
      expect((await storage.load('Same'))?.extensions['legacy'], isNull);
      final recovered = await storage.load('Same (recovered 2)');
      expect(recovered?.name, 'Same (recovered 2)');
      expect(recovered?.extensions['legacy'], isTrue);
      expect(await backend.loadDocumentSource('Same (recovered 2)'), legacy);
      expect((await SharedPreferences.getInstance()).getString(key), isNull);
    },
  );
}
