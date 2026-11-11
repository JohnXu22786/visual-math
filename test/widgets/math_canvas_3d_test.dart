import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MathCanvas3D - initial state', () {
    testWidgets('canvas is ready callback fires', (tester) async {
      bool ready = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: MathCanvas3D(onReady: () => ready = true),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(ready, isTrue);
    });
  });

  group('MathCanvas3D - camera controls', () {
    testWidgets('orbit with drag does not crash', (tester) async {
      final key = GlobalKey<MathCanvas3DState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: MathCanvas3D(key: key),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Simulate a drag gesture (orbit)
      await tester.drag(find.byType(MathCanvas3D), const Offset(50, 30));
      await tester.pump();
      // Should not crash after drag
      expect(find.byType(MathCanvas3D), findsOneWidget);
    });

    testWidgets('resetView restores default camera', (tester) async {
      final key = GlobalKey<MathCanvas3DState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: MathCanvas3D(key: key),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final state = key.currentState!;
      // Get initial camera
      final initialCamera = state.camera;
      // Drag to orbit
      await tester.drag(find.byType(MathCanvas3D), const Offset(100, 50));
      await tester.pump();
      // Camera should have changed
      final afterDrag = state.camera;
      expect(afterDrag.theta, isNot(closeTo(initialCamera.theta, 1e-10)));
      // Reset
      state.resetView();
      await tester.pump();
      // Camera should be back to initial
      expect(state.camera.distance, closeTo(initialCamera.distance, 1e-10));
    });
  });

  group('MathCanvas3D - objects', () {
    testWidgets('renders the initial scene supplied by the host', (
      tester,
    ) async {
      final initialObject = Object3D.point(
        const Point3D(1, 2, 3),
        label: 'host point',
      );
      List<Object3D>? sceneUpdate;
      final key = GlobalKey<MathCanvas3DState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: MathCanvas3D(
                key: key,
                initialObjects: [initialObject],
                initialCamera: const Camera3D(distance: 12),
                onSceneUpdated: (objects) => sceneUpdate = objects,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(key.currentState!.objects, [initialObject]);
      expect(key.currentState!.camera.distance, 12);
      key.currentState!.setCamera(const Camera3D(distance: 20));
      key.currentState!.setObjects(const []);
      await tester.pump();
      expect(sceneUpdate, isEmpty);
      key.currentState!.resetView();
      await tester.pump();
      expect(key.currentState!.camera.distance, 12);
    });

    testWidgets('setSurface adds a surface mesh', (tester) async {
      final key = GlobalKey<MathCanvas3DState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: MathCanvas3D(key: key),
            ),
          ),
        ),
      );
      await tester.pump();

      final state = key.currentState!;
      state.setSurface(
        vertices: [Point3D(0, 0, 0), Point3D(1, 0, 0), Point3D(0, 1, 0)],
        indices: [0, 1, 2],
        color: 0x800000FF,
      );
      await tester.pump();
      expect(state.objectCount, 1);
    });
  });

  group('MathCanvas3D - callbacks', () {
    testWidgets('onSceneUpdated fires after dragging an existing point', (
      tester,
    ) async {
      final key = GlobalKey<MathCanvas3DState>();
      List<Object3D>? sceneUpdate;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: MathCanvas3D(
                key: key,
                initialObjects: const [
                  Object3D.point(Point3D(1, 1, 2), label: 'P'),
                ],
                onSceneUpdated: (objects) => sceneUpdate = objects,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final state = key.currentState!;
      final start = worldToScreen(
        state.objects.single.point,
        state.camera,
        Projection3D.parallel(width: 400, height: 400, scale: 6),
      );
      await tester.tapAt(Offset(start.x, start.y));
      await tester.pump();
      final pointer = await tester.startGesture(
        Offset(start.x, start.y),
        kind: PointerDeviceKind.mouse,
      );
      await pointer.moveBy(const Offset(0, -40));
      await pointer.up();
      await tester.pump();

      expect(sceneUpdate, isNotNull);
      expect(sceneUpdate!.single.point, isNot(const Point3D(1, 1, 2)));
    });

    testWidgets('onSceneUpdated fires after a construction adds an object', (
      tester,
    ) async {
      final key = GlobalKey<MathCanvas3DState>();
      List<Object3D>? sceneUpdate;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: MathCanvas3D(
                key: key,
                currentTool: ConstructionTool.line,
                onSceneUpdated: (objects) => sceneUpdate = objects,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tapAt(const Offset(150, 200));
      await tester.pump();
      await tester.tapAt(const Offset(250, 200));
      await tester.pump();

      expect(sceneUpdate, hasLength(1));
      expect(sceneUpdate!.single.type, Object3DType.line);
    });

    testWidgets('onSceneUpdated returns immutable object geometry', (
      tester,
    ) async {
      final key = GlobalKey<MathCanvas3DState>();
      List<Object3D>? sceneUpdate;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: MathCanvas3D(
                key: key,
                onSceneUpdated: (objects) => sceneUpdate = objects,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final vertices = <Point3D>[
        const Point3D(0, 0, 0),
        const Point3D(1, 0, 0),
        const Point3D(0, 1, 0),
      ];
      key.currentState!.setObjects([
        Object3D.surface(vertices: vertices, indices: [0, 1, 2]),
      ]);

      expect(
        () => sceneUpdate!.single.vertices.add(const Point3D(2, 2, 2)),
        throwsUnsupportedError,
      );
      expect(vertices, hasLength(3));
      expect(key.currentState!.objects.single.vertices, hasLength(3));
    });

    testWidgets('onSceneUpdated fires once for an actual object action', (
      tester,
    ) async {
      var sceneUpdateCount = 0;
      final key = GlobalKey<MathCanvas3DState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: MathCanvas3D(
                key: key,
                currentTool: ConstructionTool.intersectionPoint,
                initialObjects: const [
                  Object3D.point(Point3D(0, 0, 0), label: 'P'),
                ],
                onSceneUpdated: (_) => sceneUpdateCount++,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final state = key.currentState!;
      final projected = worldToScreen(
        state.objects.single.point,
        state.camera,
        Projection3D.parallel(width: 400, height: 400, scale: 6),
      );
      final screenPoint = Offset(projected.x, projected.y);
      await tester.tapAt(screenPoint);
      await tester.pump();
      expect(sceneUpdateCount, 0);

      state.setTool(ConstructionTool.deleteObject);
      await tester.tapAt(screenPoint);
      await tester.pump();
      expect(state.objects, isEmpty);
      expect(sceneUpdateCount, 1);
    });

    testWidgets('onSceneUpdated ignores copy-style actions with no change', (
      tester,
    ) async {
      var legacyCallbackCount = 0;
      var sceneUpdateCount = 0;
      final key = GlobalKey<MathCanvas3DState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: MathCanvas3D(
                key: key,
                currentTool: ConstructionTool.copyStyle,
                initialObjects: const [
                  Object3D.point(Point3D(0, 0, 0), label: 'P'),
                ],
                onSceneChanged: () => legacyCallbackCount++,
                onSceneUpdated: (_) => sceneUpdateCount++,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final state = key.currentState!;
      final projected = worldToScreen(
        state.objects.single.point,
        state.camera,
        Projection3D.parallel(width: 400, height: 400, scale: 6),
      );
      final screenPoint = Offset(projected.x, projected.y);
      await tester.tapAt(screenPoint);
      await tester.pump();
      await tester.tapAt(screenPoint);
      await tester.pump();

      expect(legacyCallbackCount, 2);
      expect(sceneUpdateCount, 0);
    });

    testWidgets('tool commands preserve legacy callback without scene payload', (
      tester,
    ) async {
      var legacyCallbackCount = 0;
      var sceneUpdateCount = 0;
      final key = GlobalKey<MathCanvas3DState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: MathCanvas3D(
                key: key,
                onSceneChanged: () => legacyCallbackCount++,
                onSceneUpdated: (_) => sceneUpdateCount++,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      key.currentState!.performToolCommand(ConstructionTool.showHideLabels);
      expect(legacyCallbackCount, 1);
      expect(sceneUpdateCount, 0);
    });

    testWidgets('onViewportChange fires after resetView', (tester) async {
      bool viewportChanged = false;
      final key = GlobalKey<MathCanvas3DState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 400,
              child: MathCanvas3D(
                key: key,
                onViewportChange: () => viewportChanged = true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      key.currentState!.resetView();
      await tester.pump();

      expect(viewportChanged, isTrue);
    });
  });

  group('MathCanvas3DPainter', () {
    test('painter shouldRepaint returns true when camera changes', () {
      const painter1 = MathCanvas3DPainter(
        cameraDistance: 10,
        cameraTheta: 0,
        cameraPhi: 0.785,
      );
      const painter2 = MathCanvas3DPainter(
        cameraDistance: 20,
        cameraTheta: 0,
        cameraPhi: 0.785,
      );
      expect(painter1.shouldRepaint(painter2), isTrue);
    });

    test('painter shouldRepaint returns false for same values', () {
      const painter1 = MathCanvas3DPainter(
        cameraDistance: 10,
        cameraTheta: 0,
        cameraPhi: 0.785,
      );
      const painter2 = MathCanvas3DPainter(
        cameraDistance: 10,
        cameraTheta: 0,
        cameraPhi: 0.785,
      );
      expect(painter1.shouldRepaint(painter2), isFalse);
    });

    test('painter shouldRepaint returns true when objects change', () {
      const painter1 = MathCanvas3DPainter(
        cameraDistance: 10,
        cameraTheta: 0,
        cameraPhi: 0.785,
        objects: [Object3D.point(Point3D(1, 2, 3))],
        objectsVersion: 1,
      );
      const painter2 = MathCanvas3DPainter(
        cameraDistance: 10,
        cameraTheta: 0,
        cameraPhi: 0.785,
        objectsVersion: 0,
      );
      expect(painter1.shouldRepaint(painter2), isTrue);
    });
  });
}
