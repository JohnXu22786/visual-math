import 'package:flutter/material.dart' hide Viewport;
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_math/visual_math.dart';

void main() {
  const center = Point3D(1.2666666666666667e154, -5e154, -8e152);
  const camera = Camera3D(
    target: Point3D.origin,
    distance: 1e155,
    theta: 0,
    phi: 0,
  );

  Object3D largeTriangle() => Object3D.surface(
    vertices: const [
      Point3D(4.94e154, -5e154, -1.14e154),
      Point3D(3.94e154, -5e154, -2.94e154),
      Point3D(-5.08e154, -5e154, 3.84e154),
    ],
    indices: const [0, 1, 2],
  );

  Future<MathCanvas3DState> setup(
    WidgetTester tester, {
    Camera3D camera = camera,
  }) async {
    final key = GlobalKey<MathCanvas3DState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MathCanvas3D(key: key, currentTool: ConstructionTool.move),
        ),
      ),
    );
    final state = key.currentState!;
    state.setCamera(camera);
    await tester.pump();
    return state;
  }

  Offset screen(MathCanvas3DState state, Point3D point) {
    final projected = worldToScreen(
      point,
      state.camera,
      state.projectionType == ProjectionType.parallel
          ? Projection3D.parallel(
              width: 800,
              height: 600,
              scale: state.camera.distance * 0.6,
            )
          : Projection3D.perspective(width: 800, height: 600, fov: 60),
    );
    return Offset(projected.x, projected.y);
  }

  testWidgets('large finite surface triangle can be selected', (tester) async {
    final state = await setup(tester);
    final surface = largeTriangle();
    state.setObjects([surface]);
    state.setTool(ConstructionTool.move);
    await tester.pump();

    await tester.tapAt(screen(state, center));
    await tester.pump();

    expect(state.selectedObject, same(surface));
  });

  testWidgets('triangle with extreme finite aspect ratio remains selectable', (
    tester,
  ) async {
    const camera = Camera3D(
      target: Point3D.origin,
      distance: 1e200,
      theta: 0,
      phi: 0,
    );
    final state = await setup(tester, camera: camera);
    final surface = Object3D.surface(
      vertices: const [
        Point3D(-5e199, -5e199, 0),
        Point3D(5e199, -5e199, 0),
        Point3D(-5e199, -5e199, 1e-200),
      ],
      indices: const [0, 1, 2],
    );
    state.setObjects([surface]);
    state.setTool(ConstructionTool.move);
    await tester.pump();

    await tester.tapAt(screen(state, const Point3D(0, -5e199, 0)));
    await tester.pump();

    expect(state.selectedObject, same(surface));
  });

  testWidgets('large opaque triangle occludes a point behind it', (
    tester,
  ) async {
    final state = await setup(tester);
    final forward = (camera.target - camera.position).normalized();
    final hiddenPoint = center + forward * 3e154;
    final point = Object3D.point(hiddenPoint);
    state.setObjects([point]);
    state.setTool(ConstructionTool.move);
    await tester.pump();
    await tester.tapAt(screen(state, hiddenPoint));
    await tester.pump();
    expect(state.selectedPoint, same(point));

    state.setObjects([largeTriangle(), point]);
    await tester.pump();
    await tester.tapAt(screen(state, hiddenPoint));
    await tester.pump();

    expect(state.selectedPoint, isNull);
  });
}
