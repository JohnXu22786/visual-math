import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visual_math/visual_math.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('stores named documents and requires explicit overwrite', () async {
    SharedPreferences.setMockInitialValues({});
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
    await expectLater(
      storage.save(MathDrawingDocument(name: 'Alpha', drawing: drawing)),
      throwsStateError,
    );
    await storage.save(
      MathDrawingDocument(name: 'Alpha', drawing: drawing),
      overwrite: true,
    );
  });
}
