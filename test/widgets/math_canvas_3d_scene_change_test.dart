import 'package:flutter/material.dart' hide Viewport;
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

void main() {
  Future<MathCanvas3DState> setup(
    WidgetTester tester, {
    required VoidCallback onSceneChanged,
    ValueChanged<Object3D>? onObjectCreated,
  }) async {
    final key = GlobalKey<MathCanvas3DState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: MathCanvas3D(
              key: key,
              onSceneChanged: onSceneChanged,
              onObjectCreated: onObjectCreated,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return key.currentState!;
  }

  testWidgets('volume measurement does not notify a scene change', (
    tester,
  ) async {
    var sceneChanges = 0;
    final state = await setup(tester, onSceneChanged: () => sceneChanges++);
    state.setObjects([const Object3D.point(Point3D.origin)]);
    state.setTool(ConstructionTool.volume);
    await tester.pump();
    final beforeAction = sceneChanges;

    await tester.tapAt(const Offset(400, 300));
    await tester.pump();

    expect(sceneChanges, beforeAction);
  });

  testWidgets('first intersection source selection does not notify', (
    tester,
  ) async {
    var sceneChanges = 0;
    final state = await setup(tester, onSceneChanged: () => sceneChanges++);
    state.setObjects([const Object3D.point(Point3D.origin)]);
    state.setTool(ConstructionTool.intersectionPoint);
    await tester.pump();
    final beforeAction = sceneChanges;

    await tester.tapAt(const Offset(400, 300));
    await tester.pump();

    expect(sceneChanges, beforeAction);
    expect(state.objects, hasLength(1));
  });

  testWidgets('visibility mutation notifies exactly once', (tester) async {
    var sceneChanges = 0;
    final state = await setup(tester, onSceneChanged: () => sceneChanges++);
    state.setObjects([const Object3D.point(Point3D.origin)]);
    state.setTool(ConstructionTool.showHideObject);
    await tester.pump();
    final beforeAction = sceneChanges;

    await tester.tapAt(const Offset(400, 300));
    await tester.pump();

    expect(state.objects.single.visible, isFalse);
    expect(sceneChanges, beforeAction + 1);
  });

  testWidgets(
    'created intersections rely on the object callback notification',
    (tester) async {
      var sceneChanges = 0;
      final key = GlobalKey<MathCanvas3DState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: MathCanvas3D(
                key: key,
                currentTool: ConstructionTool.intersectionPoint,
                onSceneChanged: () => sceneChanges++,
                onObjectCreated: (object) {
                  key.currentState!.setObjects([
                    ...key.currentState!.objects,
                    object,
                  ]);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final state = key.currentState!;
      Offset screen(Point3D point) {
        final projected = worldToScreen(
          point,
          state.camera,
          Projection3D.parallel(
            width: 800,
            height: 600,
            scale: state.camera.distance * 0.6,
          ),
        );
        return Offset(projected.x, projected.y);
      }

      const line = Object3D.line(
        Point3D(0, 0, 0),
        Point3D(1, 0, 0),
        lineKind: Line3DKind.line,
      );
      const sphere = Object3D.sphere(center: Point3D.origin, radius: 2);
      state.setObjects([line]);
      await tester.pump();
      await tester.tapAt(screen(const Point3D(0.5, 0, 0)));
      await tester.pump();
      state.setObjects([line, sphere]);
      await tester.pump();
      final beforeAction = sceneChanges;

      await tester.tapAt(screen(Point3D.origin));
      await tester.pump();

      expect(
        state.objects.where((object) => object.type == Object3DType.point),
        hasLength(2),
      );
      expect(sceneChanges, beforeAction + 2);
    },
  );
}
