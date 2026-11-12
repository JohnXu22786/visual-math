import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

class _CountingCanvas extends Fake implements Canvas {
  int lines = 0;
  final segments = <(Offset, Offset)>[];

  @override
  void drawRect(Rect rect, Paint paint) {}

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    lines++;
    segments.add((p1, p2));
    if (lines > 202) throw StateError('Grid has too many lines');
  }
}

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
    test('grid lines stay on world coordinates after fractional pans', () {
      for (final distance in [10.0, 10.2, 100.0]) {
        for (final target in [
          Point3D.origin,
          const Point3D(0.3, -0.7, 0),
          const Point3D(-2.3, 1.7, 0),
        ]) {
          final canvas = _CountingCanvas();
          MathCanvas3DPainter(
            cameraDistance: distance,
            cameraTarget: target,
            projectionType: ProjectionType.perspective,
            showGrid: true,
            showPlane: false,
            showAxes: false,
          ).paint(canvas, const Size(400, 400));
          final camera = Camera3D(target: target, distance: distance);
          final projection = Projection3D.perspective(width: 400, height: 400);
          final range = distance * 1.5;
          final step = distance == 100 ? 3.0 : 1.0;
          for (final coordinates in [
            (0.0, 0.0),
            (step, step),
            (
              ((target.y + range) / step).floor() * step,
              ((target.x + range) / step).floor() * step,
            ),
          ]) {
            for (final endpoints in [
              (
                Point3D(target.x - range, coordinates.$1, 0),
                Point3D(target.x + range, coordinates.$1, 0),
              ),
              (
                Point3D(coordinates.$2, target.y - range, 0),
                Point3D(coordinates.$2, target.y + range, 0),
              ),
            ]) {
              final a = worldToScreen(endpoints.$1, camera, projection);
              final b = worldToScreen(endpoints.$2, camera, projection);
              expect(
                canvas.segments.any(
                  (line) =>
                      (line.$1 - Offset(a.x, a.y)).distance < 1e-6 &&
                      (line.$2 - Offset(b.x, b.y)).distance < 1e-6,
                ),
                isTrue,
              );
            }
          }
        }
      }
    });

    test('grid rendering remains bounded at large camera distances', () {
      for (final distance in [10.0, 10000.0, 1e20, double.maxFinite]) {
        final canvas = _CountingCanvas();
        MathCanvas3DPainter(
          cameraDistance: distance,
          cameraTarget: const Point3D(1e20, 1e20, 0),
          showGrid: true,
          showPlane: false,
          showAxes: false,
        ).paint(canvas, const Size(400, 400));
        expect(canvas.lines, inInclusiveRange(1, 202));
      }
    });

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
